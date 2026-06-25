import AppKit
import CryptoKit
import Foundation
import Network

/// A timed calendar event. Sendable so it can cross the async boundary.
struct CalendarEvent: Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
}

/// Google Calendar connection via OAuth 2.0 (PKCE + loopback redirect, the flow
/// Google recommends for native/desktop apps). Reads the primary calendar to tell
/// whether a busy event is happening right now. Needs a Google Cloud "Desktop app"
/// OAuth client (Client ID + Secret), provided by the user in Settings.
final class GoogleCalendar {
    static let shared = GoogleCalendar()
    private init() {}

    enum GCalError: LocalizedError {
        case missingCredentials, loopback, tokenExchange, http(Int)
        var errorDescription: String? {
            switch self {
            case .missingCredentials: return "Google Calendar isn't set up in this build."
            case .loopback: return "Could not capture the sign-in redirect."
            case .tokenExchange: return "Google did not return tokens."
            case .http(let c): return "Google returned HTTP \(c)."
            }
        }
    }

    private let scope = "https://www.googleapis.com/auth/calendar.readonly"
    private let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"

    private var accessToken: String?
    private var accessExpiry: Date = .distantPast

    // Credentials are baked into the build (GoogleConfig); only the per-user refresh
    // token is stored, in the Keychain.
    var clientID: String { GoogleConfig.clientID }
    var clientSecret: String { GoogleConfig.clientSecret }
    var isConfigured: Bool { GoogleConfig.isConfigured }
    // NOTE: dev builds are ad-hoc signed and re-signed on every rebuild, which
    // breaks Keychain access. UserDefaults survives rebuilds. Move back to
    // Keychain once the app is properly signed for release.
    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "gcalRefreshToken") }
        set { UserDefaults.standard.set(newValue, forKey: "gcalRefreshToken") }
    }
    var isConnected: Bool { refreshToken != nil }

    // MARK: - Connect / disconnect

    func connect() async throws {
        guard !clientID.isEmpty, !clientSecret.isEmpty else { throw GCalError.missingCredentials }
        let verifier = Self.randomURLSafe(64)
        let (code, redirectURI) = try await runLoopbackAuth(challenge: Self.codeChallenge(for: verifier))

        let json = try await postForm(tokenEndpoint, [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let expires = json["expires_in"] as? Double else { throw GCalError.tokenExchange }
        refreshToken = refresh
        accessToken = access
        accessExpiry = Date().addingTimeInterval(expires - 60)
    }

    func disconnect() {
        refreshToken = nil
        accessToken = nil
        accessExpiry = .distantPast
    }

    // MARK: - Meeting check

    /// Timed events from now until `window` seconds ahead (skips all-day/cancelled).
    func upcomingEvents(within window: TimeInterval) async -> [CalendarEvent] {
        guard isConnected else { return [] }
        do {
            let token = try await validAccessToken()
            let now = Date()
            let fmt = ISO8601DateFormatter()
            var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
            comps.queryItems = [
                .init(name: "timeMin", value: fmt.string(from: now.addingTimeInterval(-60))),
                .init(name: "timeMax", value: fmt.string(from: now.addingTimeInterval(window))),
                .init(name: "singleEvents", value: "true"),
                .init(name: "orderBy", value: "startTime"),
                .init(name: "maxResults", value: "10"),
            ]
            var req = URLRequest(url: comps.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = obj["items"] as? [[String: Any]] else { return [] }
            return items.compactMap { ev in
                if (ev["status"] as? String) == "cancelled" { return nil }
                guard let id = ev["id"] as? String,
                      let start = (ev["start"] as? [String: Any])?["dateTime"] as? String,
                      let end = (ev["end"] as? [String: Any])?["dateTime"] as? String,
                      let s = fmt.date(from: start), let e = fmt.date(from: end) else { return nil }
                let title = (ev["summary"] as? String) ?? "Meeting"
                return CalendarEvent(id: id, title: title, start: s, end: e)
            }
        } catch {
            return []
        }
    }

    // MARK: - Tokens

    private func validAccessToken() async throws -> String {
        if let t = accessToken, Date() < accessExpiry { return t }
        guard let refresh = refreshToken else { throw GCalError.tokenExchange }
        let json = try await postForm(tokenEndpoint, [
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ])
        guard let access = json["access_token"] as? String,
              let expires = json["expires_in"] as? Double else { throw GCalError.tokenExchange }
        accessToken = access
        accessExpiry = Date().addingTimeInterval(expires - 60)
        return access
    }

    private func postForm(_ url: String, _ params: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = params.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw GCalError.http((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Loopback OAuth

    private func runLoopbackAuth(challenge: String) async throws -> (String, String) {
        // Capture only the values the closures need, not `self` (Sendable-clean).
        let clientID = self.clientID
        let scope = self.scope
        let authEndpoint = self.authEndpoint
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(String, String), Error>) in
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                var finished = false
                let finish: (Result<(String, String), Error>) -> Void = { result in
                    if finished { return }
                    finished = true
                    listener.cancel()
                    cont.resume(with: result)
                }
                let redirectURI: @Sendable () -> String = { "http://127.0.0.1:\(listener.port?.rawValue ?? 0)" }
                listener.stateUpdateHandler = { state in
                    guard case .ready = state else { return }
                    var comps = URLComponents(string: authEndpoint)!
                    comps.queryItems = [
                        .init(name: "client_id", value: clientID),
                        .init(name: "redirect_uri", value: redirectURI()),
                        .init(name: "response_type", value: "code"),
                        .init(name: "scope", value: scope),
                        .init(name: "code_challenge", value: challenge),
                        .init(name: "code_challenge_method", value: "S256"),
                        .init(name: "access_type", value: "offline"),
                        .init(name: "prompt", value: "consent"),
                    ]
                    if let url = comps.url { NSWorkspace.shared.open(url) }
                }
                listener.newConnectionHandler = { conn in
                    conn.start(queue: .main)
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                        let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                        let firstLine = request.split(separator: "\r\n").first.map(String.init) ?? ""
                        let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                        let code = URLComponents(string: "http://x\(path)")?.queryItems?.first { $0.name == "code" }?.value
                        let html = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n<html><body style='font-family:-apple-system;text-align:center;padding-top:80px'><h2>SoftFocus connected</h2><p>You can close this tab.</p></body></html>"
                        conn.send(content: html.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                        if let code { finish(.success((code, redirectURI()))) } else { finish(.failure(GCalError.loopback)) }
                    }
                }
                listener.start(queue: .main)
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: - PKCE helpers

    private static func randomURLSafe(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
