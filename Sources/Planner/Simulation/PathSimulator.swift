import Foundation
import Model
import TaxKit

/// How one run ended.
struct RunOutcome: Sendable {
    /// Where it failed, if it did.
    let failure: RunFailure?
    /// The index of the year it failed in.
    let failedYear: Int?
    /// Plan assets at the end (0 after a failure).
    let finalValue: Double
}

/// Simulates the paths of one retirement age, following PLANNER.md, "The
/// yearly step". It keeps its buffers between runs, so a worker makes one
/// and reuses it for all its runs.
///
/// Each year: wrapper credits and planned contributions go in; severance pay
/// whose job ends is paid out; income minus taxes, spending and last year's
/// market-dependent taxes is invested, or the shortfall is withdrawn (cash
/// above the buffer, then the liquid buckets proportionally, then accessible
/// tax-advantaged buckets, then the buffer); lots earn the year's returns
/// (or their wrapper's legal revaluation); buckets are rebalanced; and the
/// tax system assesses sales, payouts, interest and year-end balances.
/// Market-dependent taxes beyond what sales and payouts already withheld are
/// paid the following year.
///
/// Tax-advantaged buckets keep their cost basis as a whole: what was paid in
/// (contributions and credits), deflated by inflation, reduced pro rata by
/// payouts, and untouched by growth and rebalancing.
struct PathSimulator {
    private let schedule: AgeSchedule
    private let scenarios: MarketScenarios
    private let portfolio: Portfolio
    private let cashBuffer: Double
    private let classCount: Int
    private let cashClass: Int?
    private let lotClass: [Int]
    private let lotIsCash: [Bool]
    private let lotDocumented: [Bool]
    private let lotCategory: [TaxCategory]
    private let bucketStart: [Int]
    private let bucketEnd: [Int]
    private let bucketLiquid: [Bool]
    private let bucketGrowthTax: [Double]
    private let bucketWrapper: [String]
    /// Per year and bucket (`year * buckets + bucket`), the real growth factor
    /// of a wrapper revalued by law instead of by the markets, else 0.
    private let revaluationFactors: [Double]
    /// Per bucket, the cost basis of a tax-advantaged bucket at the start.
    private let startWrapperBasis: [Double]
    private let inflationSteps: [Double]
    private let yearFraction: [Double]
    private let yearWorkingSpending: [Double]
    private let yearRetiredUnit: [Double]
    private let yearContributions: [Double]

    private var values: [Double]
    private var bases: [Double]
    /// Per tax-advantaged bucket, what was paid in (see the type's comment).
    private var wrapperBasis: [Double]
    private var variable = VariableYear()
    private var classValues: [Double]
    private var classTargets: [Double]
    private var sellable: [Double]
    private var categoryShares: [TaxCategory: Double] = [:]
    private var withheld = 0.0
    private var sold: [Double]
    /// Year-end plan assets of the last run, when recorded.
    private(set) var yearValues: [Double]

    private static let epsilon = 1e-6
    /// A shortfall up to this many euros doesn't count as failing.
    private static let tolerance = 1.0
    /// How closely a numeric gross-up matches the cash needed, in euros.
    private static let grossUpTolerance = 0.001

