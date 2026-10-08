import Foundation
import Model

/// How one run ended.
struct RunOutcome: Sendable {
    /// Where it failed, if it did.
    let failure: RunFailure?
    /// The index of the year it failed in.
    let failedYear: Int?
    /// Plan assets at the end (0 after a failure).
    let finalValue: Double
    /// With flexible spending, the lowest spending level paid in a
    /// retirement year, as a share of the plan's spending (0 for a run that
    /// fails: its spending falls below the floor, then to nothing); 1 without.
    var lowestLevel = 1.0
    /// With flexible spending, the retirement years in which spending was
    /// below 100% of the plan's, every year from a failure on included.
    var yearsBelowPlan = 0
}

/// Simulates the paths of one retirement age, following PLANNER.md, "The
/// yearly step". It keeps its buffers between runs, so a worker makes one
/// and reuses it for all its runs.
///
/// Each year:
/// 1. Money that becomes available at this age joins the money you can draw.
/// 2. Income from work and pensions and the year's windfalls come in;
///    spending, one-off expenses, contributions into accounts, the wealth
///    tax and last year's tax on investment income go out.
/// 3. What's left is invested in the money you can draw, at its target mix;
///    a shortfall is sold from it, more by the tax on the gain part of what's
///    sold. With flexible spending, a shortfall first cuts spending, as far
///    as the floor. When it can't be covered, the run fails.
/// 4. Every bucket is rebalanced to its mix (the money you can draw to the
///    target mix at this year's age, without tax); the year's income on
///    investments is taxed next year; the markets move every class; purchase
///    costs lose the year's inflation (gains are taxed in money of the day).
struct PathSimulator: Sendable {
    let model: PlanModel
    let schedule: AgeSchedule
    let scenarios: MarketScenarios
    let start: Portfolio
    /// The plan's flexible-spending rule, if it has one.
    let flexible: FlexibleSpendingSpec?

    /// Plan assets at each year-end of the last run with `recordValues`
    /// (0 from a failure on).
    private(set) var yearValues: [Double]
    /// The spending paid in each year of the last run with `recordValues`.
    private(set) var yearSpending: [Double]

    private var values: [[Double]]
    private var basis: [Double]
    /// Each bucket's own mix, kept while it's locked.
    private let ownMix: [[Double]?]
    private let classCount: Int

    static let tolerance = 1.0
    static let levelEpsilon = 1e-9

    init(model: PlanModel, schedule: AgeSchedule, scenarios: MarketScenarios, start: Portfolio) {
        self.model = model
        self.schedule = schedule
        self.scenarios = scenarios
        self.start = start
        flexible = model.spending.flexible
        classCount = start.classes.count
        values = start.buckets.map(\.values)
        basis = start.buckets.map(\.basis)
        ownMix = start.buckets.map { AgeSchedule.shares(of: $0.values) }
        yearValues = Array(repeating: 0, count: model.frames.count)
        yearSpending = Array(repeating: 0, count: model.frames.count)
    }

    /// The years with retirement spending at this age.
    var retirementYears: Int { schedule.retirementYears }

    /// One Monte Carlo run (`run`), or the deterministic run (`nil`), at
    /// retirement spending `spending` (before phase factors).
    mutating func run(_ run: Int?, spending: Double, recordValues: Bool = false) -> RunOutcome {
        var details: [YearDetail]?
        return simulate(run, spending: spending, recordValues: recordValues, details: &details)
    }

    /// A run with every year's detail.
    mutating func detailedRun(_ run: Int?, spending: Double) -> (RunOutcome, [YearDetail]) {
        var details: [YearDetail]? = []
        let outcome = simulate(run, spending: spending, recordValues: false, details: &details)
        return (outcome, details ?? [])
    }

    // MARK: - The yearly step

