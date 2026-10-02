import Foundation
import TaxKit

/// A made-up flat-rate tax system for the planner's tests. Every rate is a
/// stored property, so a test sets exactly the taxes it checks. Not a real
/// rule set.
///
/// - Work: income tax on gross − costs, contributions on gross, a credit to
///   the `flat.state` pension scheme and optionally to the `flat.tfr` wrapper.
/// - Pensions taxed at the income rate; windfalls at their own rate.
/// - Markets: gains tax on sales, payout tax on wrapper payouts, interest tax,
///   and a wealth tax on taxable balances.
/// - Optionally (off by default): its own currency, with an income allowance
///   in it; a tax on lump sums from pensions; a tax on fund income kept in
///   the fund, which can raise the funds' purchase cost; an occupational
///   scheme `flat.fund` with lump-sum claim options, buy-ins and a seed
///   wrapper; and a `flat.pillar` wrapper that must pay out or spreads its
///   payouts.
/// - Optionally, a country, and a tax on pensions it pays to non-residents
///   (G8): `nonResidentRate` on what's above `nonResidentAllowance` (in its
///   own currency), plus `nonResidentFee` shared by the pensions; and as the
///   residence, it can tax pensions taxed at source too, crediting the
///   paying country's tax (`taxesSourcePensionsWithCredit`).
struct FlatTaxSystem: TaxSystem {
    var id = "flat"
    var name = "Flat"
    /// The system's own currency, if any.
    var currency: String?
    /// The system's country, if any.
    var country: String?
    /// Pensions paid to non-residents are taxed at this rate; `nil`: not at all.
    var nonResidentRate: Double?
    /// Each pension's yearly amount up to this much, in the system's
    /// currency, isn't taxed for non-residents.
    var nonResidentAllowance = 0.0
    /// A fixed yearly amount charged to non-residents, with no subject.
    var nonResidentFee = 0.0
    /// A contribution rate on pensions paid to non-residents.
    var nonResidentContributionRate = 0.0
    /// As the residence, pensions taxed at source are taxed at the income
    /// rate too, less what the paying country charged.
    var taxesSourcePensionsWithCredit = false
    /// Work income up to this much, in the system's currency, isn't taxed.
    var incomeAllowance = 0.0
    var incomeRate = 0.0
    var contributionRate = 0.0
    var gainsRate = 0.0
    var interestRate = 0.0
    var wealthRate = 0.0
    var payoutRate = 0.0
    /// Payout tax is charged on what was paid in (the payout's `costBasis`)
    /// rather than on the whole payout.
    var payoutOnCostBasis = false
    /// The payout rate falls by this much per year of membership.
    var payoutDiscountPerMembershipYear = 0.0
    var windfallRate = 0.0
    /// Share of gross work income credited to the `flat.state` scheme.
    var pensionCreditRate = 0.0
    /// Share of gross salary credited to the `flat.tfr` wrapper.
    var tfrRate = 0.0
    /// A revaluation set by law for `flat.tfr`, taxed at `tfrGrowthTaxRate`.
    var tfrRevaluation: WrapperRevaluation?
    var tfrGrowthTaxRate: Double?
    /// `flat.pension` stays locked before this age, unless the planner
    /// passes an old-age pension age.
    var lockAge = 60
    /// The `flat.state` scheme's old-age pension age, if it has one.
    var oldAgePensionAge: Int?
    var growthTaxRate: Double?
    /// When false, `grossUp` returns nil and the engine solves numerically.
    var exactGrossUp = true
    /// Validation issues to report, for tests of how they surface.
    var validationIssues: [TaxIssue] = []
    /// A year's work income above this gets a warning from `prepare`: a
    /// check that needs each year's amounts.
    var revenueLimit: Double?
    /// Lump sums from pensions are taxed at this rate instead of the income rate.
    var lumpSumRate: Double?
    /// The tax on fund income kept in the fund (`reportedIncome`).
    var reportedIncomeRate = 0.0
    /// Whether that income is added to the funds' purchase cost.
    var reportedIncomeRaisesCostBasis = false
    /// When the `flat.pillar` wrapper opens, and its payout rules.
    var pillarAccessAge = 60
    var pillarPayoutYears: Int?
    var pillarMustPayOutAge: Int?
    /// The `flat.fund` scheme's yearly real growth of its annuity.
    var fundAnnuityGrowth: Double?
    /// A tax on taxable holdings' value before the year's returns, capped at
    /// their nominal rise (each balance's `startValue` and `nominalReturn`),
    /// like a deemed income on the start value.
    var startValueRate = 0.0
    let parameters: any ParameterStore

