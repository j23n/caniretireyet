/// Tax state carried from one year to the next, e.g. prior-year revenue (for
/// forfettario eligibility), years left in impatriati, or years of
/// pension-fund membership.
///
/// Opaque to the engine: it passes each year's `nextState` back to the
/// system the following year and never looks inside. Systems namespace their
/// keys (`it.priorRevenue`).
///
/// The same type carries state along each simulated path
/// (``VariableYear/pathState`` and ``TaxAssessment/nextPathState``), for what
/// depends on the markets, such as losses carried forward.
public struct TaxState: Hashable, Sendable, ExpressibleByDictionaryLiteral {
    public var values: [String: Double]

    public init(_ values: [String: Double] = [:]) {
        self.values = values
    }

    public init(dictionaryLiteral elements: (String, Double)...) {
        self.values = Dictionary(elements, uniquingKeysWith: { _, last in last })
    }

    /// The state before the first simulated year.
    public static let empty = TaxState()

    public subscript(key: String) -> Double? {
        get { values[key] }
        set { values[key] = newValue }
    }
}