    private mutating func simulate(_ run: Int?, spending planSpending: Double, recordValues: Bool,
                                   details: inout [YearDetail]?) -> RunOutcome {
        for b in values.indices {
            values[b] = start.buckets[b].values
            basis[b] = start.buckets[b].basis
        }
        let mask = run.map { scenarios.eventMasks[$0] } ?? scenarios.expectedEvents
        let taxes = model.taxes
        var carriedTax = 0.0
        var level = 1.0
        var initialRate: Double?
        var lowestLevel = 1.0
        var yearsBelowPlan = 0

        for t in schedule.income.indices {
            let frame = model.frames[t]
            for b in schedule.opens[t] { open(b) }
            let startAssets = total()

            // Taxes due: the wealth tax on the money you can draw, and last
            // year's tax on investment income.
            let wealthTax = taxes.wealthRate * max(0, value(0) - taxes.wealthAllowance) * frame.fraction
            let incomeTax = carriedTax
            carriedTax = 0

            // Flexible spending: in a year retired throughout, this year's
            // withdrawal rate against the first retirement year's moves the level.
            let retiredSpending = schedule.retiredUnit[t] * planSpending
            if let flexible, schedule.retiredUnit[t] > 0, schedule.fullyRetired[t] {
                let draw = frame.fraction > 0
                    ? max(0, retiredSpending * level - schedule.regularIncome[t]) / frame.fraction : 0
                let assets = startAssets - incomeTax
                if let initial = initialRate {
                    let current = assets > 0 ? draw / assets : .infinity
                    if current > initial * (1 + flexible.upper), level > flexible.floor + Self.levelEpsilon {
                        level = Self.snapped(max(flexible.floor, level - flexible.cut))
                    } else if current < initial * (1 - flexible.lower), level < 1 - Self.levelEpsilon {
                        level = Self.snapped(min(1, level + flexible.cut))
                    }
                } else if draw * frame.fraction > Self.tolerance, assets > 0 {
                    initialRate = draw / assets
                }
            }

            // The year's cash flow.
            var windfalls: [IncomeItem] = []
            var expenses = 0.0
            for index in schedule.events[t] {
                let event = model.events[index]
                guard event.happens(in: mask) else { continue }
                if event.amount > 0 {
                    windfalls.append(IncomeItem(kind: .windfall, id: "event-\(event.index)", label: event.name,
                                                amount: event.amount))
                } else {
                    expenses -= event.amount
                }
            }
            var contributed = 0.0
            for contribution in schedule.contributions[t] {
                deposit(contribution.amount, into: contribution.bucket, mix: schedule.accessibleMix[t])
                contributed += contribution.amount
            }
            let spending = schedule.workingSpending[t] + retiredSpending * level
            let cash = schedule.regularIncome[t] + windfalls.reduce(0) { $0 + $1.amount } - expenses - spending
                - contributed - wealthTax - incomeTax
            guard cash.isFinite else {
                return fail(t, reason: .depleted, spending: spending, paid: 0,
                            level: level, retiredSpending: retiredSpending, yearsBelowPlan: yearsBelowPlan,
                            recordValues: recordValues, details: &details)
            }
            var sold = 0.0
            var gainTax = 0.0
            var shortfall = 0.0
            if cash >= 0 {
                deposit(cash, into: 0, mix: schedule.accessibleMix[t])
            } else {
                (sold, gainTax, shortfall) = withdraw(-cash, rate: taxes.investmentRate)
            }

            // With flexible spending, money that runs short is spending forced
            // down, as far as the floor; only below it does the run fail.
            var paid = spending
            var paidLevel = level
            if let flexible, shortfall > Self.tolerance, retiredSpending > 0 {
                let room = retiredSpending * max(0, level - flexible.floor)
                if shortfall <= room + Self.tolerance {
                    paid = spending - min(shortfall, room)
                    paidLevel = level - (spending - paid) / retiredSpending
                    shortfall = 0
                }
            }
            if flexible != nil, retiredSpending > 0, shortfall <= Self.tolerance {
                lowestLevel = min(lowestLevel, paidLevel)
                if paidLevel < 1 - Self.levelEpsilon { yearsBelowPlan += 1 }
            }
            if shortfall > Self.tolerance || !shortfall.isFinite {
                let reason = shortfall.isFinite
                    ? failureReason(year: t, shortfall: shortfall, spending: planSpending, level: level) : .depleted
                return fail(t, reason: reason, spending: spending,
                            paid: spending - shortfall, level: level, retiredSpending: retiredSpending,
                            yearsBelowPlan: yearsBelowPlan, recordValues: recordValues, details: &details)
            }

            // Rebalancing, income on investments (taxed next year), then the markets.
            rebalance(0, to: schedule.accessibleMix[t])
            for b in values.indices.dropFirst() {
                if let mix = ownMix[b] { rebalance(b, to: mix) }
            }
            var investmentIncome = 0.0
            for c in 0..<classCount { investmentIncome += values[0][c] * model.incomeYields[c] * frame.fraction }
            carriedTax = taxes.investmentRate * investmentIncome
            basis[0] += investmentIncome
            for b in values.indices {
                for c in 0..<classCount {
                    let factor = run.map { scenarios.factors[($0 * scenarios.years + t) * classCount + c] }
                        ?? scenarios.expectedFactors[t * classCount + c]
                    values[b][c] *= factor
                }
                basis[b] /= frame.inflationStep
            }

            let endAssets = total()
            guard endAssets.isFinite else {
                return fail(t, reason: .depleted, spending: spending, paid: paid,
                            level: level, retiredSpending: retiredSpending, yearsBelowPlan: yearsBelowPlan,
                            recordValues: recordValues, details: &details)
            }
            if recordValues {
                yearValues[t] = endAssets
                yearSpending[t] = paid
            }
            if details != nil {
                var income = schedule.income[t]
                income += windfalls
                if sold > 0 {
                    income.append(IncomeItem(kind: .withdrawal, id: "withdrawal", label: "Investments sold",
                                             amount: sold))
                }
                details!.append(YearDetail(
                    year: frame.year, age: frame.age, fraction: frame.fraction,
                    workingShare: schedule.workingShare[t], endAssets: endAssets,
                    spending: paid, expenses: expenses, income: income,
                    investmentTax: gainTax + incomeTax, wealthTax: wealthTax,
                    savings: contributed + max(0, cash) - sold,
                    plannedSpending: flexible == nil ? nil : schedule.workingSpending[t] + retiredSpending,
                    spendingLevel: flexible != nil && retiredSpending > 0 ? paidLevel : nil))
            }
        }
        return RunOutcome(failure: nil, failedYear: nil, finalValue: total(), lowestLevel: lowestLevel,
                          yearsBelowPlan: yearsBelowPlan)
    }