    init() {
        parameters = try! JSONParameterStore(system: "flat", files: [
            2025: Data(#"{ "bonusShare": "0.5", "source": "made up" }"#.utf8),
        ])
    }

    var options: [OptionField] {
        [OptionField(key: "surcharge", label: "Surcharge", kind: .percent, defaultValue: 0)]
    }

    var regimes: [RegimeDescriptor] {
        [
            RegimeDescriptor(id: "\(id).employee", name: "\(name) employee", scope: .earnedIncome([.employee])),
            RegimeDescriptor(id: "\(id).self", name: "\(name) self-employed", scope: .earnedIncome([.selfEmployed])),
            RegimeDescriptor(id: "\(id).bonus", name: "\(name) bonus", scope: .overlay),
        ]
    }

    var wrappers: [WrapperRule] {
        let lockAge = lockAge
        return [
            WrapperRule(id: "flat.ordinary", name: "Ordinary", category: .taxable) { _ in .accessible(route: nil) },
            WrapperRule(id: "flat.pension", name: "Pension fund", category: .taxDeferred, growthTaxRate: growthTaxRate) {
                context in
                let age = context.oldAgePensionAge ?? lockAge
                return context.age >= age ? .accessible(route: nil) : .locked(reason: "Locked until \(age)")
            },
            WrapperRule(id: "flat.tfr", name: "Severance", category: .taxDeferred, growthTaxRate: tfrGrowthTaxRate,
                        revaluation: tfrRevaluation) { context in
                context.yearsSinceWorkStopped != nil ? .accessible(route: nil) : .locked(reason: "Paid when work ends")
            },
            pillarRule,
            WrapperRule(id: "flat.vested", name: "Vested benefits", category: .taxDeferred) { context in
                context.age >= 60 ? .accessible(route: nil) : .locked(reason: "Locked until 60")
            },
        ]
    }

    private var pillarRule: WrapperRule {
        let accessAge = pillarAccessAge
        let mustPayOutAge = pillarMustPayOutAge
        return WrapperRule(id: "flat.pillar", name: "Pillar", category: .taxDeferred,
                           preferredPayoutYears: pillarPayoutYears,
                           mustPayOut: mustPayOutAge.map { age in { @Sendable context in context.age >= age } }) { context in
            context.age >= accessAge ? .accessible(route: nil) : .locked(reason: "Locked until \(accessAge)")
        }
    }

    var pensionSchemes: [any PensionScheme] {
        [FlatStateScheme(oldAge: oldAgePensionAge), FlatFundScheme(annuityGrowth: fundAnnuityGrowth)]
    }

    /// The payout rate after `membershipYears` of membership.
    func payoutRate(membershipYears: Int?) -> Double {
        max(0, payoutRate - payoutDiscountPerMembershipYear * Double(membershipYears ?? 0))
    }

    func defaultRegime(for kind: EarnedIncomeKind) -> String? {
        switch kind {
        case .employee: "\(id).employee"
        case .selfEmployed: "\(id).self"
        default: nil
        }
    }

    func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue] {
        validationIssues
    }

