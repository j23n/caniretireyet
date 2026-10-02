import TaxKit

/// A capital benefit of the year: a pension lump sum (by pension ID) or a
/// payout from a pension wrapper (by wrapper ID). In CHF.
struct SwissCapitalBenefit: Hashable, Sendable {
    var subject: String
    var amount: Double
}

/// A prepared Swiss tax year. Work, pensions, pension lump sums and the
/// overlays are assessed; each simulated path adds investment income (taxed
/// with the other income, at the marginal rate), wrapper payouts (added to
/// the year's capital benefits), the wealth tax with Ticino's brake, and AHV
/// contributions without work.
struct SwissPreparedYear: PreparedTaxYear {
    /// What the market-dependent stages need from the fixed ones. A class,
    /// so each path's assessment shares it instead of copying it.
    final class Context: Sendable {
        let year: Int
        /// Units of CHF per unit of the plan's currency.
        let rate: Double
        let tariffs: SwissTariffs
        let labels: SwissLabels
        /// The income before investment income; `nil` under lump-sum taxation.
        let base: SwissIncomeBase?
        /// The prepared income taxes; `nil` under lump-sum taxation.
        let incomeTaxes: SwissIncomeTaxes?
        let lumpSum: SwissLumpSumYear?
        /// The pension lump sums of the year.
        let capitalBenefits: [SwissCapitalBenefit]
        let preparedCapitalTotal: Double
        /// Buy-ins whose deduction a lump sum this year reverses, and
        /// whether prepare already did (for a BVG lump sum).
        let lockedBuyIns: Double
        let reversedInPrepare: Bool
        /// AHV/IV/EO paid on the year's earnings, both shares.
        let workAHV: Double
        /// All pensions paid as annuities, for AHV without work.
        let annuities: Double
        /// The home's tax value less the mortgage.
        let home: Double
        /// The share of the year AHV contributions without work are due for
        /// (0 outside the ages).
        let nonEmployedShare: Double
        let adminRate: Double
        let personalTax: Double
        let fixedContributions: [TaxLine]

        init(year: Int, rate: Double, tariffs: SwissTariffs, labels: SwissLabels, base: SwissIncomeBase?,
             incomeTaxes: SwissIncomeTaxes?, lumpSum: SwissLumpSumYear?, capitalBenefits: [SwissCapitalBenefit],
             lockedBuyIns: Double, reversedInPrepare: Bool, workAHV: Double, annuities: Double, home: Double,
             nonEmployedShare: Double, adminRate: Double, personalTax: Double, fixedContributions: [TaxLine]) {
            self.year = year
            self.rate = rate > 0 ? rate : 1
            self.tariffs = tariffs
            self.labels = labels
            self.base = base
            self.incomeTaxes = incomeTaxes
            self.lumpSum = lumpSum
            self.capitalBenefits = capitalBenefits
            preparedCapitalTotal = capitalBenefits.reduce(0) { $0 + max(0, $1.amount) }
            self.lockedBuyIns = lockedBuyIns
            self.reversedInPrepare = reversedInPrepare
            self.workAHV = workAHV
            self.annuities = annuities
            self.home = home
            self.nonEmployedShare = nonEmployedShare
            self.adminRate = adminRate
            self.personalTax = personalTax
            self.fixedContributions = fixedContributions
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
        var assessor = SwissMarketAssessor(context: context, fixed: fixedAssessment)
        return assessor.assess(variable)
    }

    /// Sales from ordinary accounts aren't taxed (private capital gains are
    /// tax-free), so they raise exactly what they sell. A payout from a
    /// pension wrapper is a capital benefit, taxed with the year's other
    /// capital benefits known in advance: solved by bisection on that tariff
    /// alone. `nil` for an unknown wrapper, which the engine solves.
    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double? {
        guard let context else { return nil }
        let net = max(0, net)
        switch SwissTreatment(bucket.wrapper, foreign: context.tariffs.p.foreignWrappers) {
        case .ordinary, .taxFree, .taxedAtSource:
            return net
        case .unknown:
            return nil
        case .pillar3a, .vestedBenefits, .deferred:
            let tariffs = context.tariffs
            let prepared = context.preparedCapitalTotal
            let before = tariffs.capitalBenefitTotal(on: prepared)
            let wanted = net * context.rate
            guard let gross = NumericGrossUp.solve(net: wanted, tolerance: 1e-6, netProceeds: { gross in
                gross - (tariffs.capitalBenefitTotal(on: prepared + gross) - before)
            }) else { return nil }
            return gross / context.rate
        }
    }
}

/// How the Swiss system treats a wrapper ID.
enum SwissTreatment: Hashable, Sendable {
    /// `ch.ordinary`, the generic `taxable`, and other systems' taxable
    /// wrappers: wealth tax, income taxed, gains free.
    case ordinary
    case pillar3a
    /// `ch.vestedBenefits` and a `ch.bvg` account: payouts reverse recent buy-ins.
    case vestedBenefits
    /// The generic `taxDeferred` and other systems' pension wrappers:
    /// payouts are capital benefits (with a warning for a foreign one).
    case deferred(foreign: Bool)
    case taxFree
    /// Another system's wrapper whose payouts the paying country taxes.
    case taxedAtSource
    /// A wrapper no system the module knows: taxed as ordinary, payouts as
    /// capital benefits, with a warning.
    case unknown

