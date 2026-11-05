import Foundation

/// A seeded random number generator, SplitMix64, with helpers that use
/// whole numbers only: a seed gives the same household
/// (``HouseholdSimulator``) on every platform and every Swift version.
public struct HouseholdRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A whole number in `range`, nearly uniform.
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let count = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % count)
    }

    /// True `percent` times in 100.
    public mutating func chance(_ percent: Int) -> Bool {
        int(in: 0...99) < percent
    }

    /// About normal, with mean 0 and standard deviation about 1,000: the sum
    /// of twelve uniform draws (Irwin–Hall), less their mean.
    public mutating func bell() -> Int {
        (0..<12).reduce(0) { total, _ in total + int(in: 0...999) } - 5994
    }

    /// An amount of a whole number of cents in `range`: `amount(cents: 500...40000)`
    /// is 5 to 400.
    public mutating func amount(cents range: ClosedRange<Int>) -> Decimal {
        Decimal(int(in: range)) / 100
    }

    /// One of `elements`.
    public mutating func pick<T>(_ elements: [T]) -> T {
        elements[int(in: 0...(elements.count - 1))]
    }
}
