import TaxKit

/// A prepared German tax year. Work, pensions and windfalls are assessed;
/// each simulated path adds stage 8 (investment income, gains and the
/// Vorabpauschale, at the flat rate or, when lower, the tariff), stage 9
/// (wrapper payouts) and stage 10 (health contributions on both, for a
/// voluntary member), and reruns stage 6 on the new total.
struct GermanPreparedYear: PreparedTaxYear {
    /// The part of the year outside a job in statutory insurance, which
    /// `assess` charges again with what the markets add.
    struct HealthPart: Hashable, Sendable {
        var status: HealthStatus
        /// The share of the year it covers.
        var share: Double
        /// What prepare charges, without German occupational pensions.
        var items: [HealthItem]
        var occupationalAnnuity: Double
        var occupationalLumpSum: Double
        var minimum: Double
        var ceiling: Double
        /// A voluntary member's rate on income other than pensions.
        var otherRate: Double
        var careRate: Double
        /// 0.96 when the contribution includes sick pay, else 1.
        var deductibleHealthFactor: Double
        var rates: HealthRates
        /// The charge without market activity.
        var fixed: HealthCharge

        /// The charge with `extraItems` and occupational payouts on top.
        func charge(extraItems: [HealthItem], occupationalPayouts: Double, p: GermanParameters) -> HealthCharge {
            var all = items + extraItems
            if let item = occupationalHealthItem(annuity: occupationalAnnuity + occupationalPayouts,
                                                 lumpSum: occupationalLumpSum, status: status, rates: rates, p: p) {
                all.append(item)
            }
            return HealthCharge.charge(all, minimum: minimum, ceiling: ceiling, minimumRate: otherRate,
                                       careRate: careRate)
        }
    }

    /// What the market-dependent stages need from the fixed ones. A class, so
    /// each path's assessment shares it.
    final class Context: Sendable {
        let year: Int
        let age: Int
        /// Euros per unit of the plan's currency.
        let rate: Double
        let p: GermanParameters
        let calculator: IncomeTaxCalculator
        let inputs: TariffInputs
        let retirementProvisions: Double
        let basicProvisions: Double
        let otherProvisions: Double
        let otherProvisionsLimit: Double
        let health: HealthPart?
        let pensionLumpSumLeft: Double
        /// The cohort share of a Rürup payout drawn this year.
        let ruerupShare: Double
        let basiszins: Double
        /// The flat income-tax rate on capital income (lower with church tax).
        let flatRate: Double
        let churchRate: Double
        /// Whether a sale's tax doesn't depend on anything else: no
        /// Günstigerprüfung possible, no health contributions on gains.
        let exactGrossUp: Bool
        let labels: GermanLabels
        /// Lines after the income-tax lines: trade tax, inheritance tax.
        let otherLines: [TaxLine]
        let contributions: [TaxLine]
        let accruals: [Accrual]
        let issues: [TaxIssue]
        let nextState: TaxState

        init(year: Int, age: Int, rate: Double, parameters: GermanParameters, calculator: IncomeTaxCalculator,
             inputs: TariffInputs, retirementProvisions: Double, basicProvisions: Double, otherProvisions: Double,
             otherProvisionsLimit: Double, health: HealthPart?, pensionLumpSumLeft: Double, ruerupShare: Double,
             basiszins: Double, flatRate: Double, churchRate: Double, exactGrossUp: Bool, otherLines: [TaxLine],
             contributions: [TaxLine], accruals: [Accrual], issues: [TaxIssue], nextState: TaxState) {
            self.year = year
            self.age = age
            self.rate = rate
            self.p = parameters
            self.calculator = calculator
            self.inputs = inputs
            self.retirementProvisions = retirementProvisions
            self.basicProvisions = basicProvisions
            self.otherProvisions = otherProvisions
            self.otherProvisionsLimit = otherProvisionsLimit
            self.health = health
            self.pensionLumpSumLeft = pensionLumpSumLeft
            self.ruerupShare = ruerupShare
            self.basiszins = basiszins
            self.flatRate = flatRate
            self.churchRate = churchRate
            self.exactGrossUp = exactGrossUp
            self.labels = GermanLabels(flatRate: flatRate, churchRate: churchRate)
            self.otherLines = otherLines
            self.contributions = contributions
            self.accruals = accruals
            self.issues = issues
            self.nextState = nextState
        }

