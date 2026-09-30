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
/// market-dependent taxes is invested, or the shortfall is withdrawn (the
/// liquid buckets proportionally, then accessible tax-advantaged buckets,
/// then the cash buffer); buckets are rebalanced; lots earn the year's
/// returns (or their wrapper's legal revaluation); and the tax system
/// assesses sales, payouts, interest and year-end balances. Market-dependent
/// taxes beyond what sales and payouts already withheld are paid the
/// following year.
///
/// **Liquid (taxable) buckets** keep a purchase cost per lot, and money
/// never gains cost basis for free: every sale, including a rebalancing
/// one, realises its share of the unrealised gain and goes to the tax system
/// like any other; bought lots cost what was paid for them. Money coming in
/// goes to the classes furthest below the target mix, and money going out
/// comes from those furthest above it, so the cash flows rebalance first and
/// only what's still off target is sold.
///
/// **Tax-advantaged buckets** keep their cost basis as a whole: what was paid
/// in (contributions and credits), deflated by inflation, reduced pro rata by
/// payouts, and untouched by growth and rebalancing, which is tax-free inside
/// the wrapper.
struct PathSimulator {
    private let schedule: AgeSchedule
    private let scenarios: MarketScenarios
    private let portfolio: Portfolio
    private let cashBuffer: Double
    private let classCount: Int
    private let cashClass: Int?
    private let primaryLiquid: Int
    private let lotClass: [Int]
    private let lotIsCash: [Bool]
    private let lotDocumented: [Bool]
    private let lotCategory: [TaxCategory]
    private let bucketStart: [Int]
    private let bucketEnd: [Int]
    private let bucketLiquid: [Bool]
    private let bucketGrowthTax: [Double]
    private let bucketWrapper: [String]
    /// Target share per bucket and class: `bucket * classCount + class`.
    private let targetShares: [Double]
    /// The lot new money goes into per bucket and class (`-1` for none).
    private let depositLot: [Int]
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
    /// Per class, scratch space for the bucket being worked on: its value,
    /// the shares it's steered to, the part that follows them, what to sell
    /// and what to buy.
    private var classValues: [Double]
    private var classShares: [Double]
    private var classPool: [Double]
    private var classSales: [Double]
    private var classPurchases: [Double]
    private var classOrder: [Int]
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
    /// Rebalancing trades below this many euros are skipped.
    private static let rebalanceTolerance = 0.01

