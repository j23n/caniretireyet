/// An amount that tapers linearly with a base, written the way Italian law
/// writes its detrazioni. In each segment, up to and including `upTo`, the
/// amount is
///
///     base + variable × (upTo − x) / (upTo − from)
///
/// where `from` is the previous segment's `upTo` (0 for the first). Above
/// the last segment the amount is `above` (default 0). Flat amounts inside a
/// band, like "plus €65 between €25,000 and €35,000", are ``BandAmount``s.
///
/// In a parameter file:
///
///     { "segments": [ { "upTo": "15000", "base": "1955" },
///                     { "upTo": "28000", "base": "1910", "variable": "1190" },
///                     { "upTo": "50000", "base": "0", "variable": "1910" } ],
///       "bonuses": [ { "above": "25000", "upTo": "35000", "amount": "65" } ] }
public struct LinearTaper: Hashable, Sendable {
    /// One segment of the taper.
    public struct Segment: Hashable, Sendable {
        /// The segment's upper limit (inclusive).
        public var upTo: Double
        /// The amount at `upTo`.
        public var base: Double
        /// The extra amount at the segment's lower end, tapering to 0 at `upTo`.
        public var variable: Double

        public init(upTo: Double, base: Double, variable: Double = 0) {
            self.upTo = upTo
            self.base = base
            self.variable = variable
        }
    }

    /// Segments in ascending order of `upTo`.
    public var segments: [Segment]
    /// The amount above the last segment.
    public var above: Double
    /// Flat amounts added inside bands of the base.
    public var bonuses: [BandAmount]

    public init(segments: [Segment], above: Double = 0, bonuses: [BandAmount] = []) {
        self.segments = segments
        self.above = above
        self.bonuses = bonuses
    }

    /// Reads `segments`, the optional `above` and the optional `bonuses`.
    public init(_ node: ParameterNode) throws {
        let segments = try node["segments"].list().map { segment in
            Segment(upTo: try segment["upTo"].double(), base: try segment["base"].double(),
                    variable: try segment["variable"].double(default: 0))
        }
        guard !segments.isEmpty else { throw node.error("has no segments") }
        self.init(segments: segments, above: try node["above"].double(default: 0),
                  bonuses: try node["bonuses"].optionalList().map(BandAmount.init))
    }

    /// The amount for base `x` (a negative base counts as 0).
    public func value(at x: Double) -> Double {
        let x = max(0, x)
        var total = above
        var from = 0.0
        for segment in segments {
            if x <= segment.upTo {
                let width = segment.upTo - from
                total = segment.base + (width > 0 ? segment.variable * (segment.upTo - x) / width : 0)
                break
            }
            from = segment.upTo
        }
        return total + bonuses.reduce(0) { $0 + $1.amount(at: x) }
    }

    /// Where the amount jumps as the base rises past a limit, with the size
    /// of each jump (positive when the amount rises). Continuous limits are
    /// left out.
    public var discontinuities: [(at: Double, jump: Double)] {
        var result: [(at: Double, jump: Double)] = []
        for (index, segment) in segments.enumerated() {
            let right: Double
            if index + 1 < segments.count {
                let next = segments[index + 1]
                right = next.base + next.variable
            } else {
                right = above
            }
            let jump = right - segment.base
            if abs(jump) > 1e-9 { result.append((segment.upTo, jump)) }
        }
        for bonus in bonuses {
            result.append((bonus.above, bonus.amount))
            result.append((bonus.upTo, -bonus.amount))
        }
        return result.sorted { $0.at < $1.at }
    }

    /// The taper with every limit and amount multiplied by `factor`.
    public func scaled(by factor: Double) -> LinearTaper {
        LinearTaper(
            segments: segments.map {
                Segment(upTo: $0.upTo * factor, base: $0.base * factor, variable: $0.variable * factor)
            },
            above: above * factor,
            bonuses: bonuses.map { $0.scaled(by: factor) })
    }
}

/// A flat amount for a base strictly above `above` and at most `upTo`, e.g.
/// the extra €65 detrazione between €25,000 and €35,000. Both limits are
/// cliffs.
public struct BandAmount: Hashable, Sendable {
    public var above: Double
    public var upTo: Double
    public var amount: Double

    public init(above: Double, upTo: Double, amount: Double) {
        self.above = above
        self.upTo = upTo
        self.amount = amount
    }

    /// Reads `{ "above": …, "upTo": …, "amount": … }`.
    public init(_ node: ParameterNode) throws {
        self.init(above: try node["above"].double(), upTo: try node["upTo"].double(), amount: try node["amount"].double())
    }

    /// `amount` inside the band, 0 outside it.
    public func amount(at x: Double) -> Double {
        x > above && x <= upTo ? amount : 0
    }

    /// The band with its limits and amount multiplied by `factor`.
    public func scaled(by factor: Double) -> BandAmount {
        BandAmount(above: above * factor, upTo: upTo * factor, amount: amount * factor)
    }
}
