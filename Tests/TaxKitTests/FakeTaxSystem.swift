import Foundation
import TaxKit

/// A test-only tax system: a flat income tax from its parameters, a flat
/// gains tax, and a pension scheme that credits contributions. It exists to
/// prove the TaxKit protocols can be implemented and driven the way the
/// planner will drive them. Not a real tax rule set.
struct FakeTaxSystem: TaxSystem {
    let id = "fake"
    let name = "Fake"
    let parameters: any ParameterStore

    init() throws {
        parameters = try JSONParameterStore(system: "fake", files: [
            2025: Data(#"{ "incomeRate": "0.2", "gainsRate": "0.25", "source": "made up" }"#.utf8),
            2027: Data(#"{ "incomeRate": "0.3", "gainsRate": "0.25", "source": "made up" }"#.utf8),
        ])
    }

    var options: [OptionField] {
        [OptionField(key: "surcharge", label: "Surcharge", kind: .percent, defaultValue: 0, range: 0...0.1)]
    }

    var regimes: [RegimeDescriptor] {
        [
            RegimeDescriptor(id: "fake.employee", name: "Employee", scope: .earnedIncome([.employee])),
            RegimeDescriptor(id: "fake.flat", name: "Flat", scope: .earnedIncome([.selfEmployed]),
                             options: [OptionField(key: "rate", label: "Rate", kind: .percent, defaultValue: 0.15)],
                             excludes: ["fake.bonus"]),
            RegimeDescriptor(id: "fake.bonus", name: "Bonus", scope: .overlay, firstYear: 2025, lastYear: 2029),
        ]
    }

    var wrappers: [WrapperRule] {
        [
            WrapperRule(id: "fake.ordinary", name: "Ordinary", category: .taxable) { _ in .accessible(route: nil) },
            WrapperRule(id: "fake.pension", name: "Pension", category: .taxDeferred, growthTaxRate: 0.2) { context in
                context.age >= 60 ? .accessible(route: nil) : .locked(reason: "Locked until 60")
            },
        ]
    }

    var pensionSchemes: [any PensionScheme] { [FakePensionScheme()] }

    func defaultRegime(for kind: EarnedIncomeKind) -> String? {
        switch kind {
        case .employee: "fake.employee"
        case .selfEmployed: "fake.flat"
        default: nil
        }
    }

    func validate(_ plan: TaxPlan, parameters: any ParameterStore) -> [TaxIssue] {
        var issues: [TaxIssue] = []
        for phase in plan.work {
            let regimeID = phase.regime ?? defaultRegime(for: phase.kind)
            guard let regimeID, let regime = regime(regimeID) else {
                issues.append(.error("fake.unknownRegime", "Unknown regime \(phase.regime ?? "-")", regime: phase.regime))
                continue
            }
            for overlay in plan.overlays where regime.excludes.contains(overlay.regime) {
                issues.append(.warning("fake.excluded", "\(overlay.regime) doesn't apply to \(regime.name) income",
                                       year: phase.fromYear, regime: overlay.regime))
            }
        }
        return issues
    }

    func prepare(_ year: FixedYear, state: TaxState, parameters: ParameterSet) -> any PreparedTaxYear {
        let rate = parameters.double(at: "incomeRate") ?? 0
        let surcharge = year.systemOptions.withDefaults(from: options).double("surcharge") ?? 0
        var lines: [TaxLine] = []
        var accruals: [Accrual] = []
        for income in year.work {
            let taxable = income.gross - income.costs
            lines.append(TaxLine(id: "fake.income", label: "Income tax", amount: taxable * (rate + surcharge),
                                 base: taxable, subject: income.phaseID))
            accruals.append(Accrual(target: .pensionScheme("fake.pension"), amount: income.gross * 0.33,
                                    contributionMonths: Int((12 * income.fractionOfYear).rounded()),
                                    source: income.phaseID))
        }
        for pension in year.pensions where pension.taxedIn == .residence {
            lines.append(TaxLine(id: "fake.income", label: "Income tax", amount: pension.amount * rate,
                                 base: pension.amount, subject: pension.id))
        }
        var next = state
        next["fake.years"] = (state["fake.years"] ?? 0) + 1
        return FakePreparedYear(
            fixed: TaxAssessment(lines: lines, accruals: accruals, nextState: next),
            gainsRate: parameters.double(at: "gainsRate") ?? 0)
    }
}

struct FakePreparedYear: PreparedTaxYear {
    let fixed: TaxAssessment
    let gainsRate: Double

    var fixedAssessment: TaxAssessment { fixed }

    func assess(_ variable: VariableYear) -> TaxAssessment {
        var assessment = fixed
        for sale in variable.sales {
            let gain = sale.proceeds - (sale.costBasis ?? 0)
            assessment.lines.append(TaxLine(id: "fake.gains", label: "Gains tax", amount: max(0, gain) * gainsRate,
                                            base: gain, subject: sale.wrapper))
        }
        return assessment
    }

    func grossUp(net: Double, from bucket: BucketSnapshot) -> Double? {
        net / (1 - gainsRate * bucket.gainShare)
    }
}

struct FakePensionScheme: PensionScheme {
    let id = "fake.pension"
    let name = "Fake pension"
    var options: [OptionField] {
        [OptionField(key: "montante", label: "Contributions so far", kind: .money, isRequired: true)]
    }

    func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore) -> PensionRecord {
        PensionRecord(scheme: id, montante: options.double("montante") ?? 0,
                      contributionMonths: (options.int("contributionYears") ?? 0) * 12)
    }

    func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                parameters: ParameterSet) {
        record.montante *= 1.005
        for accrual in accruals where accrual.target == .pensionScheme(id) {
            record.montante += accrual.amount
            record.contributionMonths += accrual.contributionMonths
        }
    }

    func claimOptions(for record: PensionRecord, context: ClaimContext, parameters: any ParameterStore)
        -> [ClaimOption] {
        guard record.totalContributionYears >= 5 else { return [] }
        return (65...70).map { age in
            ClaimOption(route: "fake.oldAge", label: "Old age", age: age,
                        annualAmount: record.montante * (0.04 + Double(age - 65) * 0.002))
        }
    }
}
