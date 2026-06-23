import SwiftUI
import SoftFocusCore

/// A tiny SwiftUI preferences form. Reads/writes the same UserDefaults that
/// `Settings` uses, so changes take effect on the next tick.
struct SettingsView: View {
    @AppStorage("workMinutes") private var workMinutes: Double = 20
    @AppStorage("breakSeconds") private var breakSeconds: Double = 20
    @AppStorage("nudgeMinutes") private var nudgeMinutes: Double = 5
    @AppStorage("blinkEnabled") private var blinkEnabled: Bool = true
    @AppStorage("postureEnabled") private var postureEnabled: Bool = true

    var body: some View {
        Form {
            Section("Breaks") {
                Stepper("Work for \(Int(workMinutes)) min", value: $workMinutes, in: 1...120)
                Stepper("Break for \(Int(breakSeconds)) sec", value: $breakSeconds, in: 5...300, step: 5)
            }
            Section("Nudges") {
                Stepper("Every \(Int(nudgeMinutes)) min", value: $nudgeMinutes, in: 1...60)
                Toggle("Blink reminders", isOn: $blinkEnabled)
                Toggle("Posture reminders", isOn: $postureEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 320, height: 320)
    }
}
