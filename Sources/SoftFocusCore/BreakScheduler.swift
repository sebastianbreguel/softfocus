import Foundation

/// Are we currently working, or on a break?
public enum BreakPhase: Equatable { case working, onBreak }

/// What the app should do as a result of a tick. The scheduler never touches
/// UI itself — it just reports these and lets the app react.
public enum SchedulerAction: Equatable { case none, startBreak, endBreak }

/// Tunables for the smart-timing state machine. All values are in seconds.
public struct SchedulerConfig: Equatable {
    public var workInterval: TimeInterval       // work this long, then a break is due
    public var breakDuration: TimeInterval      // how long the break lasts
    public var idleResetThreshold: TimeInterval // away this long => already resting, reset clock
    public var naturalPauseIdle: TimeInterval   // wait for a pause this short before interrupting
    public var maxOverdue: TimeInterval         // ...but force the break after waiting this long

    public init(
        workInterval: TimeInterval,
        breakDuration: TimeInterval,
        idleResetThreshold: TimeInterval,
        naturalPauseIdle: TimeInterval,
        maxOverdue: TimeInterval
    ) {
        self.workInterval = workInterval
        self.breakDuration = breakDuration
        self.idleResetThreshold = idleResetThreshold
        self.naturalPauseIdle = naturalPauseIdle
        self.maxOverdue = maxOverdue
    }
}

/// The brain of the app: a state machine you drive by calling `tick` once a
/// second with the current time and how long the user has been idle. It owns
/// no timers and no UI, which is exactly why it's easy to test.
public final class BreakScheduler {
    public private(set) var phase: BreakPhase = .working
    public var config: SchedulerConfig
    public var paused = false

    private var work: TimeInterval = 0        // accumulated *active* work seconds
    private var overdue: TimeInterval = 0     // seconds spent waiting for a natural pause
    private var breakElapsed: TimeInterval = 0
    private var lastTick: Date?

    public init(config: SchedulerConfig) { self.config = config }

    /// Seconds of work left before a break is due (for the menu-bar countdown).
    public var timeUntilBreak: TimeInterval { max(0, config.workInterval - work) }
    /// Seconds left in the current break.
    public var breakRemaining: TimeInterval { max(0, config.breakDuration - breakElapsed) }

    /// Call ~once a second. `idleSeconds` = time since the last keyboard/mouse event.
    public func tick(now: Date, idleSeconds: TimeInterval) -> SchedulerAction {
        defer { lastTick = now }
        guard let last = lastTick else { return .none } // first tick just sets the baseline
        let delta = now.timeIntervalSince(last)
        if delta <= 0 || paused { return .none }

        switch phase {
        case .working:
            // User has been away a while => they're already resting. Start fresh.
            if idleSeconds >= config.idleResetThreshold {
                work = 0
                overdue = 0
                return .none
            }
            // Still building up to a break.
            if work < config.workInterval {
                work += delta
                return .none
            }
            // Break is due. Wait for a brief pause so we don't interrupt mid-thought,
            // but don't wait forever.
            overdue += delta
            if idleSeconds >= config.naturalPauseIdle || overdue >= config.maxOverdue {
                phase = .onBreak
                breakElapsed = 0
                overdue = 0
                return .startBreak
            }
            return .none

        case .onBreak:
            breakElapsed += delta
            if breakElapsed >= config.breakDuration {
                phase = .working
                work = 0
                return .endBreak
            }
            return .none
        }
    }

    /// User hit "Skip" — end the break and start a fresh work interval.
    public func skipBreak() { reset() }

    /// User hit "Take a break now".
    public func startBreakNow() {
        phase = .onBreak
        breakElapsed = 0
        overdue = 0
    }

    public func reset() {
        phase = .working
        work = 0
        overdue = 0
        breakElapsed = 0
    }
}
