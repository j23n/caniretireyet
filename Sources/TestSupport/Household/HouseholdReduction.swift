import Foundation

/// The seeds the household tests run over, and how a failing seed's
/// events are reduced to the fewest that still fail.
public enum HouseholdSeeds {
    /// `HOUSEHOLD_SEED` alone when it's set; else 0 up to `HOUSEHOLD_SEEDS`,
    /// 50 by default, so the suite stays fast and more can run by hand.
    public static var all: [UInt64] {
        let environment = ProcessInfo.processInfo.environment
        if let seed = environment["HOUSEHOLD_SEED"].flatMap(UInt64.init) { return [seed] }
        let count = environment["HOUSEHOLD_SEEDS"].flatMap(Int.init) ?? 50
        return Array(0..<UInt64(max(count, 1)))
    }

    /// Whether a failing seed's events are reduced (`HOUSEHOLD_REDUCE=1`):
    /// slow, so only by hand.
    public static var reduces: Bool {
        ProcessInfo.processInfo.environment["HOUSEHOLD_REDUCE"] == "1"
    }

    /// The fewest of `events` for which `fails` still holds: chunks of
    /// them removed while it holds, halving the chunks down to single events.
    public static func reduce(_ events: [HouseholdEvent], fails: ([HouseholdEvent]) -> Bool) -> [HouseholdEvent] {
        var current = events
        var chunk = max(1, current.count / 2)
        while true {
            var index = 0
            var removed = false
            while index < current.count {
                var candidate = current
                candidate.removeSubrange(index..<min(index + chunk, current.count))
                if fails(candidate) {
                    current = candidate
                    removed = true
                } else {
                    index += chunk
                }
            }
            if chunk == 1 && !removed { return current }
            chunk = max(1, chunk / 2)
        }
    }
}