    init(schedule: AgeSchedule, scenarios: MarketScenarios, portfolio: Portfolio, model: PlanModel) {
        self.schedule = schedule
        self.scenarios = scenarios
        self.portfolio = portfolio
        cashBuffer = model.cashBuffer
        classCount = portfolio.classCount
        cashClass = portfolio.classes.firstIndex(of: .cash)
        lotClass = portfolio.lots.map(\.classIndex)
        lotIsCash = portfolio.lots.map(\.isCash)
        lotDocumented = portfolio.lots.map(\.documented)
        lotCategory = portfolio.lots.map(\.category)
        bucketStart = portfolio.buckets.map(\.lots.lowerBound)
        bucketEnd = portfolio.buckets.map(\.lots.upperBound)
        bucketLiquid = portfolio.buckets.map(\.isLiquid)
        bucketGrowthTax = portfolio.buckets.map(\.growthTaxRate)
        bucketWrapper = portfolio.buckets.map(\.wrapper)
        var revaluationFactors = [Double](repeating: 0, count: schedule.years.count * portfolio.buckets.count)
        for (b, bucket) in portfolio.buckets.enumerated() {
            guard let revaluation = bucket.rule?.revaluation else { continue }
            let real = revaluation.realRate(inflation: model.inflation, taxRate: bucket.rule?.growthTaxRate ?? 0)
            for t in schedule.years.indices {
                revaluationFactors[t * portfolio.buckets.count + b] = pow(1 + real, schedule.years[t].fraction)
            }
        }
        self.revaluationFactors = revaluationFactors
        startWrapperBasis = portfolio.buckets.map { bucket in
            bucket.isLiquid ? 0 : portfolio.lots[bucket.lots].reduce(0) { $0 + $1.basis }
        }
        wrapperBasis = startWrapperBasis
        inflationSteps = model.frames.map(\.inflationStep)
        yearFraction = schedule.years.map(\.fraction)
        yearWorkingSpending = schedule.years.map(\.workingSpending)
        yearRetiredUnit = schedule.years.map(\.retiredUnit)
        yearContributions = schedule.years.map(\.contributionTotal)
        // Every lot reports a year-end balance; only the values change.
        variable.balances = portfolio.lots.map { lot in
            VariableYear.Balance(wrapper: portfolio.buckets[lot.bucket].wrapper, category: lot.category,
                                 country: lot.country, value: 0)
        }
        values = portfolio.lots.map(\.value)
        bases = portfolio.lots.map(\.basis)
        classValues = Array(repeating: 0, count: classCount)
        classTargets = Array(repeating: 0, count: classCount)
        sellable = Array(repeating: 0, count: portfolio.buckets.count)
        sold = Array(repeating: 0, count: portfolio.buckets.count)
        yearValues = Array(repeating: 0, count: schedule.years.count)
    }

    /// Simulates run `run` (or the deterministic run for `nil`) with a
    /// yearly retirement spending of `spending`.
    mutating func run(_ run: Int?, spending: Double, recordValues: Bool = false) -> RunOutcome {
        var details: [YearDetail]?
        return simulate(run, spending: spending, recordValues: recordValues, details: &details)
    }

    /// The same run, with every year's detail.
    mutating func detailedRun(_ run: Int?, spending: Double) -> (RunOutcome, [YearDetail]) {
        var details: [YearDetail]? = []
        let outcome = simulate(run, spending: spending, recordValues: true, details: &details)
        return (outcome, details ?? [])
    }

    // MARK: - The yearly loop

    private mutating func simulate(_ run: Int?, spending level: Double, recordValues: Bool,
                                   details: inout [YearDetail]?) -> RunOutcome {
        for index in values.indices {
            values[index] = portfolio.lots[index].value
            bases[index] = portfolio.lots[index].basis
        }
        for b in wrapperBasis.indices { wrapperBasis[b] = startWrapperBasis[b] }
        let mask = run.map { scenarios.eventMasks[$0] } ?? scenarios.expectedEvents
        var carried = 0.0

        for t in schedule.years.indices {
            let v = schedule.years[t].variant(for: mask)
            let prepared = schedule.years[t].variants[v].prepared
            let startAssets = details == nil ? 0 : total()
            withheld = 0
            variable.sales.removeAll(keepingCapacity: true)
            variable.payouts.removeAll(keepingCapacity: true)
            variable.capitalIncome.removeAll(keepingCapacity: true)
            for b in sold.indices { sold[b] = 0 }

            // Money arriving in wrappers, then the year's cash flow.
            var credited = 0.0
            for accrual in schedule.years[t].variants[v].accruals where accrual.amount != 0 {
                deposit(accrual.amount, into: accrual.bucket)
                credited += accrual.amount
            }
            for contribution in schedule.years[t].contributions {
                deposit(contribution.amount, into: contribution.bucket)
            }
            var severancePay = 0.0
            for b in schedule.years[t].severance {
                severancePay += payOutInFull(bucket: b, year: t, prepared: prepared)
            }
            let expenses = schedule.years[t].expenses(for: mask)
            let spending = yearWorkingSpending[t] + yearRetiredUnit[t] * level
            let cash = schedule.years[t].variants[v].netCash + severancePay - yearContributions[t] - spending
                - expenses - carried
            var shortfall = 0.0
            if cash >= 0 {
                deposit(cash, into: portfolio.primaryLiquid)
            } else {
                shortfall = withdraw(-cash, year: t, prepared: prepared)
            }

            if shortfall > Self.tolerance {
                let failure = RunFailure(year: schedule.years[t].year, age: schedule.years[t].age,
                                         reason: failureReason(year: t))
                let remaining = total()
                if recordValues {
                    yearValues[t] = remaining
                    for later in (t + 1)..<schedule.years.count { yearValues[later] = 0 }
                }
                if details != nil {
                    details!.append(detail(t, variant: v, assessment: nil, startAssets: startAssets,
                                           endAssets: remaining, spending: spending, expenses: expenses, cash: cash,
                                           credited: credited))
                }
                return RunOutcome(failure: failure, failedYear: t, finalValue: 0)
            }

            // Markets, rebalancing, and the market-dependent taxes.
            applyReturns(year: t, run: run)
            rebalance()
            let fraction = yearFraction[t]
            for l in values.indices { variable.balances[l].value = values[l] * fraction }
            let assessment = prepared.assess(variable)
            carried = assessment.totalTax + assessment.totalContributions - schedule.years[t].variants[v].fixedTotal
                - withheld

            let endAssets = total() - carried
            if recordValues { yearValues[t] = endAssets }
            if details != nil {
                details!.append(detail(t, variant: v, assessment: assessment, startAssets: startAssets,
                                       endAssets: endAssets, spending: spending, expenses: expenses, cash: cash,
                                       credited: credited))
            }
        }
        return RunOutcome(failure: nil, failedYear: nil, finalValue: total() - carried)
    }