    init(_ wrapper: String, foreign: [String: SwissParameters.ForeignWrapper]) {
        switch wrapper {
        case SwissWrapper.ordinary, "taxable": self = .ordinary
        case SwissWrapper.pillar3a: self = .pillar3a
        case SwissWrapper.vestedBenefits, SwissWrapper.bvg: self = .vestedBenefits
        case "taxDeferred": self = .deferred(foreign: false)
        case "taxFree": self = .taxFree
        default:
            switch foreign[wrapper] {
            case .taxable: self = .ordinary
            case .taxDeferred: self = .deferred(foreign: true)
            case .taxedAtSource: self = .taxedAtSource
            case nil: self = .unknown
            }
        }
    }

    /// Whether its payouts are capital benefits.
    var paysCapitalBenefits: Bool {
        switch self {
        case .pillar3a, .vestedBenefits, .deferred, .unknown: true
        default: false
        }
    }

    /// Whether its balances are wealth and its income is taxed.
    var isWealth: Bool {
        self == .ordinary || self == .unknown
    }
}

/// Stages 7–9 for one path: wrapper payouts as capital benefits,
/// investment income, the wealth tax and AHV contributions without work.
struct SwissMarketAssessor {
    let context: SwissPreparedYear.Context
    let fixed: TaxAssessment

    init(context: SwissPreparedYear.Context, fixed: TaxAssessment) {
        self.context = context
        self.fixed = fixed
    }

