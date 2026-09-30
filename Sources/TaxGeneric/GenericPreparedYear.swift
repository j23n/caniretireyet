import TaxKit

/// A year prepared by the generic system: work and pension taxes are fixed;
/// sales, payouts, capital income and wealth are taxed per path at flat rates.
struct GenericPreparedYear: PreparedTaxYear {
    let rates: GenericRates
    let fixedAssessment: TaxAssessment

    init(year: FixedYear, state: TaxState, rates: GenericRates) {
        self.rates = rates
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
        for sale in variable.sales {
            switch kind(of: sale.wrapper) {
            case GenericWrapper.taxFree:
                continue
            case GenericWrapper.taxDeferred:
                add(&assessment, id: "generic.payoutTax", label: "Tax on tax-deferred payouts", rate: rates.pension,
                    base: sale.proceeds, subject: sale.wrapper)
            default:
                let gain = max(0, sale.proceeds - (sale.costBasis ?? 0))
                add(&assessment, id: "generic.capitalGainsTax", label: "Capital gains tax", rate: rates.capitalGains,
                    base: gain, subject: sale.wrapper)
            }
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
        for income in variable.capitalIncome {
            let wrapper = kind(of: income.wrapper)
            guard wrapper == GenericWrapper.taxable || wrapper == "unknown" else { continue }
            add(&assessment, id: "generic.capitalIncomeTax", label: "Tax on interest and dividends",
                rate: rates.interestDividend, base: income.amount, subject: income.wrapper)
        }
        for balance in variable.balances {
            let wrapper = kind(of: balance.wrapper)
            guard wrapper == GenericWrapper.taxable || wrapper == "unknown" else { continue }
            add(&assessment, id: "generic.wealthTax", label: "Wealth tax", rate: rates.wealth, base: balance.value,
                subject: balance.wrapper)
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

    /// Exact: the tax on a sale is linear in the amount sold.
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