    // MARK: - Money in and out

    /// Invests `amount` in a bucket, split by its target mix. Money paid into
    /// a tax-advantaged bucket adds to its cost basis.
    private mutating func deposit(_ amount: Double, into bucket: Int) {
        guard amount > 0 else { return }
        if !bucketLiquid[bucket] { wrapperBasis[bucket] += amount }
        let row = bucket * classCount
        for c in 0..<classCount {
            let share = portfolio.targetShares[row + c]
            guard share > 0 else { continue }
            let lot = portfolio.depositLot[row + c]
            values[lot] += amount * share
            bases[lot] = lotIsCash[lot] ? values[lot] : bases[lot] + amount * share
        }
    }

    /// Pays a bucket out in full because a job ended (severance pay). The
    /// tax on it is withheld; returns what's left, which joins the year's
    /// cash flow.
    private mutating func payOutInFull(bucket b: Int, year t: Int, prepared: any PreparedTaxYear) -> Double {
        var value = 0.0
        for l in bucketStart[b]..<bucketEnd[b] { value += values[l] }
        guard value > Self.epsilon else { return 0 }
        let before = prepared.assess(variable)
        variable.payouts.append(VariableYear.WrapperPayout(
            wrapper: bucketWrapper[b], amount: value, form: .lumpSum, costBasis: wrapperBasis[b],
            membershipYears: schedule.membershipYears(year: t, bucket: b)))
        let after = prepared.assess(variable)
        let tax = after.totalTax + after.totalContributions - before.totalTax - before.totalContributions
        for l in bucketStart[b]..<bucketEnd[b] {
            values[l] = 0
            bases[l] = 0
        }
        wrapperBasis[b] = 0
        sold[b] += value
        withheld += tax
        return value - tax
    }

    /// Raises `need` in cash, in the documented order. Returns what couldn't be raised.
    private mutating func withdraw(_ need: Double, year t: Int, prepared: any PreparedTaxYear) -> Double {
        var remaining = drawCash(need, year: t, keeping: cashBuffer)
        if remaining > Self.epsilon { remaining = sell(remaining, year: t, liquid: true, prepared: prepared) }
        if remaining > Self.epsilon { remaining = sell(remaining, year: t, liquid: false, prepared: prepared) }
        if remaining > Self.epsilon { remaining = drawCash(remaining, year: t, keeping: 0) }
        return max(0, remaining)
    }

    /// Takes cash from the accessible liquid buckets, above `keeping`.
    private mutating func drawCash(_ amount: Double, year t: Int, keeping: Double) -> Double {
        var available = 0.0
        for b in bucketWrapper.indices where bucketLiquid[b] && schedule.isAccessible(year: t, bucket: b) {
            for l in bucketStart[b]..<bucketEnd[b] where lotIsCash[l] { available += values[l] }
        }
        let usable = available - keeping
        guard usable > Self.epsilon else { return amount }
        let take = min(amount, usable)
        let keep = 1 - take / available
        for b in bucketWrapper.indices where bucketLiquid[b] && schedule.isAccessible(year: t, bucket: b) {
            for l in bucketStart[b]..<bucketEnd[b] where lotIsCash[l] {
                sold[b] += values[l] * (1 - keep)
                values[l] *= keep
                bases[l] = values[l]
            }
        }
        return amount - take
    }

