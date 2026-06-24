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
    private var statusMenuItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var nudgeIsBlink = true
    private var tipIndex = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.onSkip = { [weak self] in self?.scheduler.skipBreak() }
        overlay.onSnooze = { [weak self] in self?.scheduler.postpone(5 * 60) } // 5 min
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
        // `.common` mode so the timer keeps firing while a menu is open or the
        // break overlay holds the run loop in event-tracking mode.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
        restartNudgeTimer()
    }

    private func restartNudgeTimer() {
        nudgeTimer?.invalidate()
        let interval = max(60, settings.nudgeMinutes * 60)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.fireNudge() }
        RunLoop.main.add(t, forMode: .common)
        nudgeTimer = t
    }

    private func tick() {
        // Pick up any settings changes (cheap; SchedulerConfig is a value type).
        scheduler.config = settings.schedulerConfig

        switch scheduler.tick(now: Date(), idleSeconds: idle.idleSeconds()) {
        case .warn:
            nudges.show("Break coming up…")
        case .startBreak:
            beginBreak()
        case .endBreak:
            overlay.hide()
            playSound()
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

    /// Show the break overlay with the right duration + content, and chime.
    private func beginBreak() {
        tipIndex += 1
        let content = BreakContent.make(
            isLong: scheduler.currentBreakIsLong,
            custom: settings.customMessage,
            tipsEnabled: settings.tipsEnabled,
            index: tipIndex
        )
        playSound()
        overlay.show(duration: scheduler.currentBreakDuration, title: content.title, subtitle: content.subtitle)
    }

    private func playSound() {
        guard settings.soundEnabled else { return }
        NSSound(named: "Submarine")?.play()
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
            button.imagePosition = .imageLeading // icon on the left, countdown text on the right
            // Monospaced digits so the menu-bar timer doesn't jitter as numbers change.
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }

        let menu = NSMenu()
        menu.autoenablesItems = false // we manage enabled state ourselves

        // Live timer, shown when the menu is open. Disabled = not clickable.
        let timerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        timerItem.isEnabled = false
        menu.addItem(timerItem)
        statusMenuItem = timerItem
        menu.addItem(.separator())

        menu.addItem(item("Take a break now", #selector(takeBreakNow)))
        menu.addItem(item("Skip break", #selector(skipBreak)))
        menu.addItem(item("Postpone 5 min", #selector(postponeBreak)))
        menu.addItem(.separator())

        let pause = item("Pause", #selector(togglePause))
        menu.addItem(pause)
        pauseItem = pause
        menu.addItem(makePauseForItem())
        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit SoftFocus", #selector(NSApplication.terminate(_:)), key: "q"))
        statusItem.menu = menu
        updateMenuTitle()
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func makePauseForItem() -> NSMenuItem {
        let submenu = NSMenu()
        for (title, seconds) in [("30 minutes", 1800.0), ("1 hour", 3600.0), ("2 hours", 7200.0)] {
            let it = item(title, #selector(pauseForDuration(_:)))
            it.representedObject = seconds
            submenu.addItem(it)
        }
        submenu.addItem(item("Until tomorrow", #selector(pauseUntilTomorrow)))
        let parent = NSMenuItem(title: "Pause for", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func updateMenuTitle() {
        guard let button = statusItem?.button else { return }
        let menuText: String   // full text shown in the dropdown + tooltip
        let label: String      // compact text shown next to the menu-bar icon
        if scheduler.paused {
            menuText = "Paused"
            label = "‖"
        } else if scheduler.phase == .onBreak {
            let s = Int(scheduler.breakRemaining.rounded())
            menuText = "On break · \(s)s"
            label = "\(s)s"
        } else {
            let total = Int(scheduler.timeUntilBreak.rounded())
            let clock = String(format: "%d:%02d", total / 60, total % 60)
            menuText = "Next break in \(clock)"
            label = clock
        }
        button.title = " " + label // leading space separates the timer from the icon
        button.toolTip = menuText
        statusMenuItem?.title = menuText
        pauseItem?.title = scheduler.paused ? "Resume" : "Pause"
    }

    // MARK: - Actions

    @objc private func takeBreakNow() {
        scheduler.startBreakNow()
        beginBreak()
    }

    @objc private func skipBreak() {
        scheduler.skipBreak()
        overlay.hide()
    }

    @objc private func postponeBreak() {
        scheduler.postpone(5 * 60)
        overlay.hide()
        updateMenuTitle()
    }

    @objc private func togglePause() {
        scheduler.setPaused(!scheduler.paused)
        if scheduler.paused { overlay.hide() }
        updateMenuTitle()
    }

    @objc private func pauseForDuration(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        scheduler.pause(until: Date().addingTimeInterval(seconds))
        overlay.hide()
        updateMenuTitle()
    }

    @objc private func pauseUntilTomorrow() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        let at8 = cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        scheduler.pause(until: at8)
        overlay.hide()
        updateMenuTitle()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        // Settings can change the nudge interval — re-arm that timer.
        restartNudgeTimer()
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
