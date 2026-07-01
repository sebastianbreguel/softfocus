import SwiftUI

/// Live state + action hooks for the menu-bar quick panel (design-doc state 2).
/// AppDelegate updates the @Published values each tick and wires the closures.
final class PanelModel: ObservableObject {
    @Published var bigText = ""        // "Next break in 16:42"
    @Published var subText = ""        // "Look 20 ft away · 20 sec"
    @Published var progress = 0.0      // 0…1 ring fill (time until next break)
    @Published var paused = false
    @Published var meeting = false

    var onTakeBreak: () -> Void = {}
    var onSkip: () -> Void = {}
    var onSnooze: () -> Void = {}
    var onPause: () -> Void = {}
    var onMeeting: () -> Void = {}
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}
}

/// The quick panel popover — mirrors the "Warm Night" design doc: progress ring,
/// primary "Take a break now" button, Skip / Snooze, and the toggles/links.
struct QuickPanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            // Header: ring + eye, status text.
            HStack(spacing: 13) {
                ZStack {
                    Circle().stroke(Theme.trackC, lineWidth: 4)
                    Circle().trim(from: 0, to: model.progress)
                        .stroke(Theme.accentC, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "eye")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(Theme.accentC)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.bigText)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.textC)
                    Text(model.subText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text3C)
                }
                Spacer()
            }
            .padding(16)

            divider

            VStack(spacing: 8) {
                Button(action: model.onTakeBreak) {
                    HStack(spacing: 9) {
                        Image(systemName: "cup.and.saucer.fill")
                        Text(Loc.t("Take a break now")).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accentC, in: RoundedRectangle(cornerRadius: 11))
                    .foregroundStyle(Theme.btnTextC)
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    secondary("Skip break", "forward.end.fill", action: model.onSkip)
                    secondary("Snooze 5 min", "clock", action: model.onSnooze)
                }
            }
            .padding(13)

            divider

            VStack(spacing: 0) {
                row(model.paused ? "Resume" : "Pause", "pause.fill", on: model.paused, action: model.onPause)
                row("Meeting mode", "video.fill", on: model.meeting, action: model.onMeeting)
            }
            .padding(.vertical, 5).padding(.horizontal, 7)

            divider

            VStack(spacing: 0) {
                row("Settings…", "gearshape", key: "⌘,", action: model.onSettings)
                row("Quit SoftFocus", "power", key: "⌘Q", action: model.onQuit)
            }
            .padding(.vertical, 5).padding(.horizontal, 7)
        }
        .frame(width: 300)
        .background(
            LinearGradient(colors: [Theme.bgTopC, Theme.bgMidC, Theme.bgBotC],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private var divider: some View {
        Rectangle().fill(Theme.borderC).frame(height: 1)
    }

    private func secondary(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                Text(Loc.t(title)).font(.system(size: 12.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(Theme.text2C)
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, _ icon: String, on: Bool = false, key: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(on ? Theme.accentC : Theme.text2C)
                    .frame(width: 16)
                Text(Loc.t(title))
                    .font(.system(size: 13))
                    .foregroundStyle(on ? Theme.accentC : Theme.textC)
                Spacer()
                if let key {
                    Text(key).font(.system(size: 11)).foregroundStyle(Theme.text3C)
                }
            }
            .padding(.vertical, 9).padding(.horizontal, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
