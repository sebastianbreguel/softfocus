import SwiftUI

/// Preferences pane in the "Warm Night" theme from the design doc. Reads/writes
/// the same UserDefaults keys that `Settings` uses, so changes take effect on the
/// next tick. Strings localize live: changing `language` re-renders the view.
struct SettingsView: View {
    @AppStorage("workMinutes") private var workMinutes: Double = 20
    @AppStorage("breakSeconds") private var breakSeconds: Double = 20
    @AppStorage("nudgeMinutes") private var nudgeMinutes: Double = 5
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

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header

                card("Breaks") {
                    durationRow("Work interval", value: $workMinutes, unit: "min", range: 1...120, step: 1)
                    divider
                    durationRow("Break length", value: $breakSeconds, unit: "sec", range: 5...300, step: 5)
                    divider
                    toggle("Long break now and then", $longBreaksEnabled)
                    if longBreaksEnabled {
                        HStack {
                            Text(String(format: Loc.t("Every %d breaks"), Int(longBreakEvery)))
                                .foregroundStyle(Theme.textC)
                            Spacer()
                            Stepper("", value: $longBreakEvery, in: 2...8).labelsHidden()
                        }
                        durationRow("Long break", value: $longBreakMinutes, unit: "min", range: 1...30, step: 1)
                    }
                    divider
                    toggle("Warn me before a break", $warnEnabled)
                }

                card("Nudges") {
                    durationRow("Reminders every", value: $nudgeMinutes, unit: "min", range: 1...60, step: 1)
                    divider
                    toggle("Posture reminders", $postureEnabled)
                }

                card("General") {
                    HStack {
                        Text(Loc.t("Language")).foregroundStyle(Theme.textC)
                        Spacer()
                        HStack(spacing: 2) {
                            ForEach(AppLanguage.allCases) { lang in
                                let selected = language == lang.rawValue
                                Text(lang.short)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(selected ? Theme.btnTextC : Theme.text2C)
                                    .padding(.vertical, 4).padding(.horizontal, 12)
                                    .background(selected ? Theme.accentC : .clear, in: RoundedRectangle(cornerRadius: 7))
                                    .contentShape(Rectangle())
                                    .onTapGesture { language = lang.rawValue }
                            }
                        }
                        .padding(3)
                        .background(Theme.trackC, in: RoundedRectangle(cornerRadius: 9))
                    }
                    divider
                    toggle("Pause when camera is on (meetings)", $meetingAutoDetect)
                    divider
                    toggle("Launch at login", $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in LaunchAtLogin.set(newValue) }
                    toggle("Chime on break", $soundEnabled)
                    toggle("Rotating eye-care tips", $tipsEnabled)
                    TextField(Loc.t("Custom break message…"), text: $customMessage)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.textC)
                        .padding(.vertical, 9).padding(.horizontal, 12)
                        .background(Theme.trackC, in: RoundedRectangle(cornerRadius: 9))
                }

                card("Google Calendar") {
                    if gcalConnected {
                        HStack {
                            Circle().fill(Theme.accentC).frame(width: 8, height: 8)
                            Text(Loc.t("Connected")).foregroundStyle(Theme.accentC).fontWeight(.semibold)
                            Spacer()
                            Button(Loc.t("Disconnect")) {
                                GoogleCalendar.shared.disconnect()
                                gcalConnected = false
                                gcalStatus = ""
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.text2C)
                            .padding(.vertical, 7).padding(.horizontal, 14)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderC))
                        }
                    } else {
                        Text(Loc.t("Pause breaks during calendar meetings."))
                            .font(.caption)
                            .foregroundStyle(Theme.text3C)
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
            .padding(18)
            .toggleStyle(.switch)
            .tint(Theme.accentC)
        }
        .frame(width: 392, height: 640)
        .background(
            LinearGradient(colors: [Theme.bgTopC, Theme.bgMidC, Theme.bgBotC],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    // MARK: - Pieces

    private var divider: some View {
        Rectangle().fill(Theme.borderC).frame(height: 1)
    }

    private func toggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            Text(Loc.t(title)).foregroundStyle(Theme.textC)
            Spacer()
            Toggle("", isOn: binding).labelsHidden()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye")
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(Theme.accentC)
                .frame(width: 42, height: 42)
                .background(Theme.accentDimC, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 1) {
                Text("SoftFocus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textC)
                Text(Loc.t("Take care of your eyes"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3C)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// A labelled slider whose value is also an editable numeric field, shown as
    /// an amber "pill" matching the design doc. Clamped/snapped to the range.
    private func durationRow(
        _ title: String,
        value: Binding<Double>,
        unit: String,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        let number = Binding<Int>(
            get: { Int(value.wrappedValue) },
            set: { newValue in
                let clamped = min(max(Double(newValue), range.lowerBound), range.upperBound)
                value.wrappedValue = (clamped / step).rounded() * step
            }
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(Loc.t(title)).foregroundStyle(Theme.textC).fontWeight(.semibold)
                Spacer()
                HStack(spacing: 4) {
                    TextField("", value: number, format: .number)
                        .textFieldStyle(.plain)
                        .frame(width: 34)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accentC)
                    Text(Loc.t(unit)).font(.system(size: 11)).foregroundStyle(Theme.text3C)
                }
                .padding(.vertical, 4).padding(.horizontal, 10)
                .background(Theme.accentDimC, in: RoundedRectangle(cornerRadius: 8))
            }
            Slider(value: value, in: range, step: step)
                .tint(Theme.accentC)
        }
    }

    private func card<Content: View>(
        _ title: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Loc.t(title).uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.text3C)
                .tracking(1.3)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Theme.panel2C, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.borderC))
    }
}