        /// The flat tax with its Soli and church tax, per euro of taxable capital income.
        var combinedFlatRate: Double {
            flatRate * (1 + p.soli.capitalIncomeRate + churchRate)
        }
    }

    let fixedAssessment: TaxAssessment
    let context: Context?

    init(context: Context) {
        self.context = context
        var assessor = GermanMarketAssessor(context: context)
        fixedAssessment = assessor.assess(.empty)
    }

    /// A year that couldn't be prepared; `fixed` carries the error.
    init(failed fixed: TaxAssessment) {
        fixedAssessment = fixed
        context = nil
    }

    func assess(_ variable: VariableYear) -> TaxAssessment {
        guard let context else { return fixedAssessment }
        if variable.sales.isEmpty && variable.payouts.isEmpty && variable.capitalIncome.isEmpty
            && variable.balances.isEmpty {
            return fixedAssessment
        }
        var assessor = GermanMarketAssessor(context: context)
        return assessor.assess(variable)
    }

    /// Exact for an ordinary account when the sale's tax is the flat tax
    /// alone: `net` plus the tax on the taxable gain above the €1,000
    /// allowance (assumed unused). `nil`, so the engine solves it, when the
    /// tariff may be lower (Günstigerprüfung), when a voluntary member pays
    /// health contributions on the gain, and for payouts taxed at the tariff.
    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double? {
        guard let context else { return nil }
        let net = max(0, net)
        switch GermanWrapperTreatment(bucket.wrapper) {
        case .taxFree:
            return net
        case .taxable:
            guard context.exactGrossUp else { return nil }
            var total = 0.0
            var taxable = 0.0
            for (category, share) in bucket.categoryShares.sorted(by: { $0.key < $1.key }) {
                total += max(0, share)
                taxable += max(0, share) * GermanMarketAssessor.taxableGainShare(category, p: context.p)
            }
            let gain = (total > 0 ? taxable / total : 1) * bucket.gainShare
            let allowance = context.p.saverAllowance / context.rate
            let rate = context.combinedFlatRate
            guard gain > 0, net > allowance / gain else { return net }
            guard rate * gain < 1 else { return nil }
            return (net - rate * allowance) / (1 - rate * gain)
        default:
            return nil
        }
    }
}

/// How the German system treats a wrapper ID.
enum GermanWrapperTreatment: Hashable, Sendable {
    /// Taxed on income and gains: `de.ordinary`, the generic `taxable`, and
    /// the ordinary accounts of other systems.
    case taxable
    case riester, ruerup, bav, depot
    /// A foreign pension saving taxed on its gain: an Italian pension fund, a Swiss pillar 3a.
    case foreignSaving
    /// A Swiss vested-benefits account: like a BVG lump sum.
    case vestedBenefits
    /// The Italian TFR: taxed in Italy, counted for the progression clause.
    case tfr
    case taxDeferred, taxFree, unknown

    init(_ wrapper: String) {
        switch wrapper {
        case GermanWrapper.ordinary, "taxable", "it.ordinary", "ch.ordinary": self = .taxable
        case GermanWrapper.riester: self = .riester
        case GermanWrapper.ruerup: self = .ruerup
        case GermanWrapper.bav: self = .bav
        case GermanWrapper.altersvorsorgedepot: self = .depot
        case "it.pensionFund", "ch.pillar3a": self = .foreignSaving
        case "ch.vestedBenefits": self = .vestedBenefits
        case "it.tfr": self = .tfr
        case "taxDeferred": self = .taxDeferred
        case "taxFree": self = .taxFree
        default: self = .unknown
        }
    }
}

/// The labels of the lines, made once per prepared year.
struct GermanLabels: Hashable, Sendable {
    let incomeTax = "Income tax"
    let soli = "Solidarity surcharge"
    let churchTax: String
    let capitalIncomeTax: String
    let capitalIncomeSoli = "Solidarity surcharge on the flat tax"
    let capitalIncomeChurchTax = "Church tax on the flat tax"
    let healthOnMarket = "Health insurance on investment income and payouts"
    let careOnMarket = "Care insurance on investment income and payouts"

