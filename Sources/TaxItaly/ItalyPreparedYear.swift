import TaxKit

/// A prepared Italian tax year. Work, pensions and windfalls are assessed;
/// each simulated path adds stage 8 (investment income and gains), stage 9
/// (wealth taxes) and the wrapper payouts, all taxed separately from IRPEF.
/// That makes the gross-up exact.
struct ItalyPreparedYear: PreparedTaxYear {
    /// What the market-dependent stages need from the fixed ones.
    struct Context: Sendable {
        var year: Int
        var age: Int
        /// Scaled into today's euros.
        var parameters: ItalyParameters
        /// IRPEF plus addizionali on the next euro of income, for payouts of
        /// foreign tax-deferred wrappers.
        var marginalIncomeRate: Double
        /// The share of pension-fund contributions taxed at payout: deducted
        /// contributions and TFR, as opposed to contributions that weren't deducted.
        var fundTaxedContributionShare: Double
        /// Plan years with pension-fund contributions, used when the planner
        /// doesn't pass membership years.
        var fundMembershipYears: Int
        /// The TFR's separate-taxation rate.
        var tfrRate: Double
    }

    let fixedAssessment: TaxAssessment
    let context: Context?

    init(fixed: TaxAssessment, context: Context) {
        self.fixedAssessment = fixed
        self.context = context
    }

    /// A year that couldn't be prepared; `fixed` carries the error.
    init(failed fixed: TaxAssessment) {
        self.fixedAssessment = fixed
        self.context = nil
    }

    func assess(_ variable: VariableYear) -> TaxAssessment {
        guard let context else { return fixedAssessment }
        var assessor = ItalyMarketAssessor(context: context, assessment: fixedAssessment)
        assessor.assess(variable)
        return assessor.assessment
    }

    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double? {
        guard let context else { return nil }
        let p = context.parameters
        let net = max(0, net)
        let costShare = bucket.value > 0 ? min(1, max(0, bucket.costBasis / bucket.value)) : 1
        let rate: Double
        switch WrapperTreatment(bucket.wrapper) {
        case .ordinary, .unknown:
            let total = bucket.categoryShares.values.reduce(0) { $0 + max(0, $1) }
            let blended = total > 0
                ? bucket.categoryShares.reduce(0) { $0 + max(0, $1.value) * p.investments.gainRate(for: $1.key) } / total
                : p.investments.standardRate
            rate = blended * bucket.gainShare
        case .pensionFund:
            let years = bucket.membershipYears ?? context.fundMembershipYears
            rate = p.pensionFund.payoutTaxRate(membershipYears: years) * costShare * context.fundTaxedContributionShare
        case .tfr:
            rate = context.tfrRate * costShare
        case .taxDeferred:
            rate = context.marginalIncomeRate
        case .taxFree:
            rate = 0
        }
        guard rate < 1 else { return nil }
        return net / (1 - rate)
    }
}

/// How the Italian system treats a wrapper ID.
enum WrapperTreatment: Hashable, Sendable {
    case ordinary, pensionFund, tfr, taxDeferred, taxFree, unknown

    init(_ wrapper: String) {
        switch wrapper {
        case ItalyWrapper.ordinary, "taxable": self = .ordinary
        case ItalyWrapper.pensionFund: self = .pensionFund
        case ItalyWrapper.tfr: self = .tfr
        case "taxDeferred": self = .taxDeferred
        case "taxFree": self = .taxFree
        default: self = .unknown
        }
    }
}

/// Stages 8 and 9 and the wrapper payouts for one path.
struct ItalyMarketAssessor {
    let context: ItalyPreparedYear.Context
    var assessment: TaxAssessment
    private var unknownWrappers: Set<String> = []
    private var foreignDeferred = false

    init(context: ItalyPreparedYear.Context, assessment: TaxAssessment) {
        self.context = context
        self.assessment = assessment
    }

    private var p: ItalyParameters { context.parameters }

