import Foundation

/// How long the user has been idle (no keyboard/mouse). The app provides the
/// real implementation; tests provide a fake. Keeping it a protocol is what lets
/// BreakScheduler stay testable.
public protocol IdleProviding {
    func idleSeconds() -> TimeInterval
}

/// User-facing preferences, backed by UserDefaults so they survive restarts.
/// Exposes friendly units and converts to a SchedulerConfig.
public final class Settings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "workMinutes": 20.0,
            "breakSeconds": 20.0,
            "nudgeMinutes": 5.0,
            "blinkEnabled": true,
            "postureEnabled": true,
            "longBreaksEnabled": true,
            "longBreakEvery": 4.0,
            "longBreakMinutes": 5.0,
            "warnEnabled": true,
            "soundEnabled": true,
            "tipsEnabled": true,
            "customMessage": "",
        ])
    }

    public var workMinutes: Double {
        get { defaults.double(forKey: "workMinutes") }
        set { defaults.set(newValue, forKey: "workMinutes") }
    }
    public var breakSeconds: Double {
        get { defaults.double(forKey: "breakSeconds") }
        set { defaults.set(newValue, forKey: "breakSeconds") }
    }
    public var nudgeMinutes: Double {
        get { defaults.double(forKey: "nudgeMinutes") }
        set { defaults.set(newValue, forKey: "nudgeMinutes") }
    }
    public var blinkEnabled: Bool {
        get { defaults.bool(forKey: "blinkEnabled") }
        set { defaults.set(newValue, forKey: "blinkEnabled") }
    }
    public var postureEnabled: Bool {
        get { defaults.bool(forKey: "postureEnabled") }
        set { defaults.set(newValue, forKey: "postureEnabled") }
    }
    public var longBreaksEnabled: Bool {
        get { defaults.bool(forKey: "longBreaksEnabled") }
        set { defaults.set(newValue, forKey: "longBreaksEnabled") }
    }
    public var longBreakEvery: Double {
        get { defaults.double(forKey: "longBreakEvery") }
        set { defaults.set(newValue, forKey: "longBreakEvery") }
    }
    public var longBreakMinutes: Double {
        get { defaults.double(forKey: "longBreakMinutes") }
        set { defaults.set(newValue, forKey: "longBreakMinutes") }
    }
    public var warnEnabled: Bool {
        get { defaults.bool(forKey: "warnEnabled") }
        set { defaults.set(newValue, forKey: "warnEnabled") }
    }
    public var soundEnabled: Bool {
        get { defaults.bool(forKey: "soundEnabled") }
        set { defaults.set(newValue, forKey: "soundEnabled") }
    }
    public var tipsEnabled: Bool {
        get { defaults.bool(forKey: "tipsEnabled") }
        set { defaults.set(newValue, forKey: "tipsEnabled") }
    }
    public var customMessage: String {
        get { defaults.string(forKey: "customMessage") ?? "" }
        set { defaults.set(newValue, forKey: "customMessage") }
    }

    /// Seconds before a break to show the heads-up banner (0 = off).
    public var warnSeconds: TimeInterval { warnEnabled ? 10 : 0 }

    public var schedulerConfig: SchedulerConfig {
        SchedulerConfig(
            workInterval: workMinutes * 60,
            breakDuration: breakSeconds,
            idleResetThreshold: 60,   // away 1 min => count it as rest
            naturalPauseIdle: 1.5,    // pause this brief is enough to slip the break in
            maxOverdue: 120,          // but never delay a due break more than 2 min
            warnSeconds: warnSeconds,
            longBreakEvery: longBreaksEnabled ? Int(longBreakEvery) : 0,
            longBreakDuration: longBreakMinutes * 60
        )
    }
}
