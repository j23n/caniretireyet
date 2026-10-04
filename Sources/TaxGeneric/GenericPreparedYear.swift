import TaxKit

/// A year prepared by the generic system: work and pension taxes are fixed;
/// sales, payouts, capital income and wealth are taxed per path at flat rates.
///
/// Gains and losses on sales net within the year, and a net loss is carried
/// forward along the path, without limit, against later years' gains (in
/// nominal terms, so it shrinks in today's money as prices rise). Capital
/// income is taxed apart and never offset.
struct GenericPreparedYear: PreparedTaxYear {
    let rates: GenericRates
    let fixedAssessment: TaxAssessment
    /// The year's prices against the plan's start (`FixedYear.inflationFactor`).
    let prices: Double

    init(year: FixedYear, state: TaxState, rates: GenericRates) {
        self.rates = rates
        prices = year.inflationFactor > 0 ? year.inflationFactor : 1
        var lines: [TaxLine] = []
        var contributions: [TaxLine] = []
        var deferred = year.wrapperContributions
            .filter { $0.wrapper == GenericWrapper.taxDeferred }
            .reduce(0) { $0 + max(0, $1.amount) }
        for work in year.work where work.kind != .net {
            let base = max(0, work.gross - work.costs)
            if rates.social > 0 && base > 0 {
                contributions.append(TaxLine(id: "generic.social", label: "Social contributions",
                                             amount: rates.social * base, base: base, subject: work.phaseID))
            }
            let relief = min(deferred, base)
            deferred -= relief
            let taxable = base - relief
            if rates.income > 0 && taxable > 0 {
                lines.append(TaxLine(id: "generic.incomeTax", label: "Income tax", amount: rates.income * taxable,
                                     base: taxable, subject: work.phaseID))
            }
        }
        for pension in year.pensions where pension.taxedIn == .residence && pension.amount > 0 && rates.pension > 0 {
            lines.append(TaxLine(id: "generic.pensionTax", label: "Tax on pensions",
                                 amount: rates.pension * pension.amount, base: pension.amount, subject: pension.id))
        }
        fixedAssessment = TaxAssessment(lines: lines, contributions: contributions, nextState: state)
    }

    func assess(_ variable: VariableYear) -> TaxAssessment {
        var assessment = fixedAssessment
        var unknownWrappers: Set<String> = []
        func kind(of wrapper: String) -> String {
            switch wrapper {
            case GenericWrapper.taxable, GenericWrapper.taxDeferred, GenericWrapper.taxFree: return wrapper
            default:
                unknownWrappers.insert(wrapper)
                return "unknown"
            }
        }
        // Gains and losses of the year net, then losses carried forward offset
        // what's left; each sale's gain is taxed on its share of the rest.
        var totals = GainTotals()
        totals.add(variable.sales)
        let carried = carriedLosses(in: variable.pathState)
        let offset = totals.offset(carried: carried)
        let taxedShare = totals.gains > 0 ? (totals.gains - offset) / totals.gains : 1
        for sale in variable.sales {
            switch kind(of: sale.wrapper) {
            case GenericWrapper.taxFree:
                continue
            case GenericWrapper.taxDeferred:
                add(&assessment, id: "generic.payoutTax", label: "Tax on tax-deferred payouts", rate: rates.pension,
                    base: sale.proceeds, subject: sale.wrapper)
            default:
                let gain = Self.gain(of: sale)
                guard gain > 0 else { continue }
                add(&assessment, id: "generic.capitalGainsTax", label: "Capital gains tax", rate: rates.capitalGains,
                    base: gain * taxedShare, subject: sale.wrapper)
            }
        }
        // Losses left: last year's unused, less what offset gains beyond this
        // year's losses, plus this year's losses beyond its gains.
        let left = carried - max(0, offset - totals.losses) + max(0, totals.losses - totals.gains)
        if abs(left - carried) > 1e-9 {
            var next = variable.pathState
            next[Self.lossKey] = left > 1e-9 ? left * prices : nil
            assessment.nextPathState = next
        }
        for payout in variable.payouts {
            switch kind(of: payout.wrapper) {
            case GenericWrapper.taxFree, GenericWrapper.taxable:
                continue
            default:
                add(&assessment, id: "generic.payoutTax", label: "Tax on tax-deferred payouts", rate: rates.pension,
                    base: payout.amount, subject: payout.wrapper)
            }
        }
        // Income a fund earned without paying it out is taxed only when it's
        // paid or sold, as the gain.
        for income in variable.capitalIncome where income.kind != .reportedIncome {
            let wrapper = kind(of: income.wrapper)
            guard wrapper == GenericWrapper.taxable || wrapper == "unknown" else { continue }
            add(&assessment, id: "generic.capitalIncomeTax", label: "Tax on interest and dividends",
                rate: rates.interestDividend, base: income.amount, subject: income.wrapper)
        }
        // A year's wealth tax, for the share of the year the balances are held.
        let fraction = min(1, max(0, variable.fractionOfYear))
        for balance in variable.balances {
            let wrapper = kind(of: balance.wrapper)
            guard wrapper == GenericWrapper.taxable || wrapper == "unknown" else { continue }
            add(&assessment, id: "generic.wealthTax", label: "Wealth tax", rate: rates.wealth,
                base: balance.value * fraction, subject: balance.wrapper)
        }
        for wrapper in unknownWrappers.sorted() {
            assessment.issues.append(.warning(
                "generic.unknownWrapper",
                "The generic system doesn't know the wrapper \"\(wrapper)\": it is taxed as a taxable account, "
                    + "and its payouts as tax-deferred ones."))
        }
        return assessment
    }

