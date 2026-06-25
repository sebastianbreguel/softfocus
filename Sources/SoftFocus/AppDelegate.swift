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

    private var manualMeeting = false            // forced on via the menu
    private var meetingItem: NSMenuItem?
    private var meetingCheckCounter = 0          // throttles the camera query
    private var cachedCameraMeeting = false
    private var googleCheckCounter = 0           // throttles the Google Calendar query
    private var cachedGoogleMeeting = false
    private var cachedGoogleMeetingEnd: Date?    // when the current calendar event ends
    private var cachedMeetingName: String?       // title of the current calendar meeting
    private var meetingOverrideUntil: Date?      // "don't pause for this meeting" until its end
    private var notifiedEventIDs: Set<String> = [] // events we've already warned about
    private var dontPauseItem: NSMenuItem?
    private var currentLanguage = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.onSkip = { [weak self] in self?.scheduler.skipBreak() }
        overlay.onSnooze = { [weak self] in self?.scheduler.postpone(5 * 60) } // 5 min
        setupMainMenu()
        setupMenuBar()
        startTimers()
        // Visible proof on launch (and a pointer to the menu-bar icon, which can
        // hide behind the notch on some Macs).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.nudges.show(Loc.t("SoftFocus is on — look for 👁 in the menu bar"))
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
        if settings.language != currentLanguage {
            currentLanguage = settings.language
            rebuildMenu()
        }
        updateMeetingState()

        switch scheduler.tick(now: Date(), idleSeconds: idle.idleSeconds()) {
        case .warn:
            nudges.show(Loc.t("Break coming up…"), heavy: true)
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

    /// Decide if we're in a meeting (manual toggle OR the camera is in use) and
    /// freeze the scheduler accordingly. The camera is polled at most every ~5s.
    private func updateMeetingState() {
        if settings.meetingAutoDetect {
            meetingCheckCounter -= 1
            if meetingCheckCounter <= 0 {
                meetingCheckCounter = 5
                cachedCameraMeeting = CameraMonitor.isCameraInUse()
            }
        } else {
            cachedCameraMeeting = false
        }

        // Google Calendar is a network call, so poll it less often and off the main flow.
        if GoogleCalendar.shared.isConnected {
            googleCheckCounter -= 1
            if googleCheckCounter <= 0 {
                googleCheckCounter = 60
                Task {
                    let events = await GoogleCalendar.shared.upcomingEvents(within: 15 * 60)
                    await MainActor.run { [weak self] in self?.applyCalendar(events) }
                }
            }
        } else {
            cachedGoogleMeeting = false
            cachedGoogleMeetingEnd = nil
            cachedMeetingName = nil
        }

        // "Don't pause for this meeting": ignore auto-detection until the event ends.
        if let until = meetingOverrideUntil, Date() >= until { meetingOverrideUntil = nil }
        let auto = (cachedCameraMeeting || cachedGoogleMeeting) && meetingOverrideUntil == nil
        let meeting = manualMeeting || auto
        if meeting, !scheduler.inMeeting {
            // Entering a meeting: never black out the screen (you might be sharing it).
            if scheduler.phase == .onBreak { scheduler.skipBreak() }
            overlay.hide()
        }
        scheduler.inMeeting = meeting
    }

    /// Apply a fresh calendar fetch: current meeting + a heads-up before the next one.
    private func applyCalendar(_ events: [CalendarEvent]) {
        let now = Date()
        let ongoing = events.first { $0.start <= now && now < $0.end }
        cachedGoogleMeeting = ongoing != nil
        cachedGoogleMeetingEnd = ongoing?.end
        cachedMeetingName = ongoing?.title

        // Heads-up ~2 min before an upcoming meeting, once per event.
        if let up = events.first(where: { $0.start > now && $0.start <= now.addingTimeInterval(120) }),
           !notifiedEventIDs.contains(up.id) {
            notifiedEventIDs.insert(up.id)
            let mins = max(1, Int((up.start.timeIntervalSince(now) / 60).rounded()))
            nudges.show(String(format: Loc.t("Meeting in %d min: %@"), mins, up.title))
        }
    }

    private func fireNudge() {
        guard scheduler.phase == .working, !scheduler.paused else { return }
        // Alternate between the two enabled nudge types.
        if nudgeIsBlink, settings.blinkEnabled {
            nudges.show(Loc.t("Blink 👀"))
        } else if settings.postureEnabled {
            nudges.show(Loc.t("Sit up straight 🧍"), big: true)
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
        overlay.show(duration: scheduler.currentBreakDuration, title: content.title, subtitle: content.subtitle, isLong: scheduler.currentBreakIsLong)
    }

    private func playSound() {
        guard settings.soundEnabled else { return }
        NSSound(named: "Submarine")?.play()
    }

    // MARK: - Main menu (key equivalents)

    /// A menu-bar (.accessory) app has no standard menu, so ⌘W / ⌘Q / copy-paste
    /// don't work in its windows. NSApp processes key equivalents against this
    /// main menu even when the bar isn't shown, so these shortcuts work anyway.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit SoftFocus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
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
        currentLanguage = settings.language
        rebuildMenu()
    }

    /// Build (or rebuild, on language change) the dropdown menu.
    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false // we manage enabled state ourselves

        // Live timer, shown when the menu is open. Disabled = not clickable.
        let timerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        timerItem.isEnabled = false
        menu.addItem(timerItem)
        statusMenuItem = timerItem
        menu.addItem(.separator())

        menu.addItem(item(Loc.t("Take a break now"), #selector(takeBreakNow)))
        menu.addItem(item(Loc.t("Skip break"), #selector(skipBreak)))
        menu.addItem(item(Loc.t("Postpone 5 min"), #selector(postponeBreak)))
        menu.addItem(.separator())

        let pause = item(Loc.t("Pause"), #selector(togglePause))
        menu.addItem(pause)
        pauseItem = pause
        menu.addItem(makePauseForItem())
        let meeting = item(Loc.t("Meeting mode"), #selector(toggleMeeting))
        menu.addItem(meeting)
        meetingItem = meeting
        let dontPause = item(Loc.t("Don't pause for this meeting"), #selector(dontPauseThisMeeting))
        menu.addItem(dontPause)
        dontPauseItem = dontPause
        menu.addItem(.separator())

        menu.addItem(item(Loc.t("Settings…"), #selector(openSettings), key: ","))
        // Quit must target NSApp: terminate(_:) lives on NSApplication, not on us.
        let quit = item(Loc.t("Quit SoftFocus"), #selector(NSApplication.terminate(_:)), key: "q")
        quit.target = NSApp
        menu.addItem(quit)
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
            let it = item(Loc.t(title), #selector(pauseForDuration(_:)))
            it.representedObject = seconds
            submenu.addItem(it)
        }
        submenu.addItem(item(Loc.t("Until tomorrow"), #selector(pauseUntilTomorrow)))
        let parent = NSMenuItem(title: Loc.t("Pause for"), action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func updateMenuTitle() {
        guard let button = statusItem?.button else { return }
        let menuText: String   // full text shown in the dropdown + tooltip
        let label: String      // compact text shown next to the menu-bar icon
        if scheduler.inMeeting {
            let name = cachedMeetingName.map { ": \($0)" } ?? ""
            if let end = cachedGoogleMeetingEnd, end > Date() {
                let f = DateFormatter()
                f.timeStyle = .short
                f.dateStyle = .none
                menuText = "\(Loc.t("In a meeting"))\(name) · \(Loc.t("until")) \(f.string(from: end))"
            } else {
                menuText = "\(Loc.t("In a meeting"))\(name)"
            }
            label = "◉"
        } else if scheduler.paused {
            menuText = Loc.t("Paused")
            label = "‖"
        } else if scheduler.phase == .onBreak {
            let s = Int(scheduler.breakRemaining.rounded())
            menuText = "\(Loc.t("On break")) · \(s)s"
            label = "\(s)s"
        } else {
            let total = Int(scheduler.timeUntilBreak.rounded())
            let clock = String(format: "%d:%02d", total / 60, total % 60)
            menuText = "\(Loc.t("Next break in")) \(clock)"
            label = clock
        }
        button.title = "" // ponytail: icon-only menu bar; status lives in tooltip/menu
        _ = label
        button.toolTip = menuText
        statusMenuItem?.title = menuText
        pauseItem?.title = Loc.t(scheduler.paused ? "Resume" : "Pause")
        meetingItem?.state = manualMeeting ? .on : .off
        // Only offer the per-meeting override while a calendar meeting is active.
        dontPauseItem?.isEnabled = scheduler.inMeeting && cachedGoogleMeetingEnd != nil && meetingOverrideUntil == nil
    }

    // MARK: - Actions

    @objc private func toggleMeeting() {
        manualMeeting.toggle()
        updateMeetingState()
        updateMenuTitle()
    }

    /// Ignore meeting detection for the current calendar meeting, so breaks run
    /// normally until it ends.
    @objc private func dontPauseThisMeeting() {
        meetingOverrideUntil = cachedGoogleMeetingEnd
        updateMeetingState()
        updateMenuTitle()
    }

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
            window.title = Loc.t("Settings")
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
