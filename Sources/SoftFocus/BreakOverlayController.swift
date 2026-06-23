import AppKit

/// A borderless window normally can't become key, so keystrokes would still reach
/// the app behind it. Overriding this lets the overlay swallow the keyboard while
/// the break is up.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// The full-screen "look away" overlay. Covers every display with a dimmed
/// window, shows a message + live countdown, and a Skip button. While it's up it
/// also blocks app-switching (Cmd-Tab) so you can't sneak back to your tabs.
final class BreakOverlayController {
    private var windows: [NSWindow] = []
    private var countdownLabels: [NSTextField] = []
    private var timer: Timer?
    private var remaining: TimeInterval = 0
    var onSkip: (() -> Void)?

    /// Show the overlay for `duration` seconds (one window per screen).
    func show(duration: TimeInterval) {
        hide() // clear anything stale first
        remaining = duration

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.85)
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            let label = makeCountdownLabel()
            let content = makeContentView(in: screen.frame, countdown: label, showSkip: screen == NSScreen.main)
            window.contentView = content
            window.makeKeyAndOrderFront(nil)

            windows.append(window)
            countdownLabels.append(label)
        }

        NSApp.activate(ignoringOtherApps: true)
        // Block Cmd-Tab while the break is up. (Skip stays as the escape hatch.)
        NSApp.presentationOptions = [.disableProcessSwitching]
        updateCountdownText()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.remaining -= 1
            self.updateCountdownText()
            if self.remaining <= 0 { self.hide() }
        }
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        NSApp.presentationOptions = [] // re-enable Cmd-Tab
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        countdownLabels.removeAll()
    }

    var isShowing: Bool { !windows.isEmpty }

    // MARK: - View building

    private func makeContentView(in frame: NSRect, countdown: NSTextField, showSkip: Bool) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))

        let title = NSTextField(labelWithString: "Look away from your screen")
        title.font = .systemFont(ofSize: 36, weight: .semibold)
        title.textColor = .white
        title.alignment = .center

        let subtitle = NSTextField(labelWithString: "Rest your eyes — focus on something far away")
        subtitle.font = .systemFont(ofSize: 18, weight: .regular)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.7)
        subtitle.alignment = .center

        let stack = NSStackView(views: [title, subtitle, countdown])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        if showSkip {
            let skip = NSButton(title: "Skip break", target: self, action: #selector(skipTapped))
            skip.bezelStyle = .rounded
            skip.controlSize = .large
            stack.addArrangedSubview(skip)
        }

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    private func makeCountdownLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 64, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        return label
    }

    private func updateCountdownText() {
        let secs = max(0, Int(remaining.rounded()))
        countdownLabels.forEach { $0.stringValue = "\(secs)" }
    }

    @objc private func skipTapped() {
        hide()
        onSkip?()
    }
}