    init(flatRate: Double, churchRate: Double) {
        churchTax = "Church tax (\(percent(churchRate)))"
        capitalIncomeTax = "Flat tax on investment income (\(percent(flatRate)))"
    }
}

/// Stages 8–10 and stage 6 again, for one path.
struct GermanMarketAssessor {
    let context: GermanPreparedYear.Context
    private var issues: [TaxIssue] = []
    private var unknownWrappers: Set<String> = []
    private var foreignWrappers: Set<String> = []
    private var deferredPayouts = false

    // In euros.
    /// Share gains and losses, which offset only each other.
    private var stockGains = 0.0
    /// Other capital income after the partial exemption, losses included.
    private var otherCapital = 0.0
    /// Payouts taxed in full as pensions (§22 Nr. 5) or at a cohort share.
    private var pensionPayouts = 0.0
    /// Other income at the tariff (the gain of foreign pension savings).
    private var otherTariffIncome = 0.0
    private var progression = 0.0
    /// Payouts a voluntary member pays health contributions on, at the other rate.
    private var voluntaryPayouts = 0.0
    /// German occupational-pension payouts (Versorgungsbezüge).
    private var occupationalPayouts = 0.0
    private var basisAdjustments: [String: (wrapper: String, category: TaxCategory, amount: Double)] = [:]

    init(context: GermanPreparedYear.Context) {
        self.context = context
    }

    private var p: GermanParameters { context.p }

    /// The share of a gain in `category` that's taxed: none for cash and
    /// for private sales held long enough (gold, crypto, property), the rest
    /// after the partial exemption.
    static func taxableGainShare(_ category: TaxCategory, p: GermanParameters) -> Double {
        if category == .cash || p.privateSaleCategories.contains(category) { return 0 }
        return 1 - p.partialExemption(category)
    }

    mutating func assess(_ variable: VariableYear) -> TaxAssessment {
        let rate = context.rate
        for sale in variable.sales where sale.proceeds > 0 {
            switch treatment(of: sale.wrapper) {
            case .taxable, .unknown:
                gain(sale.category, proceeds: sale.proceeds * rate, cost: sale.costBasis.map { $0 * rate })
            case .taxFree:
                break
            case let other:
                payout(other, wrapper: sale.wrapper, amount: sale.proceeds * rate,
                       costBasis: sale.costBasis.map { $0 * rate }, membershipYears: nil)
            }
        }
        for payout in variable.payouts where payout.amount > 0 {
            let kind = treatment(of: payout.wrapper)
            guard kind != .taxable && kind != .taxFree else { continue }
            self.payout(kind, wrapper: payout.wrapper, amount: payout.amount * rate,
                        costBasis: payout.costBasis.map { $0 * rate }, membershipYears: payout.membershipYears)
        }
        for income in variable.capitalIncome where income.amount > 0 {
            let kind = treatment(of: income.wrapper)
            guard kind == .taxable || kind == .unknown else { continue }
            capitalIncome(income, amount: income.amount * rate)
        }
        let fraction = min(1, max(0, variable.fractionOfYear))
        for balance in variable.balances where balance.value > 0 && GermanParameters.isFund(balance.category) {
            let kind = treatment(of: balance.wrapper)
            guard kind == .taxable || kind == .unknown else { continue }
            vorabpauschale(balance, fraction: fraction)
        }
        return assessment()
    }

    private mutating func treatment(of wrapper: String) -> GermanWrapperTreatment {
        let kind = GermanWrapperTreatment(wrapper)
        if kind == .unknown { unknownWrappers.insert(wrapper) }
        return kind
    }

    /// Stage 8: a sale's gain at average cost. Without a documented cost,
    /// 30% of the proceeds stands in for it (the substitute base).
    private mutating func gain(_ category: TaxCategory, proceeds: Double, cost: Double?) {
        guard category != .cash, !p.privateSaleCategories.contains(category) else { return }
        let gain = proceeds - (cost ?? proceeds * (1 - p.undocumentedGainShare))
        if category == .stock {
            stockGains += gain
        } else {
            otherCapital += gain * (1 - p.partialExemption(category))
        }
    }

