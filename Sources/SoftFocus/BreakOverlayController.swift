import AppKit

/// A borderless window normally can't become key, so keystrokes would still reach
/// the app behind it. Overriding this lets the overlay swallow the keyboard while
/// the break is up.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// The full-screen "look away" overlay. Covers every display with a dimmed
/// window, shows a title/subtitle + live countdown, and Skip / Snooze buttons.
/// The key window swallows keystrokes so they don't reach apps behind it.
final class BreakOverlayController {
    private var windows: [NSWindow] = []
    private var countdownLabels: [NSTextField] = []
    private var timer: Timer?
    private var remaining: TimeInterval = 0
    var onSkip: (() -> Void)?
    var onSnooze: (() -> Void)?

    /// Show the overlay for `duration` seconds (one window per screen).
    func show(duration: TimeInterval, title: String, subtitle: String) {
        hide() // clear anything stale first
        remaining = duration

        for screen in NSScreen.screens {
            let isMain = (screen == NSScreen.main)
            // NOTE: do NOT pass `screen:` here — that makes contentRect relative to
            // the screen's origin, pushing windows on non-primary displays off-screen.
            // We set the frame explicitly in global coordinates below instead.
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.85)
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.setFrame(screen.frame, display: false) // explicit global frame

            let label = makeCountdownLabel()
            label.stringValue = "\(max(0, Int(remaining.rounded())))" // seed before layout so it isn't clipped to width 0
            let content = makeContentView(in: screen.frame, title: title, subtitle: subtitle, countdown: label, showControls: isMain)
            window.contentView = content
            window.orderFrontRegardless() // show on every display, even non-active spaces
            if isMain { window.makeKey() } // keyboard focus + buttons on the main one

            windows.append(window)
            countdownLabels.append(label)
        }

        NSApp.activate(ignoringOtherApps: true)
        updateCountdownText()

        // Schedule in `.common` mode: a `.default`-mode timer freezes while the
        // key overlay window keeps the run loop in event-tracking mode.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.remaining -= 1
            self.updateCountdownText()
            if self.remaining <= 0 { self.hide() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        countdownLabels.removeAll()
    }

    var isShowing: Bool { !windows.isEmpty }

    // MARK: - View building

    private func makeContentView(in frame: NSRect, title: String, subtitle: String, countdown: NSTextField, showControls: Bool) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 36, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 18, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        subtitleLabel.alignment = .center

        let stack = NSStackView(views: [titleLabel, subtitleLabel, countdown])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        if showControls {
            let snooze = NSButton(title: "Snooze 5 min", target: self, action: #selector(snoozeTapped))
            snooze.bezelStyle = .rounded
            snooze.controlSize = .large
            let skip = NSButton(title: "Skip break", target: self, action: #selector(skipTapped))
            skip.bezelStyle = .rounded
            skip.controlSize = .large
            let buttons = NSStackView(views: [snooze, skip])
            buttons.orientation = .horizontal
            buttons.spacing = 12
            stack.addArrangedSubview(buttons)
        }

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        return view
    }

    private func makeCountdownLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "0")
        label.font = .monospacedDigitSystemFont(ofSize: 64, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        // Never let the stack compress/clip the number to zero width.
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
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

    @objc private func snoozeTapped() {
        hide()
        onSnooze?()
    }
}
