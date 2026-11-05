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

/// How far the app's numbers are from a simulated household's truth when
/// its records leave the app to guess, over many seeds: each error, and a
/// short summary of them.
public struct HouseholdErrors: Sendable {
    /// One number's error for one seed: the app's less the truth, and as a
    /// share of `scale`, such as what came in that year.
    public struct Entry: Sendable {
        public var label: String
        public var seed: UInt64
        public var error: Decimal
        public var share: Decimal

        public init(label: String, seed: UInt64, error: Decimal, share: Decimal) {
            self.label = label
            self.seed = seed
            self.error = error
            self.share = share
        }
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    /// Adds the error of `app` against `truth`, as a share of `scale`
    /// (zero when `scale` is).
    public mutating func add(_ label: String, seed: UInt64, app: Decimal?, truth: Decimal, scale: Decimal) {
        let error = (app ?? 0) - truth
        entries.append(Entry(label: label, seed: seed, error: error, share: scale == 0 ? 0 : abs(error / scale)))
    }

    public mutating func append(contentsOf other: HouseholdErrors) {
        entries += other.entries
    }

    /// The largest share of each label, with its seed, and the mean share.
    public var summary: String {
        let labels = Array(Set(entries.map(\.label))).sorted()
        return labels.map { label in
            let errors = entries.filter { $0.label == label }
            let worst = errors.max { $0.share < $1.share }
            let mean = errors.reduce(Decimal(0)) { $0 + $1.share } / Decimal(max(errors.count, 1))
            return "\(label): worst \(percent(worst?.share ?? 0)) (seed \(worst?.seed ?? 0), "
                + "\(worst?.error.rounded(scale: 2) ?? 0)), mean \(percent(mean)) over \(errors.count)"
        }.joined(separator: "\n")
    }

    private func percent(_ share: Decimal) -> String {
        "\((share * 100).rounded(scale: 2))%"
    }
}
