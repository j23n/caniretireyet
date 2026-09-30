/// A progressive bracket schedule: each rate applies only to the part of the
/// base inside its bracket, e.g. IRPEF's 23% up to €28,000, 33% up to
/// €50,000 and 43% above.
///
/// In a parameter file:
///
///     { "brackets": [ { "upTo": "28000", "rate": "0.23" },
///                     { "upTo": "50000", "rate": "0.33" },
///                     { "rate": "0.43" } ] }
///
/// A `rates` list (and a `limits` list) next to `brackets` replaces the
/// brackets' rates (and upper limits) in order, so a plan can override them
/// with a key such as `it.irpef.rates`.
public struct BracketSchedule: Hashable, Sendable {
    /// One bracket: `rate` applies to the base above the previous bracket's
    /// limit and up to `upTo` (inclusive).
    public struct Bracket: Hashable, Sendable {
        /// The upper limit, or `nil` for the top bracket.
        public var upTo: Double?
        public var rate: Double

        public init(upTo: Double?, rate: Double) {
            self.upTo = upTo
            self.rate = rate
        }
    }

    /// Brackets in ascending order; only the last may be open-ended.
    public var brackets: [Bracket]

    public init(_ brackets: [Bracket]) {
        self.brackets = brackets
    }

    /// Reads `brackets`, plus the optional `rates` and `limits` overrides.
    public init(_ node: ParameterNode) throws {
        var brackets = try node["brackets"].list().map { bracket in
            Bracket(upTo: try bracket["upTo"].optionalDouble(), rate: try bracket["rate"].double())
        }
        if node["rates"].exists {
            for (index, rate) in try node["rates"].doubles().enumerated() where brackets.indices.contains(index) {
                brackets[index].rate = rate
            }
        }
        if node["limits"].exists {
            for (index, limit) in try node["limits"].doubles().enumerated() where brackets.indices.contains(index) {
                brackets[index].upTo = limit
            }
        }
        guard !brackets.isEmpty else { throw node.error("has no brackets") }
        self.init(brackets)
    }

    /// The upper limits of the brackets, ascending.
    public var thresholds: [Double] {
        brackets.compactMap(\.upTo)
    }

    /// The tax on `base` (0 for a base of 0 or less).
    public func tax(on base: Double) -> Double {
        guard base > 0 else { return 0 }
        var tax = 0.0
        var lower = 0.0
        for bracket in brackets {
            let upper = bracket.upTo ?? .infinity
            if base > lower {
                tax += (min(base, upper) - lower) * bracket.rate
            }
            if base <= upper { break }
            lower = upper
        }
        return tax
    }

    /// The rate on the next euro above `base`.
    public func marginalRate(at base: Double) -> Double {
        for bracket in brackets where base < (bracket.upTo ?? .infinity) {
            return bracket.rate
        }
        return brackets.last?.rate ?? 0
    }

    /// Tax divided by base (0 for a base of 0 or less).
    public func averageRate(at base: Double) -> Double {
        base > 0 ? tax(on: base) / base : 0
    }

    /// The schedule with every limit multiplied by `factor`, e.g. to express
    /// nominal thresholds in today's euros.
    public func scaled(by factor: Double) -> BracketSchedule {
        BracketSchedule(brackets.map { Bracket(upTo: $0.upTo.map { $0 * factor }, rate: $0.rate) })
    }
}

/// A rate chosen by the band the base falls in and applied to the whole
/// base, e.g. the Italian cuneo's tax-free sum: 7.1% of employment income up
/// to €8,500, 5.3% up to €15,000, 4.8% above. Unlike a ``BracketSchedule``,
/// the amount jumps at each limit, so every limit is a cliff.
///
/// Written like a bracket schedule: `{ "bands": [ { "upTo": …, "rate": … }, …, { "rate": … } ] }`.
public struct BandRateSchedule: Hashable, Sendable {
    public var bands: [BracketSchedule.Bracket]

    public init(_ bands: [BracketSchedule.Bracket]) {
        self.bands = bands
    }

    public init(_ node: ParameterNode) throws {
        let bands = try node["bands"].list().map { band in
            BracketSchedule.Bracket(upTo: try band["upTo"].optionalDouble(), rate: try band["rate"].double())
        }
        guard !bands.isEmpty else { throw node.error("has no bands") }
        self.init(bands)
    }

    /// The rate of the band `base` falls in (limits are inclusive).
    public func rate(for base: Double) -> Double {
        bands.first { base <= ($0.upTo ?? .infinity) }?.rate ?? 0
    }

    /// The rate of `base`'s band times `base` (0 for a base of 0 or less).
    public func amount(on base: Double) -> Double {
        base > 0 ? base * rate(for: base) : 0
    }

    /// The band limits, where the amount jumps.
    public var thresholds: [Double] {
        bands.compactMap(\.upTo)
    }

    /// The bands with every limit multiplied by `factor`.
    public func scaled(by factor: Double) -> BandRateSchedule {
        BandRateSchedule(bands.map { .init(upTo: $0.upTo.map { $0 * factor }, rate: $0.rate) })
    }
}
