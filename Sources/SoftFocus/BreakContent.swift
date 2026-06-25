import Foundation

/// Chooses the title/subtitle shown on the break overlay: a custom message if
/// set, otherwise a rotating eye/posture tip, otherwise a sensible default.
enum BreakContent {
    static let tips = [
        "Rest your eyes. Focus on something far away.",
        "Look about 20 feet away for 20 seconds.",
        "Blink slowly a few times to refresh your eyes.",
        "Roll your shoulders back and let them drop.",
        "Unclench your jaw and relax your face.",
        "Stand up and stretch your back.",
        "Look out a window if you have one.",
        "Breathe in slowly, out even slower.",
    ]

    static func make(isLong: Bool, custom: String, tipsEnabled: Bool, index: Int) -> (title: String, subtitle: String) {
        let title = Loc.t(isLong ? "Time to stand up and stretch" : "Look away from your screen")
        let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return (title, trimmed) } // user's own message shown verbatim
        let tip = tipsEnabled ? tips[((index % tips.count) + tips.count) % tips.count] : tips[0]
        return (title, Loc.t(tip))
    }
}
