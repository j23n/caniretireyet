import Foundation
import Model

/// What-if changes applied on top of a plan for one run, without saving it
/// (UI.md, "What if"). `nil` fields keep the plan's value.
public struct PlanWhatIf: Hashable, Sendable {
    public var retirementAge: Int?
    /// Yearly spending in retirement, in today's money.
    public var retiredSpending: Decimal?
    /// Monthly saving while working.
    public var monthlySaving: Decimal?
    /// Equity's median real return (its typical year), as a fraction; the
    /// mean follows from it and the plan's volatility.
    public var equityReturn: Decimal?

    public init(retirementAge: Int? = nil, retiredSpending: Decimal? = nil, monthlySaving: Decimal? = nil,
                equityReturn: Decimal? = nil) {
        self.retirementAge = retirementAge
        self.retiredSpending = retiredSpending
        self.monthlySaving = monthlySaving
        self.equityReturn = equityReturn
    }

    public var isEmpty: Bool {
        retirementAge == nil && retiredSpending == nil && monthlySaving == nil && equityReturn == nil
    }

    /// Equity's volatility when the plan has no return assumption for it.
    static let defaultEquityVolatility = Decimal(17) / 100

    /// `plan` with these changes: the retirement age, retirement spending,
    /// equity's median return (its typical year, keeping its volatility and
    /// income yield; the default isn't written), and saving per month,
    /// which moves spending while working by as much (a month's saving more
    /// is 12 × that less spent a year). Without `baseMonthlySaving`, a
    /// saving change can't be applied and is left out.
    public func applied(to plan: PlanDocument, baseMonthlySaving: Decimal?) -> PlanDocument {
        var plan = plan
        if let retirementAge {
            plan.retirement.age = .age(retirementAge)
        }
        if let retiredSpending {
            plan.spending.retired = max(0, retiredSpending)
        }
        if let monthlySaving, let baseMonthlySaving {
            plan.spending.working = max(0, plan.spending.working - (monthlySaving - baseMonthlySaving) * 12)
        }
        if let equityReturn {
            let current = plan.assumptions.returnAssumption(for: .equity)
            plan.assumptions.setReturnAssumption(ReturnAssumption(
                medianReal: equityReturn, volatility: current?.volatility ?? Self.defaultEquityVolatility,
                incomeYield: current?.incomeYield), for: .equity)
        }
        return plan
    }
}
