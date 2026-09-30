/// `plans/<id>.json`: one retirement scenario. See PLANNER.md, "Plan file".
///
/// Amounts are yearly and in today's euros. Optional sections decode as
/// empty values when absent and are left out of the file when empty, so a
/// plan only records what differs from the defaults.
public struct PlanDocument: Hashable, Sendable, Identifiable, KnownKeysProviding {
    public var id: PlanID
    public var name: String
    /// When work stops.
    public var retirement: PlanRetirement
    /// The last age the plan must fund, as written. See ``effectiveEndAge``.
    public var endAge: Int?
    /// Tax residence over time, overlays and overrides.
    public var tax: PlanTax
    /// Working phases.
    public var work: [WorkPhase]
    public var spending: PlanSpending
    public var pensions: [PlanPension]
    public var contributions: [PlanContribution]
    /// One-off windfalls and expenses.
    public var events: [PlanEvent]
    public var portfolio: PlanPortfolio
    public var assumptions: PlanAssumptions
    public var withdrawals: PlanWithdrawals
    public var simulation: PlanSimulation

    /// 95.
    public static let defaultEndAge = 95

    public init(
        id: PlanID, name: String, retirement: PlanRetirement, endAge: Int? = nil, tax: PlanTax = PlanTax(),
        work: [WorkPhase] = [], spending: PlanSpending, pensions: [PlanPension] = [],
        contributions: [PlanContribution] = [], events: [PlanEvent] = [], portfolio: PlanPortfolio = PlanPortfolio(),
        assumptions: PlanAssumptions = PlanAssumptions(), withdrawals: PlanWithdrawals = PlanWithdrawals(),
        simulation: PlanSimulation = PlanSimulation()
    ) {
        self.id = id
        self.name = name
        self.retirement = retirement
        self.endAge = endAge
        self.tax = tax
        self.work = work
        self.spending = spending
        self.pensions = pensions
        self.contributions = contributions
        self.events = events
        self.portfolio = portfolio
        self.assumptions = assumptions
        self.withdrawals = withdrawals
        self.simulation = simulation
    }

    /// The last age the plan must fund (default 95).
    public var effectiveEndAge: Int {
        endAge ?? Self.defaultEndAge
    }
}

extension PlanDocument: Codable {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, retirement, endAge, tax, work, spending, pensions, contributions, events, portfolio,
             assumptions, withdrawals, simulation
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(PlanID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        retirement = try c.decode(PlanRetirement.self, forKey: .retirement)
        endAge = try c.decodeIfPresent(Int.self, forKey: .endAge)
        tax = try c.decodeIfPresent(PlanTax.self, forKey: .tax) ?? PlanTax()
        work = try c.decodeArray([WorkPhase].self, forKey: .work)
        spending = try c.decode(PlanSpending.self, forKey: .spending)
        pensions = try c.decodeArray([PlanPension].self, forKey: .pensions)
        contributions = try c.decodeArray([PlanContribution].self, forKey: .contributions)
        events = try c.decodeArray([PlanEvent].self, forKey: .events)
        portfolio = try c.decodeIfPresent(PlanPortfolio.self, forKey: .portfolio) ?? PlanPortfolio()
        assumptions = try c.decodeIfPresent(PlanAssumptions.self, forKey: .assumptions) ?? PlanAssumptions()
        withdrawals = try c.decodeIfPresent(PlanWithdrawals.self, forKey: .withdrawals) ?? PlanWithdrawals()
        simulation = try c.decodeIfPresent(PlanSimulation.self, forKey: .simulation) ?? PlanSimulation()
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(retirement, forKey: .retirement)
        try c.encodeIfPresent(endAge, forKey: .endAge)
        if !tax.isEmpty { try c.encode(tax, forKey: .tax) }
        try c.encodeIfNotEmpty(work, forKey: .work)
        try c.encode(spending, forKey: .spending)
        try c.encodeIfNotEmpty(pensions, forKey: .pensions)
        try c.encodeIfNotEmpty(contributions, forKey: .contributions)
        try c.encodeIfNotEmpty(events, forKey: .events)
        if !portfolio.isEmpty { try c.encode(portfolio, forKey: .portfolio) }
        if !assumptions.isEmpty { try c.encode(assumptions, forKey: .assumptions) }
        if !withdrawals.isEmpty { try c.encode(withdrawals, forKey: .withdrawals) }
        if !simulation.isEmpty { try c.encode(simulation, forKey: .simulation) }
    }
}

/// A plan's `retirement` section.
public struct PlanRetirement: Codable, Hashable, Sendable, KnownKeysProviding {
    /// The age work stops, or `earliest` to let the planner find it.
    public var age: AgeChoice

    public init(age: AgeChoice) {
        self.age = age
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case age
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}