    private func add(_ assessment: inout TaxAssessment, id: String, label: String, rate: Double, base: Double,
                     subject: String) {
        guard rate != 0, base > 0 else { return }
        if let index = assessment.lines.firstIndex(where: { $0.id == id && $0.subject == subject }) {
            assessment.lines[index].amount += rate * base
            assessment.lines[index].base = (assessment.lines[index].base ?? 0) + base
        } else {
            assessment.lines.append(TaxLine(id: id, label: label, amount: rate * base, base: base, subject: subject))
        }
    }

    // MARK: Losses

    /// The path-state key of the losses carried forward, in nominal units
    /// of the plan's currency (today's money times the year's prices).
    static let lossKey = "generic.losses"

    /// A sale's gain, negative for a loss; without a documented cost, the
    /// whole price.
    static func gain(of sale: VariableYear.Sale) -> Double {
        sale.proceeds - (sale.costBasis ?? 0)
    }

    /// Whether the system taxes a sale from `wrapper` on its gain: every
    /// wrapper but `taxFree` and `taxDeferred` (whose sales are payouts).
    static func taxesGains(_ wrapper: String) -> Bool {
        wrapper != GenericWrapper.taxFree && wrapper != GenericWrapper.taxDeferred
    }

    /// The year's gains and losses on sales taxed on their gain.
    struct GainTotals {
        var gains = 0.0
        var losses = 0.0

        mutating func add(_ sales: [VariableYear.Sale]) {
            for sale in sales where GenericPreparedYear.taxesGains(sale.wrapper) {
                let gain = GenericPreparedYear.gain(of: sale)
                if gain > 0 { gains += gain } else { losses -= gain }
            }
        }

        /// How much of the gains losses offset: the year's own first, then
        /// `carried` ones.
        func offset(carried: Double) -> Double {
            min(gains, losses + max(0, carried))
        }

        /// The gains left to tax.
        func taxable(carried: Double) -> Double {
            gains - offset(carried: carried)
        }
    }

    /// The losses carried into this year, in today's money.
    private func carriedLosses(in state: TaxState) -> Double {
        guard !state.values.isEmpty, let nominal = state[Self.lossKey] else { return 0 }
        return max(0, nominal / prices)
    }

    /// The tax selling `sales` adds to `year`: gains tax on what the year's
    /// gains less its losses and those carried forward leave, which isn't
    /// linear in a sale once losses are offset; payout tax on sales from
    /// `taxDeferred`.
    func taxOnSales(_ sales: [VariableYear.Sale], alongside year: VariableYear) -> Double? {
        var before = GainTotals()
        before.add(year.sales)
        var after = before
        after.add(sales)
        let carried = carriedLosses(in: year.pathState)
        var tax = rates.capitalGains * (after.taxable(carried: carried) - before.taxable(carried: carried))
        for sale in sales where sale.wrapper == GenericWrapper.taxDeferred {
            tax += rates.pension * sale.proceeds
        }
        return tax
    }

    func carriedForward(in state: TaxState) -> [TaxLine] {
        let losses = carriedLosses(in: state)
        guard losses > 0.005 else { return [] }
        return [TaxLine(id: Self.lossKey, label: "Losses carried forward", amount: losses)]
    }

    /// Exact without losses: the tax on a sale is linear in the amount sold.
    /// With losses to offset the engine asks ``taxOnSales(_:alongside:)``.
    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double? {
        let rate: Double
        switch bucket.wrapper {
        case GenericWrapper.taxFree: rate = 0
        case GenericWrapper.taxDeferred: rate = rates.pension
        default: rate = rates.capitalGains * bucket.gainShare
        }
        guard rate < 1 else { return nil }
        return max(0, net) / (1 - rate)
    }
}
