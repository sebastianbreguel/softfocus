import AppKit
import SwiftUI
import SoftFocusCore

/// Wires everything together: a 1-second timer drives the scheduler, the
/// scheduler's actions drive the overlay, a separate timer fires nudges, and the
/// menu bar shows status + controls.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let idle = IdleMonitor()
    private lazy var scheduler = BreakScheduler(config: settings.schedulerConfig)

    private let overlay = BreakOverlayController()
    private let nudges = NudgeController()

    private var statusItem: NSStatusItem!
    private var tickTimer: Timer?
    private var nudgeTimer: Timer?
    private var settingsWindow: NSWindow?
    private var nudgeIsBlink = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.onSkip = { [weak self] in self?.scheduler.skipBreak() }
        setupMenuBar()
        startTimers()
        // Visible proof on launch (and a pointer to the menu-bar icon, which can
        // hide behind the notch on some Macs).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.nudges.show("SoftFocus is on — look for 👁 in the menu bar")
        }
    }

    // MARK: - Timers

    private func startTimers() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        restartNudgeTimer()
    }

    private func restartNudgeTimer() {
        nudgeTimer?.invalidate()
        let interval = max(60, settings.nudgeMinutes * 60)
        nudgeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fireNudge()
        }
    }

    private func tick() {
        // Pick up any settings changes (cheap; SchedulerConfig is a value type).
        scheduler.config = settings.schedulerConfig

        switch scheduler.tick(now: Date(), idleSeconds: idle.idleSeconds()) {
        case .startBreak:
            overlay.show(duration: scheduler.config.breakDuration)
        case .endBreak:
            overlay.hide()
        case .none:
            break
        }
        updateMenuTitle()
    }

    private func fireNudge() {
        guard scheduler.phase == .working, !scheduler.paused else { return }
        // Alternate between the two enabled nudge types.
        if nudgeIsBlink, settings.blinkEnabled {
            nudges.show("Blink 👀")
        } else if settings.postureEnabled {
            nudges.show("Sit up straight 🧍")
        }
        nudgeIsBlink.toggle()
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let icon = NSImage(systemSymbolName: "eye", accessibilityDescription: "SoftFocus") {
                button.image = icon
            } else {
                button.title = "👁" // fallback so the item is never blank/invisible
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Take a break now", action: #selector(takeBreakNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Skip break", action: #selector(skipBreak), keyEquivalent: ""))
        menu.addItem(.separator())
        let pause = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pause.tag = 1
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit SoftFocus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        updateMenuTitle()
    }

    private func updateMenuTitle() {
        guard let item = statusItem else { return }
        let status: String
        if scheduler.paused {
            status = "Paused"
        } else if scheduler.phase == .onBreak {
            status = "On break · \(Int(scheduler.breakRemaining))s"
        } else {
            let mins = Int(scheduler.timeUntilBreak / 60)
            let secs = Int(scheduler.timeUntilBreak.truncatingRemainder(dividingBy: 60))
            status = String(format: "Next break in %d:%02d", mins, secs)
        }
        item.button?.toolTip = status
    }

    @objc private func takeBreakNow() {
        scheduler.startBreakNow()
        overlay.show(duration: scheduler.config.breakDuration)
    }

    @objc private func skipBreak() {
        scheduler.skipBreak()
        overlay.hide()
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        scheduler.paused.toggle()
        sender.title = scheduler.paused ? "Resume" : "Pause"
        if scheduler.paused { overlay.hide() }
        updateMenuTitle()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "SoftFocus Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        // Settings can change the nudge interval — re-arm that timer when closing.
        restartNudgeTimer()
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
