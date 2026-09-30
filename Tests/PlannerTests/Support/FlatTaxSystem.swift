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
struct FlatTaxSystem: TaxSystem {
    var id = "flat"
    var name = "Flat"
    var incomeRate = 0.0
    var contributionRate = 0.0
    var gainsRate = 0.0
    var interestRate = 0.0
    var wealthRate = 0.0
    var payoutRate = 0.0
    var windfallRate = 0.0
    /// Share of gross work income credited to the `flat.state` scheme.
    var pensionCreditRate = 0.0
    /// Share of gross salary credited to the `flat.tfr` wrapper.
    var tfrRate = 0.0
    /// `flat.pension` stays locked before this age.
    var lockAge = 60
    var growthTaxRate: Double?
    /// When false, `grossUp` returns nil and the engine solves numerically.
    var exactGrossUp = true
    /// Validation issues to report, for tests of how they surface.
    var validationIssues: [TaxIssue] = []
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
                context.age >= lockAge ? .accessible(route: nil) : .locked(reason: "Locked until \(lockAge)")
            },
            WrapperRule(id: "flat.tfr", name: "Severance", category: .taxDeferred) { context in
                context.yearsSinceWorkStopped != nil ? .accessible(route: nil) : .locked(reason: "Paid when work ends")
            },
        ]
    }

    var pensionSchemes: [any PensionScheme] { [FlatStateScheme()] }

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
            let taxable = work.gross - work.costs
            fixed.lines.append(TaxLine(id: "flat.income", label: "Income tax",
                                       amount: taxable * (incomeRate + surcharge) * bonus, base: taxable,
                                       subject: work.phaseID))
            if work.regime != defaultRegime(for: work.kind) {
                fixed.issues.append(.warning("flat.regime", "Unexpected regime \(work.regime ?? "none")", year: year.year))
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
        for pension in year.pensions where pension.taxedIn == .residence {
            fixed.lines.append(TaxLine(id: "flat.income", label: "Income tax", amount: pension.amount * incomeRate,
                                       base: pension.amount, subject: pension.id))
        }
        for windfall in year.windfalls {
            fixed.lines.append(TaxLine(id: "flat.windfall", label: "Windfall tax",
                                       amount: windfall.amount * windfallRate, base: windfall.amount))
        }
        var next = state
        next["flat.years"] = (state["flat.years"] ?? 0) + 1
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
        let payouts = variable.payouts.reduce(0.0) { $0 + $1.amount }
        if payouts > 0 {
            assessment.lines.append(TaxLine(id: "flat.payout", label: "Payout tax", amount: payouts * system.payoutRate,
                                            base: payouts))
        }
        let interest = variable.capitalIncome.reduce(0.0) { $0 + $1.amount }
        if interest > 0 {
            assessment.lines.append(TaxLine(id: "flat.interest", label: "Interest tax",
                                            amount: interest * system.interestRate, base: interest))
        }
        let wealth = variable.balances.filter { $0.wrapper != "flat.pension" && $0.wrapper != "flat.tfr" }
            .reduce(0.0) { $0 + $1.value }
        if wealth > 0, system.wealthRate > 0 {
            assessment.lines.append(TaxLine(id: "flat.wealth", label: "Wealth tax", amount: wealth * system.wealthRate,
                                            base: wealth))
        }
        return assessment
    }

    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double? {
        guard system.exactGrossUp else { return nil }
        if bucket.wrapper == "flat.pension" || bucket.wrapper == "flat.tfr" {
            return net / (1 - system.payoutRate)
        }
        return net / (1 - system.gainsRate * bucket.gainShare)
    }
}

/// A made-up public pension: credits add up, and the yearly pension from
/// 65 is 5% of them, 0.2 points more per year of waiting, after 5 years of
/// contributions.
struct FlatStateScheme: PensionScheme {
    let id = "flat.state"
    let name = "State pension"
    var options: [OptionField] {
        [OptionField(key: "montante", label: "Credits so far", kind: .money, defaultValue: 0)]
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
