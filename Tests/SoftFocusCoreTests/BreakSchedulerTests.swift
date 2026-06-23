import XCTest
@testable import SoftFocusCore

final class BreakSchedulerTests: XCTestCase {
    // Fast config: 10s work, 3s break, idle-reset at 30s, pause 1.5s, force at 5s overdue.
    private func makeScheduler() -> BreakScheduler {
        BreakScheduler(config: SchedulerConfig(
            workInterval: 10,
            breakDuration: 3,
            idleResetThreshold: 30,
            naturalPauseIdle: 1.5,
            maxOverdue: 5
        ))
    }

    /// Drive the scheduler one simulated second at a time and collect actions.
    private func run(_ s: BreakScheduler, seconds: Int, idle: TimeInterval) -> [SchedulerAction] {
        var actions: [SchedulerAction] = []
        let start = Date(timeIntervalSince1970: 0)
        for i in 0...seconds {
            actions.append(s.tick(now: start.addingTimeInterval(TimeInterval(i)), idleSeconds: idle))
        }
        return actions
    }

    func testBreakStartsAfterWorkIntervalWhenIdleHitsNaturalPause() {
        let s = makeScheduler()
        // User active (idle below natural pause) for 12s: break is due but waits...
        let actions = run(s, seconds: 12, idle: 0)
        XCTAssertFalse(actions.contains(.startBreak), "Should wait for a pause, not interrupt active typing")

        // Now a natural pause (idle 2s >= 1.5s) — break should fire.
        let fired = s.tick(now: Date(timeIntervalSince1970: 13), idleSeconds: 2)
        XCTAssertEqual(fired, .startBreak)
    }

    func testBreakIsForcedAfterMaxOverdueEvenWithoutPause() {
        let s = makeScheduler()
        // Stay active forever (idle 0). Work=10 reached at t10, then overdue accrues;
        // force fires once overdue >= 5 (around t16). Run long enough to catch it.
        let actions = run(s, seconds: 20, idle: 0)
        XCTAssertTrue(actions.contains(.startBreak), "Break must be forced after maxOverdue")
    }

    func testIdleResetsTheWorkClock() {
        let s = makeScheduler()
        // Work a bit, then go away past the reset threshold — clock resets, no break due.
        _ = run(s, seconds: 8, idle: 0)        // ~8s of work
        let away = run(s, seconds: 5, idle: 40) // away => reset every tick
        XCTAssertFalse(away.contains(.startBreak))
        // Coming back, it should take a fresh full interval before any break.
        let backShort = run(s, seconds: 5, idle: 0)
        XCTAssertFalse(backShort.contains(.startBreak), "Work clock should have reset while idle")
    }

    func testBreakEndsAfterDuration() {
        let s = makeScheduler()
        s.startBreakNow()
        let actions = run(s, seconds: 4, idle: 0) // break lasts 3s
        XCTAssertTrue(actions.contains(.endBreak))
        XCTAssertEqual(s.phase, .working)
    }

    func testPauseStopsEverything() {
        let s = makeScheduler()
        s.paused = true
        let actions = run(s, seconds: 30, idle: 0)
        XCTAssertEqual(actions.filter { $0 != .none }, [], "Paused scheduler emits nothing")
    }
}