    /// Interest, dividends and coupons; a fund's distributions after the
    /// partial exemption. Income a fund keeps (`reportedIncome`) is covered
    /// by the Vorabpauschale; a share's or bond's reinvested dividends and
    /// coupons are taxed, and raise the holding's purchase cost.
    private mutating func capitalIncome(_ income: VariableYear.CapitalIncome, amount: Double) {
        let category = income.category
        guard !p.privateSaleCategories.contains(category) else { return }
        let fund = GermanParameters.isFund(category)
        if income.kind == .reportedIncome {
            guard !fund, category != .cash else { return }
            otherCapital += amount
            adjustBasis(income.wrapper, category, amount)
        } else {
            otherCapital += amount * (fund ? 1 - p.partialExemption(category) : 1)
        }
    }

    /// The Vorabpauschale: the start value × the base rate × 70%, at most the
    /// year's rise, for the share of the year simulated; taxed after the
    /// partial exemption, and added in full to the purchase cost.
    private mutating func vorabpauschale(_ balance: VariableYear.Balance, fraction: Double) {
        guard let start = balance.startValue ?? balance.nominalReturn.map({ balance.value / (1 + $0) }), start > 0
        else { return }
        let base = start * context.basiszins * p.basisShare * fraction
        let rise = balance.nominalReturn.map { start * $0 } ?? base
        let amount = max(0, min(base, rise)) * context.rate
        guard amount > 0 else { return }
        otherCapital += amount * (1 - p.partialExemption(balance.category))
        adjustBasis(balance.wrapper, balance.category, amount)
    }

    private mutating func adjustBasis(_ wrapper: String, _ category: TaxCategory, _ amount: Double) {
        let key = wrapper + "\u{1F}" + category.rawValue
        basisAdjustments[key, default: (wrapper, category, 0)].amount += amount
    }

    /// Stage 9: payouts from pension wrappers.
    private mutating func payout(_ kind: GermanWrapperTreatment, wrapper: String, amount: Double, costBasis: Double?,
                                 membershipYears: Int?) {
        switch kind {
        case .riester, .depot:
            pensionPayouts += amount
            voluntaryPayouts += amount
        case .bav:
            pensionPayouts += amount
            occupationalPayouts += amount
        case .ruerup:
            pensionPayouts += amount * context.ruerupShare
            voluntaryPayouts += amount
        case .foreignSaving:
            foreignWrappers.insert(wrapper)
            let gain = max(0, amount - min(amount, costBasis ?? 0))
            let half = (membershipYears ?? 0) >= p.foreignHalfGainAfterYears && context.age >= p.foreignHalfGainFromAge
            otherTariffIncome += half ? gain / 2 : gain
            voluntaryPayouts += amount
        case .vestedBenefits:
            foreignWrappers.insert(wrapper)
            pensionPayouts += amount * context.ruerupShare
            voluntaryPayouts += amount
        case .tfr:
            progression += amount / max(1, p.oneFifthDivisor)
        case .taxDeferred, .unknown:
            deferredPayouts = true
            pensionPayouts += amount
            voluntaryPayouts += amount
        case .taxable, .taxFree:
            break
        }
    }

