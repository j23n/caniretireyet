import TaxKit

/// A prepared Italian tax year. Work, pensions and windfalls are assessed;
/// each simulated path adds stage 8 (investment income and gains), stage 9
/// (wealth taxes) and the wrapper payouts, all taxed separately from IRPEF.
/// That makes the gross-up exact.
struct ItalyPreparedYear: PreparedTaxYear {
    /// What the market-dependent stages need from the fixed ones. A class,
    /// so each path's assessment shares it instead of copying the parameters.
    final class Context: Sendable {
        let year: Int
        let age: Int
        /// Scaled into today's euros.
        let parameters: ItalyParameters
        /// IRPEF plus addizionali on the next euro of income, for payouts of
        /// foreign tax-deferred wrappers.
        let marginalIncomeRate: Double
        /// The share of pension-fund contributions taxed at payout: deducted
        /// contributions and TFR, as opposed to contributions that weren't deducted.
        let fundTaxedContributionShare: Double
        /// Plan years with pension-fund contributions, used when the planner
        /// doesn't pass membership years.
        let fundMembershipYears: Int
        /// The TFR's separate-taxation rate.
        let tfrRate: Double
        /// The lines' labels, which only depend on the year's rates.
        let labels: ItalyMarketLabels
        /// Euros per unit of the plan's currency. Taxes proportional to an
        /// amount don't depend on it; thresholds and fixed amounts in euros
        /// (the bollo on current accounts, IVIE's minimum, the pension
        /// fund's small-annuity test) do.
        let currencyRate: Double

