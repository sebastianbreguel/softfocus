# SoftFocus

A LookAway-style macOS menu-bar app: timed screen breaks with a full-screen
"look away" overlay, smart timing (waits for a natural pause, resets when you're
already idle), and blink/posture nudges. macOS 13+.

## Run it

```bash
swift test          # run the scheduler logic tests
./build-app.sh      # build SoftFocus.app
open SoftFocus.app    # launch it — look for the 👁 eye icon in the menu bar
```

To stop it: menu-bar eye icon → **Quit SoftFocus**.

## Layout

- `Sources/SoftFocusCore/` — pure, UI-free logic (testable):
  - `BreakScheduler.swift` — the smart-timing state machine. Drive it once a
    second with `tick(now:idleSeconds:)`; it returns `.startBreak` / `.endBreak`.
  - `Settings.swift` — UserDefaults-backed prefs + the `IdleProviding` protocol.
- `Sources/SoftFocus/` — the Mac app (AppKit + SwiftUI):
  - `IdleMonitor.swift` — real idle detection (Quartz `CGEventSource`).
  - `BreakOverlayController.swift` — full-screen dimmed overlay + countdown + Skip.
  - `NudgeController.swift` — small fading HUD for blink/posture reminders.
  - `SettingsView.swift` — SwiftUI preferences form.
  - `AppDelegate.swift` — wires the timers, scheduler, overlay, menu bar together.

## How smart timing works

`BreakScheduler` counts *active* work seconds. If you go idle past
`idleResetThreshold` (default 60s) it resets — you're already resting. When a
break is due it waits for a brief pause (`naturalPauseIdle`, 1.5s) before
interrupting, but forces the break after `maxOverdue` (2 min) so it can't be
dodged. All tunables live in `Settings.schedulerConfig`.

## Notes

- Distribution (Homebrew cask, notarization, code signing) is not set up yet —
  `build-app.sh` produces an unsigned local bundle. For shipping you'll need an
  Apple Developer ID to sign + notarize.
