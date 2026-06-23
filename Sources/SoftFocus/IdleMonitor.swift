import CoreGraphics
import Foundation
import SoftFocusCore

/// Real idle detection via Quartz: seconds since the last input event of any kind.
/// No special permissions needed for this query.
struct IdleMonitor: IdleProviding {
    func idleSeconds() -> TimeInterval {
        // ~0 as a CGEventType means "any input event" (kCGAnyInputEventType).
        let anyEvent = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }
}
