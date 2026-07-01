import AppKit

/// A borderless window normally can't become key, so keystrokes would still reach
/// the app behind it. Overriding this lets the overlay swallow the keyboard while
/// the break is up.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// A rounded "pill" button matching the design doc — filled amber or outlined.
private final class PillButton: NSView {
    private let onClick: () -> Void
    init(title: String, filled: Bool, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 19
        layer?.backgroundColor = (filled ? Theme.accent : NSColor.clear).cgColor
        if !filled {
            layer?.borderWidth = 1
            layer?.borderColor = Theme.border.cgColor
        }
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13.5, weight: .semibold)
        label.textColor = filled ? Theme.btnText : Theme.text2
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            leadingAnchor.constraint(equalTo: label.leadingAnchor, constant: -22),
            trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: 22),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) { onClick() }
}

/// The full-screen "look away" overlay. Covers every display, shows the Warm
/// Night design: radial gradient, a breathing amber orb behind a progress ring,
/// the live countdown, title/subtitle, and Skip / Postpone pills.
final class BreakOverlayController {
    private var windows: [NSWindow] = []
    private var countdownLabels: [NSTextField] = []
    private var progressRings: [CAShapeLayer] = []
    private var timer: Timer?
    private var remaining: TimeInterval = 0
    private var duration: TimeInterval = 1
    var onSkip: (() -> Void)?
    var onSnooze: (() -> Void)?

    func show(duration: TimeInterval, title: String, subtitle: String, isLong: Bool) {
        hide()
        remaining = duration
        self.duration = max(1, duration)

        for screen in NSScreen.screens {
            let isMain = (screen == NSScreen.main)
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.isOpaque = true
            window.backgroundColor = Theme.bgBot
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.setFrame(screen.frame, display: false)

            let label = makeCountdownLabel()
            let ring = CAShapeLayer()
            label.stringValue = Self.countdownString(max(0, Int(remaining.rounded())))
            let content = makeContentView(in: screen.frame, title: title, subtitle: subtitle, isLong: isLong, countdown: label, ring: ring, showControls: isMain)
            window.contentView = content
            window.orderFrontRegardless()
            if isMain { window.makeKey() }

            windows.append(window)
            countdownLabels.append(label)
            progressRings.append(ring)
        }

        NSApp.activate(ignoringOtherApps: true)
        updateCountdownText()

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
        progressRings.removeAll()
    }

    var isShowing: Bool { !windows.isEmpty }

    // MARK: - View building

    private func makeContentView(in frame: NSRect, title: String, subtitle: String, isLong: Bool, countdown: NSTextField, ring: CAShapeLayer, showControls: Bool) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true

        // Radial warm gradient: radial-gradient(120% 90% at 50% 34%, #3a2a1a, #14100a 72%).
        let grad = CAGradientLayer()
        grad.type = .radial
        grad.colors = [Theme.hex(0x3a2a1a).cgColor, Theme.hex(0x14100a).cgColor]
        grad.locations = [0, 0.72]
        grad.startPoint = CGPoint(x: 0.5, y: 0.66)        // y flipped vs CSS (34% from top)
        grad.endPoint = CGPoint(x: 1.1, y: 1.56)
        grad.frame = view.bounds
        grad.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(grad)

        // --- Ring + breathing orb + countdown (190×190) ---
        let ringBox = NSView(frame: .zero)
        ringBox.wantsLayer = true
        ringBox.translatesAutoresizingMaskIntoConstraints = false

        let orb = CALayer()
        orb.backgroundColor = Theme.accent.cgColor
        orb.frame = CGRect(x: 15, y: 15, width: 160, height: 160)
        orb.cornerRadius = 80
        orb.opacity = 0.7
        let breathe = CAKeyframeAnimation(keyPath: "transform.scale")
        breathe.values = [0.8, 1.08, 0.8]
        breathe.keyTimes = [0, 0.5, 1]
        breathe.duration = 5
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.45, 0.95, 0.45]
        fade.keyTimes = [0, 0.5, 1]
        fade.duration = 5
        fade.repeatCount = .infinity
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            orb.add(breathe, forKey: "breathe")
            orb.add(fade, forKey: "fade")
        }
        ringBox.layer?.addSublayer(orb)

        // Progress ring: faint track + amber arc, depleting clockwise from 12 o'clock.
        let arc = CGMutablePath()
        arc.addArc(center: CGPoint(x: 95, y: 95), radius: 80,
                   startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        let track = CAShapeLayer()
        track.path = arc
        track.fillColor = nil
        track.strokeColor = NSColor(white: 1, alpha: 0.1).cgColor
        track.lineWidth = 3
        ringBox.layer?.addSublayer(track)

        ring.path = arc
        ring.fillColor = nil
        ring.strokeColor = Theme.accent.cgColor
        ring.lineWidth = 3
        ring.lineCap = .round
        ring.strokeEnd = 1
        ringBox.layer?.addSublayer(ring)

        let unit = NSTextField(labelWithString: Loc.t(remaining >= 60 ? "remaining" : "seconds").uppercased())
        unit.font = .systemFont(ofSize: 11, weight: .medium)
        unit.textColor = Theme.text3
        let numberStack = NSStackView(views: [countdown, unit])
        numberStack.orientation = .vertical
        numberStack.alignment = .centerX
        numberStack.spacing = 6
        numberStack.translatesAutoresizingMaskIntoConstraints = false
        ringBox.addSubview(numberStack)
        NSLayoutConstraint.activate([
            ringBox.widthAnchor.constraint(equalToConstant: 190),
            ringBox.heightAnchor.constraint(equalToConstant: 190),
            numberStack.centerXAnchor.constraint(equalTo: ringBox.centerXAnchor),
            numberStack.centerYAnchor.constraint(equalTo: ringBox.centerYAnchor),
        ])

        // --- Title + subtitle (amber "20 feet" emphasis baked into subtitle) ---
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = Theme.text
        titleLabel.alignment = .center

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 16, weight: .regular)
        subtitleLabel.textColor = Theme.text2
        subtitleLabel.alignment = .center

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .centerX
        textStack.spacing = 8

        let stack = NSStackView(views: [ringBox, textStack])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false

        if showControls {
            let skip = PillButton(title: Loc.t("Skip break"), filled: false) { [weak self] in self?.skipTapped() }
            let postpone = PillButton(title: Loc.t("Postpone 5 min"), filled: true) { [weak self] in self?.snoozeTapped() }
            let buttons = NSStackView(views: [skip, postpone])
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
        label.font = .monospacedDigitSystemFont(ofSize: 54, weight: .bold)
        label.textColor = Theme.text
        label.alignment = .center
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    private func updateCountdownText() {
        let text = Self.countdownString(max(0, Int(remaining.rounded())))
        countdownLabels.forEach { $0.stringValue = text }
        let progress = CGFloat(max(0, remaining) / duration)
        progressRings.forEach { $0.strokeEnd = progress }
    }

    /// Seconds-only under a minute ("19"); M:SS at or above ("4:56") so long
    /// breaks read as minutes, not a giant number.
    static func countdownString(_ secs: Int) -> String {
        secs >= 60 ? String(format: "%d:%02d", secs / 60, secs % 60) : "\(secs)"
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
