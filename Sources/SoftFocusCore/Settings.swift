import Foundation

/// How long the user has been idle (no keyboard/mouse). The app provides the
/// real implementation; tests provide a fake. Keeping it a protocol is what lets
/// BreakScheduler stay testable.
public protocol IdleProviding {
    func idleSeconds() -> TimeInterval
}

/// User-facing preferences, backed by UserDefaults so they survive restarts.
/// Exposes a couple of friendly units (minutes) and converts to a SchedulerConfig.
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

    public var schedulerConfig: SchedulerConfig {
        SchedulerConfig(
            workInterval: workMinutes * 60,
            breakDuration: breakSeconds,
            idleResetThreshold: 60,   // away 1 min => count it as rest
            naturalPauseIdle: 1.5,    // pause this brief is enough to slip the break in
            maxOverdue: 120           // but never delay a due break more than 2 min
        )
    }
}
