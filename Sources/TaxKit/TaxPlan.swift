/// The tax-relevant parts of a plan, in TaxKit's own types: the input to
/// ``TaxSystem/validate(_:parameters:)``. The planner builds it from the
/// plan file.
public struct TaxPlan: Hashable, Sendable {
    /// Which system applies from which year, with its options.
    public var residence: [Residence]
    /// The overlays the plan chose, with their options.
    public var overlays: [RegimeChoice]
    /// Whether thresholds rise with inflation after the last known tax year.
    public var indexThresholds: Bool
    /// Parameter overrides, keyed by system-prefixed path (`it.irpef.rates`).
    public var overrides: OptionValues
    /// The work phases, with their regimes.
    public var work: [WorkPhase]
    /// The pensions, with their schemes.
    public var pensions: [Pension]
    /// The person's birth year, if known.
    public var birthYear: Int?

    public init(residence: [Residence], overlays: [RegimeChoice] = [], indexThresholds: Bool = true,
                overrides: OptionValues = [:], work: [WorkPhase] = [], pensions: [Pension] = [],
                birthYear: Int? = nil) {
        self.residence = residence
        self.overlays = overlays
        self.indexThresholds = indexThresholds
        self.overrides = overrides
        self.work = work
        self.pensions = pensions
        self.birthYear = birthYear
    }

    /// The residence entry in force in `year`: the latest starting at or before it.
    public func residence(in year: Int) -> Residence? {
        residence.filter { $0.from <= year }.max { $0.from < $1.from }
    }

    /// One entry of the residence timeline.
    public struct Residence: Hashable, Sendable {
        /// The first year this system applies (residence changes on 1 January).
        public var from: Int
        public var system: String
        public var options: OptionValues

        public init(from: Int, system: String, options: OptionValues = [:]) {
            self.from = from
            self.system = system
            self.options = options
        }
    }

    /// A work phase as far as taxes are concerned.
    public struct WorkPhase: Hashable, Sendable {
        /// The same ID as `FixedYear.WorkIncome.phaseID`.
        public var id: String
        public var kind: EarnedIncomeKind
        /// `nil` means the system's default for `kind`.
        public var regime: String?
        public var options: OptionValues
        public var fromYear: Int
        /// The last year, or `nil` when the phase runs until a retirement age
        /// that isn't known yet.
        public var untilYear: Int?

        public init(id: String, kind: EarnedIncomeKind, regime: String? = nil, options: OptionValues = [:],
                    fromYear: Int, untilYear: Int?) {
            self.id = id
            self.kind = kind
            self.regime = regime
            self.options = options
            self.fromYear = fromYear
            self.untilYear = untilYear
        }
    }

    /// A pension as far as taxes are concerned.
    public struct Pension: Hashable, Sendable {
        /// The same ID as `FixedYear.Pension.id`.
        public var id: String
        public var scheme: String
        public var options: OptionValues

        public init(id: String, scheme: String, options: OptionValues = [:]) {
            self.id = id
            self.scheme = scheme
            self.options = options
        }
    }
}