    /// Sells from the accessible liquid buckets (their non-cash lots) or
    /// tax-advantaged buckets, proportionally, to receive `amount` after tax.
    private mutating func sell(_ amount: Double, year t: Int, liquid: Bool, prepared: any PreparedTaxYear) -> Double {
        var remaining = amount
        for _ in 0..<3 {
            var total = 0.0
            for b in bucketWrapper.indices {
                sellable[b] = 0
                guard bucketLiquid[b] == liquid, schedule.isAccessible(year: t, bucket: b) else { continue }
                for l in bucketStart[b]..<bucketEnd[b] where !(liquid && lotIsCash[l]) { sellable[b] += values[l] }
                total += sellable[b]
            }
            guard total > Self.epsilon else { break }
            let target = remaining
            for b in bucketWrapper.indices where sellable[b] > Self.epsilon {
                let net = target * sellable[b] / total
                let gross = grossAmount(net: net, bucket: b, liquid: liquid, year: t, prepared: prepared)
                let sale = min(gross, sellable[b])
                let received = gross > sale ? net * sale / gross : net
                sellLots(sale, of: b, liquid: liquid, year: t)
                withheld += sale - received
                remaining -= received
            }
            if remaining <= Self.epsilon { break }
        }
        return remaining
    }

    /// How much to sell from a bucket to receive `net`: the tax system's
    /// gross-up, or a numeric solve when it has none.
    private mutating func grossAmount(net: Double, bucket b: Int, liquid: Bool, year t: Int,
                                      prepared: any PreparedTaxYear) -> Double {
        var basis = 0.0
        categoryShares.removeAll(keepingCapacity: true)
        for l in bucketStart[b]..<bucketEnd[b] where !(liquid && lotIsCash[l]) && values[l] > 0 {
            if lotDocumented[l] { basis += bases[l] }
            categoryShares[lotCategory[l], default: 0] += values[l] / sellable[b]
        }
        let snapshot = BucketSnapshot(
            wrapper: bucketWrapper[b], value: sellable[b], costBasis: liquid ? basis : wrapperBasis[b],
            categoryShares: categoryShares, membershipYears: liquid ? nil : schedule.membershipYears(year: t, bucket: b))
        if let gross = prepared.grossUp(net: net, from: snapshot), gross.isFinite, gross > 0 {
            return gross
        }
        return solveGross(net: net, bucket: b, liquid: liquid, year: t, prepared: prepared)
    }

    /// Finds the sale that nets `net` by assessing candidate sales, with
    /// TaxKit's `NumericGrossUp`.
    private mutating func solveGross(net: Double, bucket b: Int, liquid: Bool, year t: Int,
                                     prepared: any PreparedTaxYear) -> Double {
        let base = prepared.assess(variable)
        let baseTax = base.totalTax + base.totalContributions
        func netOf(_ gross: Double, _ simulator: inout PathSimulator) -> Double {
            let (sales, payouts) = (simulator.variable.sales.count, simulator.variable.payouts.count)
            simulator.appendCandidate(gross, of: b, liquid: liquid, year: t)
            let assessment = prepared.assess(simulator.variable)
            simulator.variable.sales.removeSubrange(sales...)
            simulator.variable.payouts.removeSubrange(payouts...)
            return gross - (assessment.totalTax + assessment.totalContributions - baseTax)
        }
        let all = sellable[b]
        // Without tax on this sale, the answer is the amount itself.
        let untaxed = min(net, all)
        if netOf(untaxed, &self) >= net - Self.grossUpTolerance { return untaxed }
        if let gross = NumericGrossUp.solve(net: net, upperBound: all, tolerance: Self.grossUpTolerance,
                                            netProceeds: { netOf($0, &self) }) {
            return gross
        }
        // Not enough: report a gross above the bucket so the caller scales down.
        let netOfAll = netOf(all, &self)
        return netOfAll > Self.epsilon ? all * net / netOfAll : all * 2
    }