    func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear {
        let surcharge = year.systemOptions.withDefaults(from: options).double("surcharge") ?? 0
        let bonus = year.overlays.contains { $0.regime == "\(id).bonus" }
            ? (parameters.double(at: "bonusShare") ?? 1) : 1
        var fixed = TaxAssessment()
        for work in year.work {
            var taxable = work.gross - work.costs
            if incomeAllowance > 0 {
                // The allowance is in the system's currency; the tax goes back in the plan's.
                taxable = year.inPlanCurrency(max(0, year.inSystemCurrency(taxable) - incomeAllowance))
            }
            fixed.lines.append(TaxLine(id: "flat.income", label: "Income tax",
                                       amount: taxable * (incomeRate + surcharge) * bonus, base: taxable,
                                       subject: work.phaseID))
            if work.regime != defaultRegime(for: work.kind) {
                fixed.issues.append(.warning("flat.regime", "Unexpected regime \(work.regime ?? "none")", year: year.year))
            }
            if let revenueLimit, work.gross > revenueLimit {
                fixed.issues.append(.warning("flat.revenueLimit", "Work income is above the limit in \(year.year).",
                                             year: year.year, regime: work.regime))
            }
            fixed.contributions.append(TaxLine(id: "flat.social", label: "Social contributions",
                                               amount: work.gross * contributionRate, base: work.gross,
                                               subject: work.phaseID))
            if pensionCreditRate > 0 {
                fixed.accruals.append(Accrual(target: .pensionScheme("flat.state"), amount: work.gross * pensionCreditRate,
                                              contributionMonths: Int((12 * work.fractionOfYear).rounded()),
                                              source: work.phaseID))
            }
            if tfrRate > 0, work.kind == .employee {
                fixed.accruals.append(Accrual(target: .wrapper("flat.tfr"), amount: work.gross * tfrRate,
                                              source: work.phaseID))
            }
        }
        for pension in year.pensions where pension.taxedIn == .source && taxesSourcePensionsWithCredit {
            let tax = pension.amount * incomeRate
            fixed.lines.append(TaxLine(id: "flat.income", label: "Income tax", amount: tax, base: pension.amount,
                                       subject: pension.id))
            if let paid = pension.sourceTax, paid > 0 {
                fixed.lines.append(TaxLine(id: "flat.foreignCredit", label: "Credit for tax paid abroad",
                                           amount: -min(paid, tax), subject: pension.id))
            }
        }
        for pension in year.pensions where pension.taxedIn == .residence {
            if pension.form == .lumpSum, let lumpSumRate {
                fixed.lines.append(TaxLine(id: "flat.lumpSum", label: "Lump-sum tax", amount: pension.amount * lumpSumRate,
                                           base: pension.amount, subject: pension.id))
                continue
            }
            fixed.lines.append(TaxLine(id: "flat.income", label: "Income tax", amount: pension.amount * incomeRate,
                                       base: pension.amount, subject: pension.id))
        }
        // Buy-ins into the fund scheme are credited to it.
        for contribution in year.wrapperContributions where contribution.wrapper == FlatFundScheme.schemeID {
            fixed.accruals.append(Accrual(target: .pensionScheme(FlatFundScheme.schemeID), amount: contribution.amount,
                                          source: contribution.source))
        }
        for windfall in year.windfalls {
            fixed.lines.append(TaxLine(id: "flat.windfall", label: "Windfall tax",
                                       amount: windfall.amount * windfallRate, base: windfall.amount,
                                       subject: windfall.name))
        }
        var next = state
        next["flat.years"] = (state["flat.years"] ?? 0) + 1
        fixed.nextState = next
        return FlatPreparedYear(system: self, fixed: fixed)
    }

    func prepareNonResident(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> (any PreparedTaxYear)? {
        guard let nonResidentRate else { return nil }
        var fixed = TaxAssessment()
        for pension in year.pensions {
            let taxable = year.inPlanCurrency(max(0, year.inSystemCurrency(pension.amount) - nonResidentAllowance))
            fixed.lines.append(TaxLine(id: "\(id).nonResident", label: "Non-resident tax",
                                       amount: taxable * nonResidentRate, base: taxable, subject: pension.id))
            if nonResidentContributionRate > 0 {
                fixed.contributions.append(TaxLine(id: "\(id).nonResidentHealth", label: "Health contributions",
                                                   amount: pension.amount * nonResidentContributionRate,
                                                   base: pension.amount, subject: pension.id))
            }
        }
        if nonResidentFee > 0 {
            fixed.lines.append(TaxLine(id: "\(id).nonResidentFee", label: "Non-resident fee",
                                       amount: year.inPlanCurrency(nonResidentFee)))
        }
        if year.residenceSystem(in: year.year) == id {
            fixed.issues.append(.warning("flat.nonResidentAtHome", "Asked about a resident.", year: year.year))
        }
        var next = state
        next["\(id).nonResidentYears"] = (state["\(id).nonResidentYears"] ?? 0) + 1
        fixed.nextState = next
        return FlatPreparedYear(system: self, fixed: fixed)
    }
}

struct FlatPreparedYear: PreparedTaxYear {
    let system: FlatTaxSystem
    let fixed: TaxAssessment