    /// Ends the run as failed in year `t`.
    private mutating func fail(_ t: Int, reason: FailureReason, spending: Double, paid: Double,
                               level: Double, retiredSpending: Double, yearsBelowPlan: Int, recordValues: Bool,
                               details: inout [YearDetail]?) -> RunOutcome {
        let frame = model.frames[t]
        let failure = RunFailure(year: frame.year, age: frame.age, reason: reason)
        let left = total()
        let remaining = left.isFinite ? left : 0
        if recordValues {
            yearValues[t] = remaining
            yearSpending[t] = paid.isFinite ? max(0, paid) : 0
            for later in (t + 1)..<model.frames.count {
                yearValues[later] = 0
                yearSpending[later] = 0
            }
        }
        if details != nil {
            details!.append(YearDetail(
                year: frame.year, age: frame.age, fraction: frame.fraction, workingShare: schedule.workingShare[t],
                endAssets: remaining, spending: spending,
                income: schedule.income[t],
                plannedSpending: flexible == nil ? nil : schedule.workingSpending[t] + retiredSpending,
                spendingLevel: flexible != nil && retiredSpending > 0 ? level : nil))
        }
        var outcome = RunOutcome(failure: failure, failedYear: t, finalValue: 0)
        if flexible != nil {
            outcome.lowestLevel = 0
            let retiredYearsLeft = (t..<model.frames.count).filter { schedule.retiredUnit[$0] > 0 }.count
            outcome.yearsBelowPlan = yearsBelowPlan + retiredYearsLeft
        }
        return outcome
    }