    init(schedule: AgeSchedule, scenarios: MarketScenarios, portfolio: Portfolio, model: PlanModel) {
        self.schedule = schedule
        self.scenarios = scenarios
        self.portfolio = portfolio
        cashBuffer = model.cashBuffer
        classCount = portfolio.classCount
        cashClass = portfolio.classes.firstIndex(of: .cash)
        primaryLiquid = portfolio.primaryLiquid
        lotClass = portfolio.lots.map(\.classIndex)
        lotIsCash = portfolio.lots.map(\.isCash)
        lotDocumented = portfolio.lots.map(\.documented)
        lotCategory = portfolio.lots.map(\.category)
        bucketStart = portfolio.buckets.map(\.lots.lowerBound)
        bucketEnd = portfolio.buckets.map(\.lots.upperBound)
        bucketLiquid = portfolio.buckets.map(\.isLiquid)
        bucketGrowthTax = portfolio.buckets.map(\.growthTaxRate)
        bucketWrapper = portfolio.buckets.map(\.wrapper)
        targetShares = portfolio.targetShares
        depositLot = portfolio.depositLot
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
        classShares = Array(repeating: 0, count: classCount)
        classPool = Array(repeating: 0, count: classCount)
        classSales = Array(repeating: 0, count: classCount)
        classPurchases = Array(repeating: 0, count: classCount)
        classOrder = Array(repeating: 0, count: classCount)
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
                deposit(cash, into: primaryLiquid)
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

            // Rebalancing what the cash flows left off target, the markets,
            // and the market-dependent taxes.
            for b in bucketWrapper.indices {
                if bucketLiquid[b] {
                    rebalanceTaxable(b, year: t, prepared: prepared)
                } else {
                    rebalanceWithoutTax(b)
                }
            }
            applyReturns(year: t, run: run)
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

    // MARK: - Money in

    /// Invests `amount` in a bucket. A liquid bucket's money goes to the
    /// classes furthest below its target mix first, so saving rebalances
    /// without selling. A tax-advantaged bucket's is split by its target mix
    /// and adds to its cost basis. New money costs what was paid for it.
    private mutating func deposit(_ amount: Double, into b: Int) {
        guard amount > 0 else { return }
        let row = b * classCount
        if bucketLiquid[b] {
            let value = loadClassValues(b)
            let kept = steer(b, finalTotal: value + amount)
            loadPool(kept: kept)
            if Self.purchases(of: amount, pool: classPool, shares: classShares, order: &classOrder,
                              into: &classPurchases) {
                for c in 0..<classCount where classPurchases[c] > 0 {
                    buy(classPurchases[c], into: depositLot[row + c])
                }
                return
            }
        } else {
            wrapperBasis[b] += amount
        }
        for c in 0..<classCount {
            let share = targetShares[row + c]
            guard share > 0 else { continue }
            buy(amount * share, into: depositLot[row + c])
        }
    }

    /// Adds money to a lot at its price: its cost basis rises by the amount.
    private mutating func buy(_ amount: Double, into lot: Int) {
        guard lot >= 0, amount > 0 else { return }
        values[lot] += amount
        bases[lot] = lotIsCash[lot] ? values[lot] : bases[lot] + amount
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

    // MARK: - Money out

    /// Raises `need` in cash, in the documented order: the liquid buckets
    /// (keeping the cash buffer), accessible tax-advantaged buckets, then the
    /// buffer. Returns what couldn't be raised.
    private mutating func withdraw(_ need: Double, year t: Int, prepared: any PreparedTaxYear) -> Double {
        var remaining = sellLiquid(need, year: t, prepared: prepared, keepingBuffer: true)
        if remaining > Self.epsilon { remaining = sellWrappers(remaining, year: t, prepared: prepared) }
        if remaining > Self.epsilon {
            remaining = sellLiquid(remaining, year: t, prepared: prepared, keepingBuffer: false)
        }
        return max(0, remaining)
    }

    /// Sells from the accessible liquid buckets, in proportion to what each
    /// can sell, to receive `amount` after tax. With `keepingBuffer`, the
    /// primary bucket's cash buffer isn't touched. Returns what's still needed.
    private mutating func sellLiquid(_ amount: Double, year t: Int, prepared: any PreparedTaxYear,
                                     keepingBuffer: Bool) -> Double {
        var remaining = amount
        for _ in 0..<3 {
            var total = 0.0
            for b in bucketWrapper.indices {
                sellable[b] = 0
                guard bucketLiquid[b], schedule.isAccessible(year: t, bucket: b) else { continue }
                let value = loadClassValues(b)
                sellable[b] = max(0, value - (keepingBuffer ? bufferFloor(b) : 0))
                total += sellable[b]
            }
            guard total > Self.epsilon else { break }
            let target = remaining
            for b in bucketWrapper.indices where bucketLiquid[b] && sellable[b] > Self.epsilon {
                remaining -= sellFromLiquid(b, net: target * sellable[b] / total, limit: sellable[b], year: t,
                                            prepared: prepared, keepingBuffer: keepingBuffer)
            }
            if remaining <= Self.epsilon { break }
        }
        return remaining
    }

    /// Sells from liquid bucket `b` (at most `limit`) to receive `net` after
    /// tax: first what the target mix doesn't want, then the classes furthest
    /// above their share, down to a common level. The sale is grossed up for
    /// its tax, which is withheld. Returns what was received.
    private mutating func sellFromLiquid(_ b: Int, net: Double, limit: Double, year t: Int,
                                         prepared: any PreparedTaxYear, keepingBuffer: Bool) -> Double {
        guard net > 0, limit > Self.epsilon else { return 0 }
        let value = loadClassValues(b)
        // Which classes are sold depends on the amount, and the amount on the
        // tax: the second round settles both, then the sale is scaled to the net.
        var gross = min(net, limit)
        var tax = 0.0
        for round in 0..<2 {
            let kept = steer(b, finalTotal: value - gross, keepingBuffer: keepingBuffer)
            loadPool(kept: kept)
            Self.sales(of: gross, pool: classPool, shares: classShares, order: &classOrder, into: &classSales)
            tax = saleTax(b, year: t, prepared: prepared)
            guard tax > 0, gross - tax > Self.epsilon else { break }
            let wanted = min(limit, gross * net / (gross - tax))
            if round == 1 || abs(wanted - gross) <= Self.grossUpTolerance {
                if wanted != gross {
                    // A class already sold out can't give more; the next pass covers any difference.
                    let scale = wanted / gross
                    for c in 0..<classCount { classSales[c] = min(classPool[c], classSales[c] * scale) }
                    tax = saleTax(b, year: t, prepared: prepared)
                }
                break
            }
            gross = wanted
        }
        let proceeds = applySales(b)
        let received = max(0, proceeds - tax)
        withheld += proceeds - received
        sold[b] += proceeds
        return received
    }

    /// Sells from the accessible tax-advantaged buckets proportionally, as
    /// payouts, to receive `amount` after tax. Returns what's still needed.
    private mutating func sellWrappers(_ amount: Double, year t: Int, prepared: any PreparedTaxYear) -> Double {
        var remaining = amount
        for _ in 0..<3 {
            var total = 0.0
            for b in bucketWrapper.indices {
                sellable[b] = 0
                guard !bucketLiquid[b], schedule.isAccessible(year: t, bucket: b) else { continue }
                for l in bucketStart[b]..<bucketEnd[b] { sellable[b] += values[l] }
                total += sellable[b]
            }
            guard total > Self.epsilon else { break }
            let target = remaining
            for b in bucketWrapper.indices where !bucketLiquid[b] && sellable[b] > Self.epsilon {
                let net = target * sellable[b] / total
                let gross = grossPayout(net: net, bucket: b, year: t, prepared: prepared)
                let sale = min(gross, sellable[b])
                let received = gross > sale ? net * sale / gross : net
                payOut(sale, from: b, year: t)
                withheld += sale - received
                remaining -= received
            }
            if remaining <= Self.epsilon { break }
        }
        return remaining
    }

    /// How much to pay out of a tax-advantaged bucket to receive `net`: the
    /// tax system's gross-up, or a numeric solve when it has none.
    private mutating func grossPayout(net: Double, bucket b: Int, year t: Int, prepared: any PreparedTaxYear) -> Double {
        categoryShares.removeAll(keepingCapacity: true)
        for l in bucketStart[b]..<bucketEnd[b] where values[l] > 0 {
            categoryShares[lotCategory[l], default: 0] += values[l] / sellable[b]
        }
        let snapshot = BucketSnapshot(wrapper: bucketWrapper[b], value: sellable[b], costBasis: wrapperBasis[b],
                                      categoryShares: categoryShares,
                                      membershipYears: schedule.membershipYears(year: t, bucket: b))
        if let gross = prepared.grossUp(net: net, from: snapshot), gross.isFinite, gross > 0 {
            return gross
        }
        return solvePayout(net: net, bucket: b, year: t, prepared: prepared)
    }

    /// Finds the payout that nets `net` by assessing candidates, with
    /// TaxKit's `NumericGrossUp`.
    private mutating func solvePayout(net: Double, bucket b: Int, year t: Int, prepared: any PreparedTaxYear) -> Double {
        let base = prepared.assess(variable)
        let baseTax = base.totalTax + base.totalContributions
        func netOf(_ gross: Double, _ simulator: inout PathSimulator) -> Double {
            let payouts = simulator.variable.payouts.count
            simulator.variable.payouts.append(simulator.payout(gross, from: b, year: t))
            let assessment = prepared.assess(simulator.variable)
            simulator.variable.payouts.removeSubrange(payouts...)
            return gross - (assessment.totalTax + assessment.totalContributions - baseTax)
        }
        let all = sellable[b]
        // Without tax on this payout, the answer is the amount itself.
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

    /// A payout of `gross` from tax-advantaged bucket `b`, with its share of
    /// what was paid in.
    private func payout(_ gross: Double, from b: Int, year t: Int) -> VariableYear.WrapperPayout {
        VariableYear.WrapperPayout(
            wrapper: bucketWrapper[b], amount: gross, form: payoutForm(bucket: b, year: t),
            costBasis: wrapperBasis[b] * min(1, gross / sellable[b]),
            membershipYears: schedule.membershipYears(year: t, bucket: b))
    }

    /// Pays `gross` out of tax-advantaged bucket `b`, from its lots
    /// proportionally, and records it.
    private mutating func payOut(_ gross: Double, from b: Int, year t: Int) {
        guard gross > 0 else { return }
        variable.payouts.append(payout(gross, from: b, year: t))
        let share = gross / sellable[b]
        let all = share >= 1 - 1e-12
        for l in bucketStart[b]..<bucketEnd[b] {
            values[l] = all ? 0 : values[l] - values[l] * share
            bases[l] = lotIsCash[l] ? values[l] : (all ? 0 : bases[l] - bases[l] * share)
        }
        wrapperBasis[b] = all ? 0 : wrapperBasis[b] - wrapperBasis[b] * share
        sold[b] += gross
    }

    private func payoutForm(bucket b: Int, year t: Int) -> VariableYear.PayoutForm {
        if case .accessible(let route?) = schedule.access[t * schedule.bucketCount + b], !route.isEmpty {
            return .earlyAccess
        }
        return .lumpSum
    }

    // MARK: - Selling from a liquid bucket

    /// Loads bucket `b`'s value per class into `classValues`; returns its total.
    @discardableResult
    private mutating func loadClassValues(_ b: Int) -> Double {
        for c in 0..<classCount { classValues[c] = 0 }
        var total = 0.0
        for l in bucketStart[b]..<bucketEnd[b] {
            classValues[lotClass[l]] += values[l]
            total += values[l]
        }
        return total
    }

    /// The cash the primary liquid bucket keeps as its buffer: up to the
    /// buffer, as far as it holds cash. Uses `classValues`.
    private func bufferFloor(_ b: Int) -> Double {
        guard b == primaryLiquid, cashBuffer > 0, let cash = cashClass else { return 0 }
        return min(cashBuffer, max(0, classValues[cash]))
    }

    /// Fills `classShares` with the mix bucket `b` is steered to when it ends
    /// at `finalTotal`, and returns the cash kept out of it: the primary
    /// liquid bucket keeps up to its cash buffer in cash, and when its target
    /// share of cash would be less, the buffer stays aside and the other
    /// classes share the rest in their target proportions. Uses `classValues`.
    private mutating func steer(_ b: Int, finalTotal: Double, keepingBuffer: Bool = true) -> Double {
        let row = b * classCount
        for c in 0..<classCount { classShares[c] = targetShares[row + c] }
        guard keepingBuffer, let cash = cashClass else { return 0 }
        let floor = bufferFloor(b)
        let share = classShares[cash]
        guard floor > 0, share < 1, share * finalTotal < floor else { return 0 }
        classShares[cash] = 0
        for c in 0..<classCount where c != cash { classShares[c] /= 1 - share }
        return floor
    }

    /// `classValues` less the cash `kept` aside, into `classPool`.
    private mutating func loadPool(kept: Double) {
        for c in 0..<classCount { classPool[c] = classValues[c] }
        if kept > 0, let cash = cashClass { classPool[cash] = max(0, classPool[cash] - kept) }
    }

    /// The share of lot `l` sold when its class sells `classSales`.
    @inline(__always)
    private func saleShare(_ l: Int) -> Double {
        let c = lotClass[l]
        guard classSales[c] > 0, classValues[c] > 0 else { return 0 }
        return min(1, classSales[c] / classValues[c])
    }

    /// The tax on selling `classSales` from liquid bucket `b` (each class pro
    /// rata across its lots, at average cost): from the tax system's gross-up
    /// of what's sold, or, when it has none, by assessing the sale on top of
    /// the year so far. Cash is sold at its value, without tax.
    private mutating func saleTax(_ b: Int, year t: Int, prepared: any PreparedTaxYear) -> Double {
        var proceeds = 0.0
        var basis = 0.0
        categoryShares.removeAll(keepingCapacity: true)
        for l in bucketStart[b]..<bucketEnd[b] where !lotIsCash[l] && values[l] > 0 {
            let q = saleShare(l)
            guard q > 0 else { continue }
            let amount = values[l] * q
            proceeds += amount
            if lotDocumented[l] { basis += bases[l] * q }
            categoryShares[lotCategory[l], default: 0] += amount
        }
        guard proceeds > Self.epsilon else { return 0 }
        for index in categoryShares.values.indices { categoryShares.values[index] /= proceeds }
        let snapshot = BucketSnapshot(wrapper: bucketWrapper[b], value: proceeds, costBasis: basis,
                                      categoryShares: categoryShares)
        if let gross = prepared.grossUp(net: proceeds, from: snapshot), gross.isFinite, gross >= proceeds {
            // Selling `gross` nets `proceeds`, so selling `proceeds` nets proceeds² / gross.
            return proceeds - proceeds * proceeds / gross
        }
        let base = prepared.assess(variable)
        let count = variable.sales.count
        appendSales(b)
        let after = prepared.assess(variable)
        variable.sales.removeSubrange(count...)
        return max(0, after.totalTax + after.totalContributions - base.totalTax - base.totalContributions)
    }

    /// Records the sales of `classSales` from bucket `b`'s lots other than
    /// cash, for the tax system.
    private mutating func appendSales(_ b: Int) {
        for l in bucketStart[b]..<bucketEnd[b] where !lotIsCash[l] && values[l] > 0 {
            let q = saleShare(l)
            guard q > 0 else { continue }
            variable.sales.append(VariableYear.Sale(wrapper: bucketWrapper[b], category: lotCategory[l],
                                                    proceeds: values[l] * q,
                                                    costBasis: lotDocumented[l] ? bases[l] * q : nil))
        }
    }

    /// Sells `classSales` from bucket `b`: each class pro rata across its
    /// lots, whose cost basis falls in proportion. Sales of anything but cash
    /// are recorded for the tax system. Returns the proceeds.
    private mutating func applySales(_ b: Int) -> Double {
        appendSales(b)
        var proceeds = 0.0
        for l in bucketStart[b]..<bucketEnd[b] where values[l] > 0 {
            let q = saleShare(l)
            guard q > 0 else { continue }
            let amount = values[l] * q
            proceeds += amount
            if q >= 1 - 1e-12 {
                values[l] = 0
                bases[l] = 0
            } else {
                values[l] -= amount
                bases[l] = lotIsCash[l] ? values[l] : bases[l] * (1 - q)
            }
        }
        return proceeds
    }

    /// Water-filling for a sale: per class (into `sales`), what to sell to
    /// raise `amount` from `pool` so that what's left is as close to `shares`
    /// as it can be. Classes without a share go first; then the classes
    /// furthest above their share, down to a common level, below which every
    /// class sells in proportion to its share.
    static func sales(of amount: Double, pool: [Double], shares: [Double], order: inout [Int],
                      into sales: inout [Double]) {
        var remaining = amount
        var unwanted = 0.0
        for c in pool.indices {
            sales[c] = 0
            if shares[c] <= 0, pool[c] > 0 { unwanted += pool[c] }
        }
        if unwanted > 0 {
            let q = min(1, remaining / unwanted)
            for c in pool.indices where shares[c] <= 0 && pool[c] > 0 { sales[c] = pool[c] * q }
            remaining -= unwanted * q
        }
        guard remaining > 0 else { return }
        // The other classes by how far above their share they are, highest first.
        func ratio(_ c: Int) -> Double { max(0, pool[c]) / shares[c] }
        var count = 0
        for c in pool.indices where shares[c] > 0 {
            let r = ratio(c)
            var i = count
            while i > 0, ratio(order[i - 1]) < r {
                order[i] = order[i - 1]
                i -= 1
            }
            order[i] = c
            count += 1
        }
        var value = 0.0
        var share = 0.0
        for k in 0..<count {
            value += max(0, pool[order[k]])
            share += shares[order[k]]
            let next = k + 1 < count ? ratio(order[k + 1]) : 0
            if value - share * next >= remaining || k + 1 == count {
                let level = max(0, (value - remaining) / share)
                for i in 0...k {
                    let c = order[i]
                    sales[c] += max(0, pool[c] - shares[c] * level)
                }
                return
            }
        }
    }

    /// Water-filling for a purchase: per class (into `purchases`), what to
    /// buy with `amount` so that `pool` comes as close to `shares` as it can:
    /// the classes furthest below their share first, up to a common level,
    /// above which every class buys in proportion to its share. Returns
    /// `false` when no class has a share.
    static func purchases(of amount: Double, pool: [Double], shares: [Double], order: inout [Int],
                          into purchases: inout [Double]) -> Bool {
        func ratio(_ c: Int) -> Double { max(0, pool[c]) / shares[c] }
        var count = 0
        for c in pool.indices {
            purchases[c] = 0
            guard shares[c] > 0 else { continue }
            let r = ratio(c)
            var i = count
            while i > 0, ratio(order[i - 1]) > r {
                order[i] = order[i - 1]
                i -= 1
            }
            order[i] = c
            count += 1
        }
        guard count > 0 else { return false }
        var value = 0.0
        var share = 0.0
        for k in 0..<count {
            value += max(0, pool[order[k]])
            share += shares[order[k]]
            let next = k + 1 < count ? ratio(order[k + 1]) : .infinity
            if share * next - value >= amount || k + 1 == count {
                let level = (amount + value) / share
                for i in 0...k {
                    let c = order[i]
                    purchases[c] = max(0, shares[c] * level - max(0, pool[c]))
                }
                return true
            }
        }
        return true
    }

    // MARK: - Rebalancing

    /// Brings liquid bucket `b` back to its target mix after the year's cash
    /// flows. What's still above target is sold and taxed like any other
    /// sale; the tax is paid from the bucket and the rest buys the classes
    /// below target at their price.
    private mutating func rebalanceTaxable(_ b: Int, year t: Int, prepared: any PreparedTaxYear) {
        let value = loadClassValues(b)
        guard value > Self.epsilon else { return }
        // The bucket ends smaller by the tax, which depends on what's sold.
        // Allowing for a tax T gives a sale taxed g(T); the answer is the
        // fixed point T = g(T), found in one step once g's slope is known
        // (exactly, when the tax is proportional to what's sold).
        var (selling, buying) = rebalancingTrades(b, value: value, allowingForTax: 0)
        guard selling > Self.rebalanceTolerance else { return }
        let first = saleTax(b, year: t, prepared: prepared)
        var tax = first
        if first > Self.grossUpTolerance {
            (selling, buying) = rebalancingTrades(b, value: value, allowingForTax: first)
            let second = saleTax(b, year: t, prepared: prepared)
            tax = second
            let slope = (second - first) / first
            if abs(second - first) > Self.grossUpTolerance, slope < 1 {
                (selling, buying) = rebalancingTrades(b, value: value, allowingForTax: first / (1 - slope))
                tax = saleTax(b, year: t, prepared: prepared)
            }
        }
        let proceeds = applySales(b)
        tax = min(tax, proceeds)
        withheld += tax
        let spend = proceeds - tax
        let row = b * classCount
        if buying > Self.epsilon {
            for c in 0..<classCount where classPurchases[c] > 0 {
                buy(classPurchases[c] * spend / buying, into: depositLot[row + c])
            }
        } else {
            for c in 0..<classCount where classShares[c] > 0 {
                buy(spend * classShares[c], into: depositLot[row + c])
            }
        }
    }

    /// The trades that bring liquid bucket `b` (worth `value`, in
    /// `classValues`) to its target mix once `tax` is paid out of it: what to
    /// sell into `classSales`, what to buy into `classPurchases`, and their totals.
    private mutating func rebalancingTrades(_ b: Int, value: Double, allowingForTax tax: Double)
        -> (selling: Double, buying: Double) {
        let finalTotal = max(0, value - tax)
        let kept = steer(b, finalTotal: finalTotal)
        loadPool(kept: kept)
        let poolTotal = max(0, finalTotal - kept)
        var selling = 0.0
        var buying = 0.0
        for c in 0..<classCount {
            let target = classShares[c] * poolTotal
            classSales[c] = max(0, classPool[c] - target)
            classPurchases[c] = max(0, target - classPool[c])
            selling += classSales[c]
            buying += classPurchases[c]
        }
        return (selling, buying)
    }

    /// Brings a tax-advantaged bucket back to its target mix, without tax:
    /// within a class, lots keep their weights.
    private mutating func rebalanceWithoutTax(_ b: Int) {
        let bucketValue = loadClassValues(b)
        guard bucketValue > Self.epsilon else { return }
        let row = b * classCount
        for c in 0..<classCount {
            let current = classValues[c]
            let target = targetShares[row + c] * bucketValue
            if current > Self.epsilon {
                let ratio = target / current
                for l in bucketStart[b]..<bucketEnd[b] where lotClass[l] == c {
                    values[l] *= ratio
                    bases[l] = lotIsCash[l] ? values[l] : bases[l] * ratio
                }
            } else if target > Self.epsilon {
                buy(target, into: depositLot[row + c])
            }
        }
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