    var fixedAssessment: TaxAssessment { fixed }

    func assess(_ variable: VariableYear) -> TaxAssessment {
        var assessment = fixed
        let gains = variable.sales.reduce(0.0) { $0 + max(0, $1.proceeds - ($1.costBasis ?? 0)) }
        if gains > 0 {
            assessment.lines.append(TaxLine(id: "flat.gains", label: "Gains tax", amount: gains * system.gainsRate,
                                            base: gains))
        }
        var payoutBase = 0.0
        var payoutTax = 0.0
        for payout in variable.payouts {
            let base = system.payoutOnCostBasis ? min(payout.amount, payout.costBasis ?? payout.amount) : payout.amount
            payoutBase += base
            payoutTax += base * system.payoutRate(membershipYears: payout.membershipYears)
        }
        if payoutBase > 0 {
            assessment.lines.append(TaxLine(id: "flat.payout", label: "Payout tax", amount: payoutTax, base: payoutBase))
        }
        let interest = variable.capitalIncome.filter { $0.kind != .reportedIncome }.reduce(0.0) { $0 + $1.amount }
        if interest > 0 {
            assessment.lines.append(TaxLine(id: "flat.interest", label: "Interest tax",
                                            amount: interest * system.interestRate, base: interest))
        }
        let reported = variable.capitalIncome.filter { $0.kind == .reportedIncome }
        let reportedTotal = reported.reduce(0.0) { $0 + $1.amount }
        if reportedTotal > 0, system.reportedIncomeRate > 0 {
            assessment.lines.append(TaxLine(id: "flat.fundIncome", label: "Fund income tax",
                                            amount: reportedTotal * system.reportedIncomeRate, base: reportedTotal))
            if system.reportedIncomeRaisesCostBasis {
                assessment.costBasisAdjustments = reported.map {
                    CostBasisAdjustment(wrapper: $0.wrapper, category: $0.category, amount: $0.amount)
                }
            }
        }
        if system.startValueRate > 0 {
            let held = variable.balances.filter { $0.wrapper == "flat.ordinary" && $0.category != .cash }
            let base = held.reduce(0.0) { total, balance in
                let start = balance.startValue ?? 0
                return total + min(start, max(0, start * (balance.nominalReturn ?? 0) / system.startValueRate))
            }
            assessment.lines.append(TaxLine(id: "flat.startValue", label: "Start-value tax",
                                            amount: base * system.startValueRate, base: base))
        }
        let wealth = variable.balances.filter { ["flat.ordinary", "taxable"].contains($0.wrapper) || !$0.wrapper.hasPrefix("flat.") }
            .reduce(0.0) { $0 + $1.value } * variable.fractionOfYear
        if wealth > 0, system.wealthRate > 0 {
            assessment.lines.append(TaxLine(id: "flat.wealth", label: "Wealth tax", amount: wealth * system.wealthRate,
                                            base: wealth))
        }
        return assessment
    }

    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double? {
        guard system.exactGrossUp else { return nil }
        if bucket.wrapper.hasPrefix("flat."), bucket.wrapper != "flat.ordinary" {
            let taxedShare = system.payoutOnCostBasis ? 1 - bucket.gainShare : 1
            return net / (1 - system.payoutRate(membershipYears: bucket.membershipYears) * taxedShare)
        }
        return net / (1 - system.gainsRate * bucket.gainShare)
    }
}

/// A made-up public pension: credits add up, and the yearly pension from
/// 65 is 5% of them, 0.2 points more per year of waiting, after 5 years of
/// contributions. Its old-age pension age is the option `oldAgePensionAge`,
/// else `oldAge`.
struct FlatStateScheme: PensionScheme {
    let id = "flat.state"
    let name = "State pension"
    var oldAge: Int?
    var options: [OptionField] {
        [OptionField(key: "montante", label: "Credits so far", kind: .money, defaultValue: 0)]
    }