    /// Adds the sales or payout of a candidate sale to `variable`, without
    /// changing the lots.
    private mutating func appendCandidate(_ gross: Double, of b: Int, liquid: Bool, year t: Int) {
        let q = gross / sellable[b]
        if liquid {
            for l in bucketStart[b]..<bucketEnd[b] where !lotIsCash[l] && values[l] > 0 {
                variable.sales.append(VariableYear.Sale(wrapper: bucketWrapper[b], category: lotCategory[l],
                                                        proceeds: values[l] * q,
                                                        costBasis: lotDocumented[l] ? bases[l] * q : nil))
            }
        } else {
            variable.payouts.append(VariableYear.WrapperPayout(
                wrapper: bucketWrapper[b], amount: gross, form: payoutForm(bucket: b, year: t),
                costBasis: wrapperBasis[b] * min(1, q), membershipYears: schedule.membershipYears(year: t, bucket: b)))
        }
    }

    /// Sells `gross` from a bucket's sellable lots proportionally and records it.
    private mutating func sellLots(_ gross: Double, of b: Int, liquid: Bool, year t: Int) {
        guard gross > 0 else { return }
        appendCandidate(gross, of: b, liquid: liquid, year: t)
        let share = gross / sellable[b]
        let all = share >= 1 - 1e-12
        for l in bucketStart[b]..<bucketEnd[b] where !(liquid && lotIsCash[l]) {
            values[l] = all ? 0 : values[l] - values[l] * share
            bases[l] = lotIsCash[l] ? values[l] : (all ? 0 : bases[l] - bases[l] * share)
        }
        if !liquid { wrapperBasis[b] = all ? 0 : wrapperBasis[b] - wrapperBasis[b] * share }
        sold[b] += gross
    }

    private func payoutForm(bucket b: Int, year t: Int) -> VariableYear.PayoutForm {
        if case .accessible(let route?) = schedule.access[t * schedule.bucketCount + b], !route.isEmpty {
            return .earlyAccess
        }
        return .lumpSum
    }

    // MARK: - Markets

    /// Every lot earns its class's return for the year, or its wrapper's
    /// revaluation when the law sets one (after the wrapper's growth tax).
    /// Wrappers with a tax on growth earn less; interest on liquid cash is
    /// reported as capital income. Cost bases shrink by inflation.
    private mutating func applyReturns(year t: Int, run: Int?) {
        let step = inflationSteps[t]
        let base: Int
        let factors: [Double]
        if let run {
            base = (run * scenarios.years + t) * scenarios.classes
            factors = scenarios.factors
        } else {
            base = t * scenarios.classes
            factors = scenarios.expectedFactors
        }
        let buckets = bucketWrapper.count
        for b in 0..<buckets {
            let revaluation = revaluationFactors[t * buckets + b]
            let growthTax = revaluation > 0 ? 0 : bucketGrowthTax[b]
            if !bucketLiquid[b] { wrapperBasis[b] /= step }
            var interest = 0.0
            for l in bucketStart[b]..<bucketEnd[b] {
                var factor = revaluation > 0 ? revaluation : factors[base + lotClass[l]]
                if growthTax > 0 {
                    let nominal = factor * step - 1
                    factor = (1 + nominal * (1 - growthTax)) / step
                }
                if lotIsCash[l] {
                    if bucketLiquid[b], revaluation == 0 { interest += values[l] * max(0, factor * step - 1) }
                    values[l] *= factor
                    bases[l] = values[l]
                } else {
                    values[l] *= factor
                    bases[l] /= step
                }
            }
            if interest > Self.epsilon {
                variable.capitalIncome.append(VariableYear.CapitalIncome(
                    wrapper: bucketWrapper[b], category: .cash, kind: .interest, amount: interest))
            }
        }
    }