    mutating func assess(_ variable: VariableYear) -> TaxAssessment {
        let c = context
        let rate = c.rate
        let p = c.tariffs.p
        let foreign = p.foreignWrappers
        var capitalIncome = 0.0
        var benefits = c.capitalBenefits
        var vestedPaid = false
        var wealth = c.home
        var gains = 0.0
        var unknown: Set<String> = []
        var foreignPayouts: Set<String> = []
        var taxedAtSource: Set<String> = []

        func treatment(_ wrapper: String) -> SwissTreatment {
            let treatment = SwissTreatment(wrapper, foreign: foreign)
            if treatment == .unknown { unknown.insert(wrapper) }
            return treatment
        }
        func payOut(_ wrapper: String, _ amount: Double, _ treatment: SwissTreatment) {
            guard amount > 0 else { return }
            switch treatment {
            case .taxedAtSource:
                taxedAtSource.insert(wrapper)
                return
            case .deferred(let isForeign):
                if isForeign { foreignPayouts.insert(wrapper) }
            case .vestedBenefits:
                vestedPaid = true
            default:
                break
            }
            guard treatment.paysCapitalBenefits else { return }
            let chf = amount * rate
            if let index = benefits.firstIndex(where: { $0.subject == wrapper }) {
                benefits[index].amount += chf
            } else {
                benefits.append(SwissCapitalBenefit(subject: wrapper, amount: chf))
            }
        }

        for sale in variable.sales {
            let kind = treatment(sale.wrapper)
            if kind.isWealth {
                if let cost = sale.costBasis, sale.category != .cash { gains += max(0, sale.proceeds - cost) * rate }
            } else {
                payOut(sale.wrapper, sale.proceeds, kind)
            }
        }
        for payout in variable.payouts {
            let kind = treatment(payout.wrapper)
            if !kind.isWealth || kind == .unknown { payOut(payout.wrapper, payout.amount, kind) }
        }
        for income in variable.capitalIncome where income.amount > 0 && treatment(income.wrapper).isWealth {
            capitalIncome += income.amount * rate
        }
        for balance in variable.balances where treatment(balance.wrapper).isWealth {
            wealth += balance.value * rate
        }

        var issues = fixed.issues
        var extraIncome = 0.0
        if vestedPaid && c.lockedBuyIns > 0 && !c.reversedInPrepare {
            extraIncome = c.lockedBuyIns
            issues.append(.warning(
                "ch.bvg.buyInLock",
                "A lump sum from the 2nd pillar in \(c.year) comes within \(p.bvg.lockYears) years of BVG buy-ins "
                    + "(\(francs(c.lockedBuyIns))): their deduction is reversed, and the fund may refuse the lump sum.",
                year: c.year, regime: BVGPensionScheme.schemeID))
        }

        // Stage 8: investment income joins the other income.
        let tariffs = c.tariffs
        var builder = SwissLineBuilder(tariffs: tariffs, labels: c.labels)
        var incomeTaxes = c.incomeTaxes
        if let base = c.base {
            if capitalIncome > 0 || extraIncome > 0 {
                incomeTaxes = tariffs.incomeTaxes(base, capitalIncome: capitalIncome, extraIncome: extraIncome)
            }
            if let taxes = incomeTaxes {
                builder.addIncome(federal: taxes.federal, federalBase: taxes.federalTaxable, simple: taxes.simple,
                                  cantonalBase: taxes.cantonalTaxable)
            }
        } else if let lumpSum = c.lumpSum {
            builder.addIncome(federal: lumpSum.federal, federalBase: lumpSum.base, simple: lumpSum.simple,
                              cantonalBase: lumpSum.base)
        }
        builder.addPersonalTax(c.personalTax)

        // Stage 7: all of the year's capital benefits, taxed together.
        builder.addCapitalBenefits(benefits)

        // Stage 9: wealth tax, with Ticino's brake, for the share of the year.
        let fraction = min(1, max(0, variable.fractionOfYear))
        let netWealth = max(0, wealth)
        let place = tariffs.place
        if let lumpSum = c.lumpSum {
            builder.addWealth(simple: lumpSum.wealthSimple, netWealth: lumpSum.deemedWealth, fraction: 1)
        } else {
            let simple = place.canton.wealthSimpleTax(on: netWealth)
            var brake = 0.0
            if let rule = place.canton.brake, let taxes = incomeTaxes, simple > 0 {
                let multipliers = place.canton.cantonMultiplier + place.communeMultiplier
                let total = (taxes.simple + simple) * multipliers
                let counted = taxes.cantonalTaxable + max(0, rule.minimumYieldOnWealth * netWealth - capitalIncome)
                brake = min(simple * multipliers, max(0, total - rule.maximumShareOfIncome * counted))
            }
            builder.addWealth(simple: simple, netWealth: netWealth, fraction: fraction, brake: brake)
        }

        // AHV without work: on wealth plus 20 × the pensions, less what was
        // paid on earnings (none due when that's at least half of it).
        var contributions = fixed.contributions
        if c.nonEmployedShare > 0 {
            let rules = p.nonEmployed
            let base = netWealth + rules.pensionIncomeMultiple * c.annuities
            let full = rules.contribution(onBase: base)
            let due = c.workAHV >= full / 2 ? 0 : full - c.workAHV
            let amount = due * (1 + c.adminRate) * fraction * c.nonEmployedShare
            if amount > 1e-9 {
                contributions.append(TaxLine(id: SwissLine.ahvNonEmployed, label: c.labels.ahvNonEmployed,
                                             amount: amount / rate, base: base / rate))
            }
        }

        // Checks.
        if gains > 0, let taxes = incomeTaxes {
            let netIncome = max(0, taxes.cantonalTaxable) + gains
            if gains > p.traderGainsShare * netIncome {
                issues.append(.warning(
                    "ch.securitiesTrader",
                    "Realised gains of \(francs(gains)) in \(c.year) are more than half of the year's net income: one "
                        + "of the tests that make gains tax-free private wealth management (ESTV circular 36) isn't met, "
                        + "so the tax office could look at them as trading income. The estimate keeps them tax-free.",
                    year: c.year))
            }
        }
        for wrapper in unknown.sorted() {
            issues.append(.warning(
                "ch.unknownWrapper",
                "Switzerland doesn't know the wrapper \"\(wrapper)\": it is taxed as an ordinary account, and its payouts "
                    + "as capital benefits.", year: c.year))
        }
        for wrapper in foreignPayouts.sorted() {
            issues.append(.warning(
                "ch.foreignWrapper",
                "Payouts from \(wrapper) are taxed as capital benefits, like a Swiss pension lump sum (if the scheme is "
                    + "comparable to the 2nd pillar or 3a; to verify).", year: c.year))
        }
        for wrapper in taxedAtSource.sorted() {
            issues.append(.warning(
                "ch.foreignWrapper.taxedAtSource",
                "Payouts from \(wrapper) are taxed by the paying country under the treaty, not in Switzerland.",
                year: c.year))
        }
        return TaxAssessment(lines: builder.converted(rate: rate), contributions: contributions,
                             accruals: fixed.accruals, issues: issues, nextState: fixed.nextState)
    }
}