    mutating func assess(_ variable: VariableYear) {
        for sale in variable.sales {
            switch treatment(of: sale.wrapper) {
            case .ordinary, .unknown:
                taxGain(sale)
            case .pensionFund:
                taxFundPayout(amount: sale.proceeds, costBasis: sale.costBasis, membershipYears: nil,
                              wrapper: sale.wrapper)
            case .tfr:
                taxTFRPayout(amount: sale.proceeds, costBasis: sale.costBasis, wrapper: sale.wrapper)
            case .taxDeferred:
                taxForeignPayout(amount: sale.proceeds, wrapper: sale.wrapper)
            case .taxFree:
                break
            }
        }
        for payout in variable.payouts {
            switch treatment(of: payout.wrapper) {
            case .pensionFund:
                taxFundPayout(amount: payout.amount, costBasis: payout.costBasis,
                              membershipYears: payout.membershipYears, wrapper: payout.wrapper)
            case .tfr:
                taxTFRPayout(amount: payout.amount, costBasis: payout.costBasis, wrapper: payout.wrapper)
            case .taxDeferred, .unknown:
                taxForeignPayout(amount: payout.amount, wrapper: payout.wrapper)
            case .ordinary, .taxFree:
                break
            }
        }
        checkLumpSums(variable)
        for income in variable.capitalIncome where income.amount > 0 {
            switch treatment(of: income.wrapper) {
            case .ordinary, .unknown:
                let rate = p.investments.rate(for: income.category)
                add("it.capitalIncome", "Tax on interest and dividends (\(percent(rate)))", rate * income.amount,
                    base: income.amount, subject: income.wrapper)
            default:
                break
            }
        }
        for balance in variable.balances where balance.value > 0 {
            switch treatment(of: balance.wrapper) {
            case .ordinary, .unknown:
                taxWealth(balance)
            default:
                break
            }
        }
        for wrapper in unknownWrappers.sorted() {
            assessment.issues.append(.warning(
                "it.unknownWrapper",
                "Italy doesn't know the wrapper \"\(wrapper)\": it is taxed as an ordinary account, and its payouts "
                    + "as income.", year: context.year))
        }
        if foreignDeferred {
            assessment.issues.append(.warning(
                "it.taxDeferredPayout",
                "Payouts from a tax-deferred account are taxed at your marginal IRPEF rate, an approximation.",
                year: context.year))
        }
    }

    private mutating func treatment(of wrapper: String) -> WrapperTreatment {
        let treatment = WrapperTreatment(wrapper)
        if treatment == .unknown { unknownWrappers.insert(wrapper) }
        return treatment
    }

    /// Adds to the line with the same ID, label and subject, or appends one.
    private mutating func add(_ id: String, _ label: String, _ amount: Double, base: Double, subject: String) {
        guard amount > 1e-9 else { return }
        if let index = assessment.lines.firstIndex(where: { $0.id == id && $0.label == label && $0.subject == subject }) {
            assessment.lines[index].amount += amount
            assessment.lines[index].base = (assessment.lines[index].base ?? 0) + base
        } else {
            assessment.lines.append(TaxLine(id: id, label: label, amount: amount, base: base, subject: subject))
        }
    }

    /// Stage 8: rate × realised gain at average cost. Losses aren't offset.
    /// Without a documented cost, physical gold is taxed on the whole price
    /// (the parameter's share of it), and anything else as if it cost nothing.
    private mutating func taxGain(_ sale: VariableYear.Sale) {
        let gain: Double
        if let cost = sale.costBasis {
            gain = max(0, sale.proceeds - cost)
        } else if sale.category == .physicalGold {
            gain = max(0, sale.proceeds * p.investments.goldUndocumentedGainShare)
        } else {
            gain = max(0, sale.proceeds)
        }
        let rate = p.investments.gainRate(for: sale.category)
        add("it.capitalGains", "Tax on gains: \(sale.category.rawValue) (\(percent(rate)))", rate * gain, base: gain,
            subject: sale.wrapper)
    }

    /// Pension-fund payouts: the payout rate on the contributions that were
    /// deducted (and TFR); growth was taxed inside the fund.
    private mutating func taxFundPayout(amount: Double, costBasis: Double?, membershipYears: Int?, wrapper: String) {
        guard amount > 0 else { return }
        let contributions = costBasis.map { min(amount, max(0, $0)) } ?? amount
        let taxable = contributions * context.fundTaxedContributionShare
        let rate = p.pensionFund.payoutTaxRate(membershipYears: membershipYears ?? context.fundMembershipYears)
        add("it.pensionFund.payoutTax", "Tax on pension-fund payouts (\(percent(rate)))", rate * taxable, base: taxable,
            subject: wrapper)
    }