        init(year: Int, age: Int, parameters: ItalyParameters, marginalIncomeRate: Double,
             fundTaxedContributionShare: Double, fundMembershipYears: Int, tfrRate: Double, currencyRate: Double = 1) {
            self.year = year
            self.age = age
            self.parameters = parameters
            self.marginalIncomeRate = marginalIncomeRate
            self.fundTaxedContributionShare = fundTaxedContributionShare
            self.fundMembershipYears = fundMembershipYears
            self.tfrRate = tfrRate
            self.currencyRate = currencyRate > 0 ? currencyRate : 1
            labels = ItalyMarketLabels(parameters, tfrRate: tfrRate)
        }
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
        let investments = context.parameters.investments
        let net = max(0, net)
        let costShare = bucket.value > 0 ? min(1, max(0, bucket.costBasis / bucket.value)) : 1
        let rate: Double
        switch WrapperTreatment(bucket.wrapper) {
        case .ordinary, .unknown:
            // Summed in the categories' order, so the result is the same in
            // every process (a dictionary's order depends on its hash seed).
            var total = 0.0
            var weighted = 0.0
            func add(_ category: TaxCategory, _ share: Double) {
                total += max(0, share)
                weighted += max(0, share) * investments.gainRate(for: ItalyMarketLabels.resolve(category))
            }
            if bucket.categoryShares.count > 1 {
                for (category, share) in bucket.categoryShares.sorted(by: { $0.key < $1.key }) { add(category, share) }
            } else {
                for (category, share) in bucket.categoryShares { add(category, share) }
            }
            let blended = total > 0 ? weighted / total : investments.standardRate
            rate = blended * bucket.gainShare
        case .pensionFund:
            let years = bucket.membershipYears ?? context.fundMembershipYears
            rate = context.parameters.pensionFund.payoutTaxRate(membershipYears: years) * costShare
                * context.fundTaxedContributionShare
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

/// The labels of the market-dependent lines, made once per prepared year
/// (they're used once per path and year, and only depend on the year's rates).
struct ItalyMarketLabels: Sendable {
    private var gains: [TaxCategory: String] = [:]
    private var capitalIncome: [TaxCategory: String] = [:]
    let financial: String
    let blacklisted: String
    let crypto: String
    let tfrPayout: String
    /// Pension-fund payout labels by rate: one per rate the membership
    /// years can give.
    private var fundPayouts: [(rate: Double, label: String)] = []
    let currentAccount = "Imposta di bollo on current accounts"
    let ivie = "IVIE (property abroad)"
    let taxDeferredPayout = "IRPEF on tax-deferred payouts"

    private static let categories: [TaxCategory] = [
        .fund, .stock, .bond, .governmentBond, .etc, .crypto, .stablecoin, .physicalGold, .cash, .realEstate, .other,
    ]
    private static let knownCategories = Set(categories)

    /// The category Italy taxes `category` as: itself, or the broader one
    /// Italy knows (every kind of fund is a `fund`, an ETC with a delivery
    /// claim an `etc`). Italy taxes all funds alike, so the planner's fund
    /// kinds change neither its rates nor its labels.
    static func resolve(_ category: TaxCategory) -> TaxCategory {
        guard category.broader != nil else { return category }
        return category.resolved(in: knownCategories) ?? category
    }

    init(_ p: ItalyParameters, tfrRate: Double) {
        for category in Self.categories {
            gains[category] = Self.gainLabel(category, rate: p.investments.gainRate(for: category))
            capitalIncome[category] = Self.capitalIncomeLabel(rate: p.investments.rate(for: category))
        }
        financial = Self.financialLabel(rate: p.wealthTax.financialRate)
        blacklisted = Self.financialLabel(rate: p.wealthTax.blacklistRate)
        crypto = "Tax on the value of crypto (\(percent(p.wealthTax.cryptoRate)))"
        tfrPayout = "TFR separate taxation (\(percent(tfrRate)))"
        let fund = p.pensionFund
        let lastStep = fund.payoutReductionPerYear > 0
            ? fund.payoutReductionAfterYears + Int(((fund.payoutRate - fund.payoutFloor) / fund.payoutReductionPerYear)
                .rounded(.up)) + 1
            : fund.payoutReductionAfterYears
        for years in 0...max(0, min(lastStep, 100)) {
            let rate = fund.payoutTaxRate(membershipYears: years)
            if !fundPayouts.contains(where: { $0.rate == rate }) {
                fundPayouts.append((rate, Self.fundPayoutLabel(rate: rate)))
            }
        }
    }

    func fundPayout(rate: Double) -> String {
        fundPayouts.first { $0.rate == rate }?.label ?? Self.fundPayoutLabel(rate: rate)
    }

    static func fundPayoutLabel(rate: Double) -> String {
        "Tax on pension-fund payouts (\(percent(rate)))"
    }

    func gain(_ category: TaxCategory, rate: Double) -> String {
        gains[category] ?? Self.gainLabel(category, rate: rate)
    }

    func capitalIncome(_ category: TaxCategory, rate: Double) -> String {
        capitalIncome[category] ?? Self.capitalIncomeLabel(rate: rate)
    }

    func financial(blacklisted: Bool) -> String {
        blacklisted ? self.blacklisted : financial
    }

    static func gainLabel(_ category: TaxCategory, rate: Double) -> String {
        "Tax on gains: \(category.rawValue) (\(percent(rate)))"
    }

    static func capitalIncomeLabel(rate: Double) -> String {
        "Tax on interest and dividends (\(percent(rate)))"
    }

    static func financialLabel(rate: Double) -> String {
        "Imposta di bollo / IVAFE (\(percent(rate)))"
    }
}

/// Stages 8 and 9 and the wrapper payouts for one path.
struct ItalyMarketAssessor {
    let context: ItalyPreparedYear.Context
    var assessment: TaxAssessment
    private var unknownWrappers: Set<String> = []
    private var foreignDeferred = false

    /// How many of `assessment`'s lines are the fixed year's.
    private let fixedLines: Int

    init(context: ItalyPreparedYear.Context, assessment: TaxAssessment) {
        self.context = context
        self.assessment = assessment
        fixedLines = assessment.lines.count
    }

    /// The parameters, read in place (never copied: they hold many arrays).
    private var p: ItalyParameters { _read { yield context.parameters } }

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
        if !variable.payouts.isEmpty { checkLumpSums(variable) }
        // Income a fund earned without paying it out isn't taxed until it's
        // paid or the fund is sold (accumulating funds).
        for income in variable.capitalIncome where income.amount > 0 && income.kind != .reportedIncome {
            switch treatment(of: income.wrapper) {
            case .ordinary, .unknown:
                let category = ItalyMarketLabels.resolve(income.category)
                let rate = context.parameters.investments.rate(for: category)
                add("it.capitalIncome", context.labels.capitalIncome(category, rate: rate), rate * income.amount,
                    base: income.amount, subject: income.wrapper)
            default:
                break
            }
        }
        for balance in variable.balances where balance.value > 0 {
            switch treatment(of: balance.wrapper) {
            case .ordinary, .unknown:
                taxWealth(balance, fraction: min(1, max(0, variable.fractionOfYear)))
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

    /// A country code in capitals, without making a new string when it already is.
    private static func uppercased(_ code: String) -> String {
        code.utf8.contains { $0 >= 97 && $0 <= 122 } ? code.uppercased() : code
    }

    private mutating func treatment(of wrapper: String) -> WrapperTreatment {
        let treatment = WrapperTreatment(wrapper)
        if treatment == .unknown { unknownWrappers.insert(wrapper) }
        return treatment
    }

    /// Adds to the line with the same ID, label and subject, or appends one.
    /// Market lines come after the fixed ones, so only those are searched.
    private mutating func add(_ id: String, _ label: String, _ amount: Double, base: Double, subject: String) {
        guard amount > 1e-9 else { return }
        var index = assessment.lines.count - 1
        while index >= fixedLines {
            if assessment.lines[index].id == id && assessment.lines[index].label == label
                && assessment.lines[index].subject == subject {
                assessment.lines[index].amount += amount
                assessment.lines[index].base = (assessment.lines[index].base ?? 0) + base
                return
            }
            index -= 1
        }
        if fixedLines > 0, let fixed = assessment.lines[..<fixedLines].firstIndex(where: {
            $0.id == id && $0.label == label && $0.subject == subject
        }) {
            assessment.lines[fixed].amount += amount
            assessment.lines[fixed].base = (assessment.lines[fixed].base ?? 0) + base
            return
        }
        if assessment.lines.count == fixedLines { assessment.lines.reserveCapacity(fixedLines + 8) }
        assessment.lines.append(TaxLine(id: id, label: label, amount: amount, base: base, subject: subject))
    }

    /// Stage 8: rate × realised gain at average cost. Losses aren't offset.
    /// Without a documented cost, physical gold is taxed on the whole price
    /// (the parameter's share of it), and anything else as if it cost nothing.
    private mutating func taxGain(_ sale: VariableYear.Sale) {
        let category = ItalyMarketLabels.resolve(sale.category)
        let gain: Double
        if let cost = sale.costBasis {
            gain = max(0, sale.proceeds - cost)
        } else if category == .physicalGold {
            gain = max(0, sale.proceeds * context.parameters.investments.goldUndocumentedGainShare)
        } else {
            gain = max(0, sale.proceeds)
        }
        let rate = context.parameters.investments.gainRate(for: category)
        add("it.capitalGains", context.labels.gain(category, rate: rate), rate * gain, base: gain,
            subject: sale.wrapper)
    }

    /// Pension-fund payouts: the payout rate on the contributions that were
    /// deducted (and TFR); growth was taxed inside the fund.
    private mutating func taxFundPayout(amount: Double, costBasis: Double?, membershipYears: Int?, wrapper: String) {
        guard amount > 0 else { return }
        let contributions = costBasis.map { min(amount, max(0, $0)) } ?? amount
        let taxable = contributions * context.fundTaxedContributionShare
        let rate = context.parameters.pensionFund.payoutTaxRate(membershipYears: membershipYears ?? context.fundMembershipYears)
        add("it.pensionFund.payoutTax", context.labels.fundPayout(rate: rate), rate * taxable, base: taxable,
            subject: wrapper)
    }

    /// TFR: separate taxation at the average-rate approximation, on the
    /// accrued amount (the revaluation was taxed every year).
    private mutating func taxTFRPayout(amount: Double, costBasis: Double?, wrapper: String) {
        guard amount > 0 else { return }
        let taxable = costBasis.map { min(amount, max(0, $0)) } ?? amount
        add("it.tfr.payoutTax", context.labels.tfrPayout, context.tfrRate * taxable, base: taxable, subject: wrapper)
    }

    private mutating func taxForeignPayout(amount: Double, wrapper: String) {
        guard amount > 0 else { return }
        foreignDeferred = true
        add("it.taxDeferredPayout", context.labels.taxDeferredPayout, context.marginalIncomeRate * amount, base: amount,
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
        // In euros, to compare with the assegno sociale.
        let before = (balances.reduce(0) { $0 + $1.value } + paidOut) * context.currencyRate
        let rules = p.pensionFund
        guard lumpSums * context.currencyRate > rules.lumpSumMaxShare * before + 0.01 else { return }
        let annuity = rules.lumpSumAnnuityShare * before * p.pension.coefficient(ageInMonths: context.age * 12)
        let smallAnnuityLimit = rules.smallAnnuityAssegnoSocialeShare * p.pension.assegnoSociale * p.pension.instalments
        guard annuity >= smallAnnuityLimit else { return }
        assessment.issues.append(.warning(
            "it.pensionFund.lumpSumLimit",
            "At most \(percent(rules.lumpSumMaxShare)) of the pension fund can be taken as a lump sum; the rest is paid "
                + "as an annuity.", year: context.year))
    }

    /// Stage 9: wealth taxes on year-end values of ordinary accounts. The
    /// thresholds are tested on the balance (in euros), and `fraction` of a
    /// year's tax is charged (less than a year in a plan's first year).
    private mutating func taxWealth(_ balance: VariableYear.Balance, fraction: Double) {
        // The parameters and labels are read in place: this runs for every
        // balance of every path, and copying them would cost more than the tax.
        let context = context
        let rate = context.currencyRate
        switch ItalyMarketLabels.resolve(balance.category) {
        case .cash:
            if balance.value * rate > context.parameters.wealthTax.currentAccountThreshold {
                add("it.wealthTax.currentAccount", context.labels.currentAccount,
                    context.parameters.wealthTax.currentAccountAmount / rate * fraction, base: balance.value,
                    subject: balance.wrapper)
            }
        case .crypto, .stablecoin:
            add("it.wealthTax.crypto", context.labels.crypto,
                context.parameters.wealthTax.cryptoRate * balance.value * fraction, base: balance.value,
                subject: balance.wrapper)
        case .physicalGold:
            break
        case .realEstate:
            guard let country = balance.country.map(Self.uppercased), country != "IT" else { break }
            let tax = context.parameters.wealthTax.propertyAbroadRate * balance.value
            if tax * rate > context.parameters.wealthTax.propertyAbroadMinimum {
                add("it.ivie", context.labels.ivie, tax * fraction, base: balance.value, subject: balance.wrapper)
            }
        default:
            let blacklisted = balance.country.map {
                !context.parameters.wealthTax.blacklist.isEmpty
                    && context.parameters.wealthTax.blacklist.contains(Self.uppercased($0))
            } ?? false
            let rate = blacklisted ? context.parameters.wealthTax.blacklistRate
                : context.parameters.wealthTax.financialRate
            add("it.wealthTax.financial", blacklisted ? context.labels.blacklisted : context.labels.financial,
                rate * balance.value * fraction, base: balance.value, subject: balance.wrapper)
        }
    }
}