    /// Brings each bucket back to its target mix. Within a class, lots keep
    /// their weights and their share of unrealised gain; the primary liquid
    /// bucket keeps up to the cash buffer in cash.
    private mutating func rebalance() {
        for b in bucketWrapper.indices {
            var bucketValue = 0.0
            for c in 0..<classCount { classValues[c] = 0 }
            for l in bucketStart[b]..<bucketEnd[b] {
                classValues[lotClass[l]] += values[l]
                bucketValue += values[l]
            }
            guard bucketValue > Self.epsilon else { continue }
            let row = b * classCount
            for c in 0..<classCount { classTargets[c] = portfolio.targetShares[row + c] * bucketValue }
            if b == portfolio.primaryLiquid, cashBuffer > 0, let cash = cashClass {
                let keep = min(cashBuffer, classValues[cash])
                if keep > classTargets[cash] {
                    let others = bucketValue - classTargets[cash]
                    let scale = others > Self.epsilon ? (bucketValue - keep) / others : 0
                    for c in 0..<classCount where c != cash { classTargets[c] *= scale }
                    classTargets[cash] = keep
                }
            }
            for c in 0..<classCount {
                let current = classValues[c]
                let target = classTargets[c]
                if current > Self.epsilon {
                    let ratio = target / current
                    for l in bucketStart[b]..<bucketEnd[b] where lotClass[l] == c {
                        values[l] *= ratio
                        bases[l] = lotIsCash[l] ? values[l] : bases[l] * ratio
                    }
                } else if target > Self.epsilon {
                    let lot = portfolio.depositLot[row + c]
                    guard lot >= 0 else { continue }
                    values[lot] += target
                    bases[lot] = lotIsCash[lot] ? values[lot] : bases[lot] + target
                }
            }
        }
    }

    // MARK: - Reporting

    private func total() -> Double {
        values.reduce(0, +)
    }

    /// Why a run failed in year `t`: money still locked in a wrapper, or nothing left.
    private func failureReason(year t: Int) -> FailureReason {
        var locked: (bucket: Int, value: Double)?
        for b in bucketWrapper.indices where !schedule.isAccessible(year: t, bucket: b) {
            var value = 0.0
            for l in bucketStart[b]..<bucketEnd[b] { value += values[l] }
            if value > Self.tolerance, value > (locked?.value ?? 0) { locked = (b, value) }
        }
        guard let locked else { return .depleted }
        let bucket = portfolio.buckets[locked.bucket]
        var reason = ""
        if case .locked(let why) = schedule.access[t * schedule.bucketCount + locked.bucket] { reason = why }
        return .locked(LockedMoney(wrapper: bucket.wrapper, name: bucket.name, value: locked.value,
                                   accessibleFromAge: schedule.accessibleFromAge(bucket: locked.bucket, after: t),
                                   reason: reason))
    }

    private func detail(_ t: Int, variant v: Int, assessment: TaxAssessment?, startAssets: Double,
                        endAssets: Double, spending: Double, expenses: Double, cash: Double,
                        credited: Double) -> YearDetail {
        let year = schedule.years[t]
        let variant = year.variants[v]
        var income = year.income + variant.windfalls
        for b in bucketWrapper.indices where sold[b] > Self.epsilon {
            let bucket = portfolio.buckets[b]
            income.append(IncomeItem(kind: bucket.isLiquid ? .withdrawal : .payout, id: bucket.wrapper,
                                     label: bucket.name, amount: sold[b]))
        }
        var taxes = variant.taxes
        var contributions = variant.contributions
        if let assessment {
            Self.add(assessment.lines, minus: variant.fixed.lines, to: &taxes)
            Self.add(assessment.contributions, minus: variant.fixed.contributions, to: &contributions)
        }
        let withdrawn = sold.reduce(0, +)
        let savings = year.contributionTotal + credited + (cash >= 0 ? cash : 0) - withdrawn
        return YearDetail(year: year.year, age: year.age, fraction: year.fraction, workingShare: year.workingShare,
                          startAssets: startAssets, endAssets: endAssets, spending: spending, expenses: expenses,
                          income: income, taxes: taxes, contributions: contributions, savings: savings)
    }

    /// Adds the market-dependent part of an assessment (its lines minus the
    /// fixed ones, by ID) to `items`.
    private static func add(_ lines: [TaxLine], minus fixed: [TaxLine], to items: inout [AmountItem]) {
        var delta: [String: (label: String, amount: Double)] = [:]
        var order: [String] = []
        for line in lines {
            if delta[line.id] == nil { order.append(line.id) }
            delta[line.id, default: (line.label, 0)].amount += line.amount
        }
        for line in fixed {
            if delta[line.id] == nil { order.append(line.id) }
            delta[line.id, default: (line.label, 0)].amount -= line.amount
        }
        for id in order {
            guard let entry = delta[id], abs(entry.amount) > 0.005 else { continue }
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].amount += entry.amount
            } else {
                items.append(AmountItem(id: id, label: entry.label, amount: entry.amount))
            }
        }
    }
}