    func oldAgePensionAge(in year: Int, options: OptionValues, parameters: any ParameterStore) -> Int? {
        options.int("oldAgePensionAge") ?? oldAge
    }

    func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore) -> PensionRecord {
        PensionRecord(scheme: id, montante: options.double("montante") ?? 0,
                      contributionMonths: (options.int("contributionYears") ?? 0) * 12)
    }

    func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                parameters: ParameterSet) {
        for accrual in accruals where accrual.target == .pensionScheme(id) {
            record.montante += accrual.amount
            record.contributionMonths += accrual.contributionMonths
        }
    }

    func claimOptions(for record: PensionRecord, context: ClaimContext, parameters: any ParameterStore)
        -> [ClaimOption] {
        guard record.totalContributionYears >= 5 else { return [] }
        return (65...70).map { age in
            ClaimOption(route: "flat.oldAge", label: "Old age", age: age,
                        annualAmount: record.montante * (0.05 + Double(age - 65) * 0.002))
        }
    }
}

/// A made-up occupational scheme, `flat.fund`: a balance that grows by
/// nothing, from the option `startingBalance` and buy-ins, kept in the
/// system's currency. From 60 it pays 5% of the balance a year
/// (`flat.fund.annuity`), or half of it as a lump sum and 2.5% a year
/// (`flat.fund.half`), or all of it as a lump sum (`flat.fund.capital`).
/// When work stops before 60 it moves into `flat.vested` (`flat.fund.transfer`).
/// Half of each payment is from its mandatory part.
struct FlatFundScheme: PensionScheme {
    static let schemeID = "flat.fund"
    let id = FlatFundScheme.schemeID
    let name = "Fund"
    var annuityGrowth: Double?
    var options: [OptionField] { [.money("startingBalance", "Balance")] }
    var seedWrapper: String? { "flat.fundAccount" }

    func pensionKind(options: OptionValues) -> PensionKind? { .occupational }

    func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore) -> PensionRecord {
        PensionRecord(scheme: id, montante: options.double("startingBalance") ?? 0)
    }

    func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore,
                        currencyRate: Double) -> PensionRecord {
        PensionRecord(scheme: id, montante: (options.double("startingBalance") ?? 0) * currencyRate)
    }

    func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                parameters: ParameterSet) {
        accrue(accruals, in: year, to: &record, options: options, parameters: parameters, currencyRate: 1)
    }

    func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                parameters: ParameterSet, currencyRate: Double) {
        for accrual in accruals where accrual.target == .pensionScheme(id) {
            record.montante += accrual.amount * currencyRate
        }
    }

    func claimOptions(for record: PensionRecord, context: ClaimContext, parameters: any ParameterStore)
        -> [ClaimOption] {
        let balance = context.inPlanCurrency(record.montante)
        let age = context.year - context.birthDate.year
        guard balance > 0 else { return [] }
        if age < 60 {
            guard context.yearsSinceWorkStopped != nil else { return [] }
            return [ClaimOption(route: "flat.fund.transfer", label: "Transfer", age: age, annualAmount: 0,
                                lumpSum: balance, lumpSumWrapper: "flat.vested")]
        }
        return (60...70).flatMap { age in
            [
                ClaimOption(route: "flat.fund.annuity", label: "Annuity", age: age, annualAmount: balance * 0.05,
                            realGrowthPerYear: annuityGrowth, mandatoryShare: 0.5),
                ClaimOption(route: "flat.fund.half", label: "Half as capital", age: age, annualAmount: balance * 0.025,
                            lumpSum: balance / 2, realGrowthPerYear: annuityGrowth, mandatoryShare: 0.5),
                ClaimOption(route: "flat.fund.capital", label: "All as capital", age: age, annualAmount: 0,
                            lumpSum: balance, mandatoryShare: 0.5),
            ]
        }
    }
}
