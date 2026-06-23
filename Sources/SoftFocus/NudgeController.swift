import AppKit

/// Small, non-intrusive HUD that fades in near the top of the main screen with a
/// short reminder ("Blink 👀" / "Sit up straight"), then fades out. No system
/// notifications, so it needs no permissions or app bundle identifier.
final class NudgeController {
    private var window: NSWindow?

    func show(_ text: String) {
        guard let screen = NSScreen.main else { return }

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 20, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        let padding: CGFloat = 24
        let size = NSSize(width: label.frame.width + padding * 2, height: label.frame.height + padding)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - 80
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        container.layer?.cornerRadius = 12
        label.frame = NSRect(x: padding, y: padding / 2, width: label.frame.width, height: label.frame.height)
        container.addSubview(label)
        panel.contentView = container

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        window = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }

        // Hold for ~3s, then fade out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                if self?.window === panel { self?.window = nil }
            })
        }
    }
}