    /// Why a run that can't cover year `t` fails: it's a bridging problem
    /// when money still locked away opens within the plan and would have
    /// covered what's missing until then (the shortfall, and the later
    /// years' spending beyond income, in today's money). Of such buckets,
    /// the one that opens first is named.
    private func failureReason(year t: Int, shortfall: Double, spending: Double, level: Double) -> FailureReason {
        var bridge: (bucket: Int, opens: Int)?
        for b in values.indices.dropFirst() where value(b) > Self.tolerance {
            guard let opens = schedule.opens.indices.dropFirst(t + 1).first(where: { schedule.opens[$0].contains(b) })
            else { continue }
            var need = shortfall
            for later in (t + 1)..<opens {
                need += max(0, schedule.workingSpending[later] + schedule.retiredUnit[later] * spending * level
                    - schedule.regularIncome[later])
            }
            if value(b) >= need, opens < bridge?.opens ?? .max { bridge = (b, opens) }
        }
        guard let bridge else { return .depleted }
        let bucket = start.buckets[bridge.bucket]
        return .locked(LockedMoney(name: bucket.name, accessibleFromAge: bucket.opensAtAge))
    }

    // MARK: - Moving money

    private func value(_ b: Int) -> Double {
        var sum = 0.0
        for c in 0..<classCount { sum += values[b][c] }
        return sum
    }

    private func total() -> Double {
        var sum = 0.0
        for b in values.indices { sum += value(b) }
        return sum
    }

    /// Moves bucket `b` into the money you can draw.
    private mutating func open(_ b: Int) {
        for c in 0..<classCount {
            values[0][c] += values[b][c]
            values[b][c] = 0
        }
        basis[0] += basis[b]
        basis[b] = 0
    }

    /// Invests `amount` in bucket `b`: the money you can draw at `mix`, a
    /// locked bucket at its own mix. New money costs what was paid for it.
    private mutating func deposit(_ amount: Double, into b: Int, mix: [Double]) {
        guard amount > 0 else { return }
        let shares = b == 0 ? mix : (ownMix[b] ?? mix)
        for c in 0..<classCount { values[b][c] += amount * shares[c] }
        basis[b] += amount
    }

    /// Sells enough of the money you can draw to pay `need` after the tax
    /// on the gain part of what's sold, across its classes in proportion.
    /// Returns what was sold, that tax, and what couldn't be covered.
    private mutating func withdraw(_ need: Double, rate: Double)
        -> (sold: Double, tax: Double, shortfall: Double) {
        let available = value(0)
        guard available > 0 else { return (0, 0, need) }
        let gainShare = min(1, max(0, 1 - basis[0] / available))
        let kept = 1 - rate * gainShare
        guard kept > 0 else { return (0, 0, need) }
        let gross = need / kept
        let sold = min(gross, available)
        let remaining = 1 - sold / available
        for c in 0..<classCount { values[0][c] *= remaining }
        basis[0] *= remaining
        let tax = rate * gainShare * sold
        return (sold, tax, max(0, need - (sold - tax)))
    }

    /// Rebalances bucket `b` to `mix`, without tax.
    private mutating func rebalance(_ b: Int, to mix: [Double]) {
        let total = value(b)
        guard total > 0 else { return }
        for c in 0..<classCount { values[b][c] = total * mix[c] }
    }

    // MARK: - Helpers

    /// A level a hair from a whole step, snapped to it, so repeated cuts and
    /// raises land on 90%, 80%, … exactly.
    static func snapped(_ level: Double) -> Double {
        let rounded = (level * 1000).rounded() / 1000
        return abs(rounded - level) < 1e-9 ? rounded : level
    }
}
