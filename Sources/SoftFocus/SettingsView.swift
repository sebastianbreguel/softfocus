import SwiftUI

/// Calm, native preferences pane. Reads/writes the same UserDefaults keys that
/// `Settings` uses, so changes take effect on the next tick. Strings localize
/// live: changing `language` re-renders the view.
struct SettingsView: View {
    @AppStorage("workMinutes") private var workMinutes: Double = 20
    @AppStorage("breakSeconds") private var breakSeconds: Double = 20
    @AppStorage("nudgeMinutes") private var nudgeMinutes: Double = 5
    @AppStorage("blinkEnabled") private var blinkEnabled: Bool = true
    @AppStorage("postureEnabled") private var postureEnabled: Bool = true
    @AppStorage("longBreaksEnabled") private var longBreaksEnabled: Bool = true
    @AppStorage("longBreakEvery") private var longBreakEvery: Double = 4
    @AppStorage("longBreakMinutes") private var longBreakMinutes: Double = 5
    @AppStorage("warnEnabled") private var warnEnabled: Bool = true
    @AppStorage("soundEnabled") private var soundEnabled: Bool = true
    @AppStorage("tipsEnabled") private var tipsEnabled: Bool = true
    @AppStorage("customMessage") private var customMessage: String = ""
    @AppStorage("meetingAutoDetect") private var meetingAutoDetect: Bool = true
    @AppStorage("language") private var language: String = "system"

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    @State private var gcalConnected = GoogleCalendar.shared.isConnected
    @State private var gcalConnecting = false
    @State private var gcalStatus = ""

    // Calm, muted teal: the one memorable accent, used only on live values + controls.
    private static let accent = Color(red: 0.18, green: 0.56, blue: 0.55)

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                card("Breaks") {
                    durationRow("Work", value: $workMinutes, unit: "min", range: 1...120, step: 1)
                    Divider().opacity(0.5)
                    durationRow("Break", value: $breakSeconds, unit: "sec", range: 5...300, step: 5)
                    Divider().opacity(0.5)
                    Toggle(Loc.t("Long break now and then"), isOn: $longBreaksEnabled)
                    if longBreaksEnabled {
                        Stepper(String(format: Loc.t("Every %d breaks"), Int(longBreakEvery)),
                                value: $longBreakEvery, in: 2...8)
                        durationRow("Long break", value: $longBreakMinutes, unit: "min", range: 1...30, step: 1)
                    }
                    Divider().opacity(0.5)
                    Toggle(Loc.t("Warn me before a break"), isOn: $warnEnabled)
                }

                card("Nudges") {
                    durationRow("Every", value: $nudgeMinutes, unit: "min", range: 1...60, step: 1)
                    Divider().opacity(0.5)
                    Toggle(Loc.t("Blink reminders"), isOn: $blinkEnabled)
                    Toggle(Loc.t("Posture reminders"), isOn: $postureEnabled)
                }

                card("General") {
                    Picker(Loc.t("Language"), selection: $language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang.rawValue)
                        }
                    }
                    Divider().opacity(0.5)
                    Toggle(Loc.t("Pause when camera is on (meetings)"), isOn: $meetingAutoDetect)
                    Divider().opacity(0.5)
                    Toggle(Loc.t("Launch at login"), isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in LaunchAtLogin.set(newValue) }
                    Toggle(Loc.t("Chime on break"), isOn: $soundEnabled)
                    Toggle(Loc.t("Rotating eye-care tips"), isOn: $tipsEnabled)
                    TextField(Loc.t("Custom break message (optional)"), text: $customMessage)
                        .textFieldStyle(.roundedBorder)
                }

                card("Google Calendar") {
                    if gcalConnected {
                        HStack {
                            Text(Loc.t("Connected")).foregroundStyle(Self.accent)
                            Spacer()
                            Button(Loc.t("Disconnect")) {
                                GoogleCalendar.shared.disconnect()
                                gcalConnected = false
                                gcalStatus = ""
                            }
                        }
                    } else {
                        Text(Loc.t("Pause breaks during calendar meetings."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(Loc.t(gcalConnecting ? "Connecting…" : "Connect Google Calendar")) {
                            gcalConnecting = true
                            gcalStatus = ""
                            Task {
                                do {
                                    try await GoogleCalendar.shared.connect()
                                    await MainActor.run { gcalConnected = true; gcalConnecting = false }
                                } catch {
                                    await MainActor.run { gcalStatus = error.localizedDescription; gcalConnecting = false }
                                }
                            }
                        }
                        .disabled(gcalConnecting)
                    }
                    if !gcalStatus.isEmpty {
                        Text(gcalStatus).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .padding(24)
            .toggleStyle(.switch)
            .tint(Self.accent)
        }
        .frame(width: 380, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Self.accent)
                .frame(width: 56, height: 56)
                .background(Self.accent.opacity(0.12), in: Circle())
            Text("SoftFocus")
                .font(.title3.weight(.semibold))
            Text(Loc.t("Take care of your eyes"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    /// A labelled slider whose value is also an editable numeric field: type a
    /// number or drag, kept in sync and clamped/snapped to the range.
    private func durationRow(
        _ title: String,
        value: Binding<Double>,
        unit: String,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        // Edits go through here: clamp to range, then snap to the slider's step.
        let number = Binding<Int>(
            get: { Int(value.wrappedValue) },
            set: { newValue in
                let clamped = min(max(Double(newValue), range.lowerBound), range.upperBound)
                value.wrappedValue = (clamped / step).rounded() * step
            }
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(Loc.t(title))
                Spacer()
                TextField("", value: number, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .font(.headline)
                    .foregroundStyle(Self.accent)
                Text(Loc.t(unit))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .tint(Self.accent)
        }
    }

    private func card<Content: View>(
        _ title: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Loc.t(title).uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }
}
