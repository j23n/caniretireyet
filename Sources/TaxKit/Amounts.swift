/// A flat rate on a base, after an allowance and up to a cap: e.g. an
/// inheritance tax of 4% above a €1,000,000 allowance, or a social
/// contribution of 26.07% on income up to a maximum base.
///
/// In a parameter file: `{ "rate": "0.04", "allowance": "1000000", "cap": … }`
/// (`allowance` and `cap` optional).
public struct FlatRate: Hashable, Sendable {
    public var rate: Double
    /// Deducted from the base first.
    public var allowance: Double
    /// The largest base the rate applies to, if limited.
    public var cap: Double?

    public init(rate: Double, allowance: Double = 0, cap: Double? = nil) {
        self.rate = rate
        self.allowance = allowance
        self.cap = cap
    }

    public init(_ node: ParameterNode) throws {
        self.init(rate: try node["rate"].double(), allowance: try node["allowance"].double(default: 0),
                  cap: try node["cap"].optionalDouble())
    }

    /// The part of `amount` the rate applies to: capped, less the allowance, never negative.
    public func taxableBase(for amount: Double) -> Double {
        max(0, min(amount, cap ?? .infinity) - allowance)
    }

    /// The rate times the taxable base.
    public func amount(on base: Double) -> Double {
        rate * taxableBase(for: base)
    }

    /// The same rate with the allowance and cap multiplied by `factor`.
    public func scaled(by factor: Double) -> FlatRate {
        FlatRate(rate: rate, allowance: allowance * factor, cap: cap.map { $0 * factor })
    }
}

/// A limit a value must stay within, e.g. forfettario's "revenue of at most
/// €85,000". Inclusive limits allow the limit itself.
public struct Threshold: Hashable, Sendable {
    public var limit: Double
    /// Whether a value equal to the limit is still within it.
    public var inclusive: Bool

    public init(_ limit: Double, inclusive: Bool = true) {
        self.limit = limit
        self.inclusive = inclusive
    }

    /// Whether `value` is beyond the limit.
    public func isExceeded(by value: Double) -> Bool {
        inclusive ? value > limit : value >= limit
    }

    /// Whether `value` is within the limit.
    public func admits(_ value: Double) -> Bool {
        !isExceeded(by: value)
    }

    public func scaled(by factor: Double) -> Threshold {
        Threshold(limit * factor, inclusive: inclusive)
    }
}

/// A point where the law makes a tax jump instead of changing smoothly, e.g.
/// the €65 extra detrazione that starts above €25,000 of income, which makes
/// IRPEF fall as income crosses €25,000.
///
/// Systems declare their cliffs explicitly, so tests can check that taxes
/// never fall as income rises anywhere else, and so results can explain a
/// jump.
public struct LegalCliff: Hashable, Sendable {
    /// Which way the tax moves as the measure rises past the cliff.
    public enum Direction: String, Hashable, Sendable {
        case taxFalls
        case taxRises
    }

    /// Stable ID, e.g. `it.detrazione.employment.bonus.25000`.
    public var id: String
    /// What the threshold is compared with, e.g. `reddito complessivo`.
    public var measure: String
    /// The threshold, in the same euros as the parameters it was read from.
    public var at: Double
    public var direction: Direction
    /// A short explanation for results and tests.
    public var note: String

    public init(id: String, measure: String, at: Double, direction: Direction, note: String) {
        self.id = id
        self.measure = measure
        self.at = at
        self.direction = direction
        self.note = note
    }

    /// Whether the cliff lies between `lower` and `upper`, inclusive: a
    /// cliff at a limit takes effect just above it.
    public func lies(between lower: Double, and upper: Double) -> Bool {
        at >= lower && at <= upper
    }
}
