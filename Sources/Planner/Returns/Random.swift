import Foundation

/// SplitMix64: a tiny generator used to seed ``Xoshiro256StarStar`` and to
/// derive independent streams from one seed.
struct SplitMix64: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// xoshiro256** (Blackman and Vigna): the planner's seeded generator. The
/// same seed gives the same sequence on every platform; no Foundation
/// randomness is involved.
struct Xoshiro256StarStar: RandomNumberGenerator, Sendable {
    private var s0, s1, s2, s3: UInt64

    /// Seeds the four words from SplitMix64, as the authors recommend.
    init(seed: UInt64) {
        var mixer = SplitMix64(seed: seed)
        s0 = mixer.next()
        s1 = mixer.next()
        s2 = mixer.next()
        s3 = mixer.next()
    }

    /// An independent stream for one simulated run: the same `(seed, stream,
    /// index)` always gives the same numbers, whatever else the plan contains.
    init(seed: UInt64, stream: UInt64, index: Int) {
        var mixer = SplitMix64(seed: seed ^ (stream &* 0xD1B5_4A32_D192_ED03))
        let base = mixer.next()
        self.init(seed: base &+ UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9_7F4A_7C15)
    }

    mutating func next() -> UInt64 {
        let result = ((s1 &* 5) << 7 | (s1 &* 5) >> 57) &* 9
        let t = s1 << 17
        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = s3 << 45 | s3 >> 19
        return result
    }

    /// A uniform double in [0, 1), from the top 53 bits.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }
}

/// Standard normal draws by the Marsaglia polar method, keeping the spare
/// value of each pair.
struct NormalSampler: Sendable {
    private var generator: Xoshiro256StarStar
    private var spare: Double?

    init(_ generator: Xoshiro256StarStar) {
        self.generator = generator
    }

    mutating func next() -> Double {
        if let value = spare {
            spare = nil
            return value
        }
        while true {
            let u = 2 * generator.nextUnit() - 1
            let v = 2 * generator.nextUnit() - 1
            let s = u * u + v * v
            if s > 0, s < 1 {
                let factor = (-2 * log(s) / s).squareRoot()
                spare = v * factor
                return u * factor
            }
        }
    }
}

/// Stream identifiers, so adding an event never shifts the market draws.
enum RandomStream {
    static let markets: UInt64 = 1
    static let events: UInt64 = 2
}
