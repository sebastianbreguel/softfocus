import Foundation

/// Are we currently working, or on a break?
public enum BreakPhase: Equatable { case working, onBreak }

/// What the app should do as a result of a tick. The scheduler never touches
/// UI itself, it just reports these and lets the app react.
public enum SchedulerAction: Equatable { case none, warn, startBreak, endBreak }

/// Tunables for the smart-timing state machine. All values are in seconds
/// (except `longBreakEvery`, a count).
public struct SchedulerConfig: Equatable {
    public var workInterval: TimeInterval       // work this long, then a break is due
    public var breakDuration: TimeInterval      // how long a normal (short) break lasts
    public var idleResetThreshold: TimeInterval // away this long => already resting, reset clock
    public var naturalPauseIdle: TimeInterval   // wait for a pause this short before interrupting
    public var maxOverdue: TimeInterval         // ...but force the break after waiting this long
    public var warnSeconds: TimeInterval        // emit `.warn` this long before a break (0 = off)
    public var longBreakEvery: Int              // every Nth break is a long one (0 = off)
    public var longBreakDuration: TimeInterval  // how long a long break lasts

    public init(
        workInterval: TimeInterval,
        breakDuration: TimeInterval,
        idleResetThreshold: TimeInterval,
        naturalPauseIdle: TimeInterval,
        maxOverdue: TimeInterval,
        warnSeconds: TimeInterval = 0,
        longBreakEvery: Int = 0,
        longBreakDuration: TimeInterval = 0
    ) {
        self.workInterval = workInterval
        self.breakDuration = breakDuration
        self.idleResetThreshold = idleResetThreshold
        self.naturalPauseIdle = naturalPauseIdle
        self.maxOverdue = maxOverdue
        self.warnSeconds = warnSeconds
        self.longBreakEvery = longBreakEvery
        self.longBreakDuration = longBreakDuration
    }
}

/// The brain of the app: a state machine you drive by calling `tick` once a
/// second with the current time and how long the user has been idle. It owns
/// no timers and no UI, which is exactly why it's easy to test.
public final class BreakScheduler {
    public private(set) var phase: BreakPhase = .working
    public var config: SchedulerConfig
    public var paused = false
    /// While true (e.g. you're in a meeting) the clock freezes and nothing fires.
    /// Driven externally by the app's meeting detection.
    public var inMeeting = false

    /// Whether the break currently running (or about to) is a long one.
    public private(set) var currentBreakIsLong = false
    /// How many breaks have started so far (drives the long-break cadence).
    public private(set) var breaksTaken = 0

    private var work: TimeInterval = 0        // accumulated *active* work seconds
    private var overdue: TimeInterval = 0     // seconds spent waiting for a natural pause
    private var breakElapsed: TimeInterval = 0
    private var didWarn = false               // have we already emitted .warn this cycle?
    private var pausedUntil: Date?            // auto-resume time when paused for a fixed span
    private var lastTick: Date?

    public init(config: SchedulerConfig) { self.config = config }

    /// Duration of the break currently running, picking short vs long.
    public var currentBreakDuration: TimeInterval {
        currentBreakIsLong ? config.longBreakDuration : config.breakDuration
    }
    /// Seconds of work left before a break is due (for the menu-bar countdown).
    public var timeUntilBreak: TimeInterval { max(0, config.workInterval - work) }
    /// Seconds left in the current break.
    public var breakRemaining: TimeInterval { max(0, currentBreakDuration - breakElapsed) }

    /// Call ~once a second. `idleSeconds` = time since the last keyboard/mouse event.
    public func tick(now: Date, idleSeconds: TimeInterval) -> SchedulerAction {
        defer { lastTick = now }
        guard let last = lastTick else { return .none } // first tick just sets the baseline
        let delta = now.timeIntervalSince(last)
        if delta <= 0 { return .none }

        // In a meeting: freeze the clock and suppress everything. Work already
        // accumulated is preserved, so it resumes where it left off afterwards.
        if inMeeting { return .none }

        if paused {
            // Auto-resume once a fixed-duration pause elapses.
            if let until = pausedUntil, now >= until {
                paused = false
                pausedUntil = nil
            } else {
                return .none
            }
        }

        switch phase {
        case .working:
            // User has been away a while => they're already resting. Start fresh.
            if idleSeconds >= config.idleResetThreshold {
                work = 0
                overdue = 0
                didWarn = false
                return .none
            }
            // Still building up to a break.
            if work < config.workInterval {
                work += delta
                if config.warnSeconds > 0, !didWarn, timeUntilBreak <= config.warnSeconds {
                    didWarn = true
                    return .warn
                }
                return .none
            }
            // Break is due. Wait for a brief pause so we don't interrupt mid-thought,
            // but don't wait forever.
            overdue += delta
            if idleSeconds >= config.naturalPauseIdle || overdue >= config.maxOverdue {
                beginBreak(long: longBreakIsNext())
                return .startBreak
            }
            return .none

        case .onBreak:
            breakElapsed += delta
            if breakElapsed >= currentBreakDuration {
                phase = .working
                work = 0
                overdue = 0
                didWarn = false
                return .endBreak
            }
            return .none
        }
    }

    /// User hit "Skip" — end the break and start a fresh work interval.
    public func skipBreak() { reset() }

    /// User hit "Take a break now". A manual break is always a short one and does
    /// not advance the long-break cadence.
    public func startBreakNow() {
        currentBreakIsLong = false
        phase = .onBreak
        breakElapsed = 0
        overdue = 0
        didWarn = false
    }

    /// Delay the next break by `seconds` (Snooze / "postpone"). This adds to the
    /// remaining time, so it never brings a break *sooner*: if a break is already
    /// due it lands `seconds` from now; mid-interval it pushes out by `seconds`.
    public func postpone(_ seconds: TimeInterval) {
        phase = .working
        work = max(0, work - seconds) // less accumulated work => break is further away
        overdue = 0
        breakElapsed = 0
        didWarn = false
    }

    /// Pause until `date`, then auto-resume on the next tick past it.
    public func pause(until date: Date) {
        paused = true
        pausedUntil = date
    }

    /// Manual pause/resume from the menu. Clears any fixed-duration auto-resume.
    public func setPaused(_ on: Bool) {
        paused = on
        pausedUntil = nil
    }

    public func reset() {
        phase = .working
        work = 0
        overdue = 0
        breakElapsed = 0
        didWarn = false
    }

    // MARK: - Private

    private func longBreakIsNext() -> Bool {
        config.longBreakEvery > 0 && (breaksTaken + 1) % config.longBreakEvery == 0
    }

    private func beginBreak(long: Bool) {
        breaksTaken += 1
        currentBreakIsLong = long
        phase = .onBreak
        breakElapsed = 0
        overdue = 0
    }
}