    /// TFR: separate taxation at the average-rate approximation, on the
    /// accrued amount (the revaluation was taxed every year).
    private mutating func taxTFRPayout(amount: Double, costBasis: Double?, wrapper: String) {
        guard amount > 0 else { return }
        let taxable = costBasis.map { min(amount, max(0, $0)) } ?? amount
        add("it.tfr.payoutTax", "TFR separate taxation (\(percent(context.tfrRate)))", context.tfrRate * taxable,
            base: taxable, subject: wrapper)
    }

    private mutating func taxForeignPayout(amount: Double, wrapper: String) {
        guard amount > 0 else { return }
        foreignDeferred = true
        add("it.taxDeferredPayout", "IRPEF on tax-deferred payouts", context.marginalIncomeRate * amount, base: amount,
            subject: wrapper)
    }

    /// Up to half the pension fund can be taken as a lump sum, unless the
    /// annuity from 70% of it would be under half the assegno sociale. The
    /// annuity is estimated with the INPS conversion coefficient for the age.
    private mutating func checkLumpSums(_ variable: VariableYear) {
        let lumpSums = variable.payouts.filter { $0.wrapper == ItalyWrapper.pensionFund && $0.form == .lumpSum }
            .reduce(0) { $0 + $1.amount }
        let balances = variable.balances.filter { $0.wrapper == ItalyWrapper.pensionFund }
        guard lumpSums > 0, !balances.isEmpty else { return }
        let paidOut = variable.payouts.filter { $0.wrapper == ItalyWrapper.pensionFund }.reduce(0) { $0 + $1.amount }
        let before = balances.reduce(0) { $0 + $1.value } + paidOut
        let rules = p.pensionFund
        guard lumpSums > rules.lumpSumMaxShare * before + 0.01 else { return }
        let annuity = rules.lumpSumAnnuityShare * before * p.pension.coefficient(ageInMonths: context.age * 12)
        let smallAnnuityLimit = rules.smallAnnuityAssegnoSocialeShare * p.pension.assegnoSociale * p.pension.instalments
        guard annuity >= smallAnnuityLimit else { return }
        assessment.issues.append(.warning(
            "it.pensionFund.lumpSumLimit",
            "At most \(percent(rules.lumpSumMaxShare)) of the pension fund can be taken as a lump sum; the rest is paid "
                + "as an annuity.", year: context.year))
    }

    /// Stage 9: wealth taxes on year-end values of ordinary accounts.
    private mutating func taxWealth(_ balance: VariableYear.Balance) {
        let wealth = p.wealthTax
        switch balance.category {
        case .cash:
            if balance.value > wealth.currentAccountThreshold {
                add("it.wealthTax.currentAccount", "Imposta di bollo on current accounts", wealth.currentAccountAmount,
                    base: balance.value, subject: balance.wrapper)
            }
        case .crypto, .stablecoin:
            add("it.wealthTax.crypto", "Tax on the value of crypto (\(percent(wealth.cryptoRate)))",
                wealth.cryptoRate * balance.value, base: balance.value, subject: balance.wrapper)
        case .physicalGold:
            break
        case .realEstate:
            guard let country = balance.country?.uppercased(), country != "IT" else { break }
            let tax = wealth.propertyAbroadRate * balance.value
            if tax > wealth.propertyAbroadMinimum {
                add("it.ivie", "IVIE (property abroad)", tax, base: balance.value, subject: balance.wrapper)
            }
        default:
            let blacklisted = balance.country.map { wealth.blacklist.contains($0.uppercased()) } ?? false
            let rate = blacklisted ? wealth.blacklistRate : wealth.financialRate
            add("it.wealthTax.financial", "Imposta di bollo / IVAFE (\(percent(rate)))", rate * balance.value,
                base: balance.value, subject: balance.wrapper)
        }
    }
}