    /// Stages 10 and 6, and the assessment.
    private mutating func assessment() -> TaxAssessment {
        let rate = context.rate
        let capital = max(0, max(0, stockGains) + otherCapital)

        // Stage 10: health contributions on what the markets added.
        var healthDelta = HealthCharge()
        if let part = context.health {
            var extra: [HealthItem] = []
            if part.status == .voluntary {
                if capital > 0 {
                    extra.append(HealthItem(kind: .capital, healthBase: capital * part.share,
                                            careBase: capital * part.share, rate: part.otherRate))
                }
                if voluntaryPayouts > 0 {
                    extra.append(HealthItem(kind: .other, healthBase: voluntaryPayouts, careBase: voluntaryPayouts,
                                            rate: part.otherRate))
                }
            }
            if !extra.isEmpty || occupationalPayouts > 0 {
                healthDelta = part.charge(extraItems: extra, occupationalPayouts: occupationalPayouts, p: p) - part.fixed
            }
        }

        // Stage 6 again, with payouts at the tariff and the extra contributions deducted.
        var inputs = context.inputs
        if let part = context.health, healthDelta != HealthCharge() {
            let basic = context.basicProvisions + healthDelta.deductibleHealth * part.deductibleHealthFactor
                + healthDelta.deductibleCare
            inputs.provisions = context.retirementProvisions
                + max(basic, min(basic + context.otherProvisions, context.otherProvisionsLimit))
        }
        let lumpSum = min(context.pensionLumpSumLeft, max(0, pensionPayouts))
        let tariffIncome = pensionPayouts - lumpSum + otherTariffIncome
        inputs.income += tariffIncome
        inputs.positiveIncome += max(0, tariffIncome)
        inputs.progression += progression
        var result = context.calculator.compute(inputs)

        // Stage 8: the flat tax, or the tariff when that gives less income tax
        // including the Soli and church tax (§32d Abs. 6).
        let taxable = max(0, capital - p.saverAllowance)
        var flatTax = context.flatRate * taxable
        if taxable > 0 {
            var alternative = inputs
            alternative.income += taxable
            alternative.positiveIncome += taxable
            let tariff = context.calculator.compute(alternative)
            if tariff.total < result.total + context.combinedFlatRate * taxable - 1e-9 {
                result = tariff
                flatTax = 0
            }
        }

        let labels = context.labels
        var lines: [TaxLine] = []
        func add(_ id: String, _ label: String, _ amount: Double, base: Double? = nil, subject: String? = nil) {
            guard abs(amount) > 1e-9 else { return }
            lines.append(TaxLine(id: id, label: label, amount: amount / rate, base: base.map { $0 / rate },
                                 subject: subject))
        }
        add(GermanLine.incomeTax, labels.incomeTax, result.incomeTax, base: result.taxableIncome)
        add(GermanLine.soli, labels.soli, result.soli, base: result.incomeTax)
        add(GermanLine.churchTax, labels.churchTax, result.churchTax)
        lines += context.otherLines
        if flatTax > 0 {
            add(GermanLine.capitalIncomeTax, labels.capitalIncomeTax, flatTax, base: taxable)
            add(GermanLine.capitalIncomeSoli, labels.capitalIncomeSoli, flatTax * p.soli.capitalIncomeRate, base: flatTax)
            add(GermanLine.capitalIncomeChurchTax, labels.capitalIncomeChurchTax, flatTax * context.churchRate,
                base: flatTax)
        }

        var contributions = context.contributions
        if abs(healthDelta.health) > 1e-9 {
            contributions.append(TaxLine(id: GermanLine.health, label: labels.healthOnMarket,
                                         amount: healthDelta.health / rate))
        }
        if abs(healthDelta.care) > 1e-9 {
            contributions.append(TaxLine(id: GermanLine.care, label: labels.careOnMarket, amount: healthDelta.care / rate))
        }

        var issues = context.issues
        for wrapper in unknownWrappers.sorted() {
            issues.append(.warning("de.unknownWrapper", "Germany doesn't know the wrapper \"\(wrapper)\": it's taxed as "
                                   + "an ordinary account, and its payouts as income.", year: context.year))
        }
        for wrapper in foreignWrappers.sorted() {
            issues.append(.warning("de.foreignWrapper", "How Germany taxes payouts from \(wrapper) isn't settled: the "
                                   + "module taxes them as docs/tax/DE.md describes, an assumption.", year: context.year))
        }
        if deferredPayouts {
            issues.append(.warning("de.taxDeferredPayout", "Payouts from a tax-deferred account are taxed in full at "
                                   + "the tariff, an approximation.", year: context.year))
        }
        let adjustments = basisAdjustments.values.sorted { ($0.wrapper, $0.category) < ($1.wrapper, $1.category) }
            .map { CostBasisAdjustment(wrapper: $0.wrapper, category: $0.category, amount: $0.amount / rate) }
        return TaxAssessment(lines: lines, contributions: contributions, accruals: context.accruals, issues: issues,
                             nextState: context.nextState, costBasisAdjustments: adjustments)
    }
}
