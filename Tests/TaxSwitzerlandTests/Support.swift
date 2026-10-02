@testable import TaxSwitzerland
import TaxKit

/// Shared helpers for the Swiss tests. Made-up people only.
enum Swiss {
    static let system = SwissTaxSystem()

    static func parameters(_ year: Int = 2026) throws -> ParameterSet {
        try system.parameters.parameters(for: year)
    }

    /// The residence options for a commune listed in the parameter file.
    static func place(_ commune: String, _ extra: OptionValues = [:]) -> OptionValues {
        var options: OptionValues = ["canton": .string(["Zurich": "ZH"][commune] ?? "TI"), "commune": .string(commune)]
        for (key, value) in extra.values { options[key] = value }
        return options
    }

    /// A year with one work phase.
    static func workYear(_ kind: EarnedIncomeKind, gross: Double, costs: Double = 0, commune: String = "Zurich",
                         options: OptionValues = [:], age: Int = 40, year: Int = 2026, fraction: Double = 1,
                         contributions: [FixedYear.WrapperContribution] = [], pensions: [FixedYear.Pension] = [],
                         overlays: [RegimeChoice] = [], systemOptions: OptionValues = [:]) -> FixedYear {
        FixedYear(year: year, age: age, systemOptions: place(commune, systemOptions), overlays: overlays,
                  work: [.init(phaseID: "work", kind: kind, options: options, gross: gross, costs: costs,
                               fractionOfYear: fraction)],
                  pensions: pensions, wrapperContributions: contributions)
    }

    /// A retired year with one pension.
    static func pensionYear(_ amount: Double, commune: String = "Zurich", age: Int = 70, scheme: String = "ch.ahv",
                            year: Int = 2026) -> FixedYear {
        FixedYear(year: year, age: age, systemOptions: place(commune),
                  pensions: [.init(id: "pension-0", scheme: scheme, amount: amount)])
    }

    /// Prepares `year` and returns the prepared year.
    static func prepare(_ year: FixedYear, state: TaxState = .empty, system: SwissTaxSystem = system) throws
        -> SwissPreparedYear {
        SwissYearCalculator.prepare(system: system, year: year, state: state,
                                    parameters: try system.parameters.parameters(for: year.year))
    }
}

extension TaxAssessment {
    /// The sum of the lines with `id`.
    func total(_ id: String) -> Double {
        lines.filter { $0.id == id }.reduce(0) { $0 + $1.amount }
    }

    /// The sum of the contribution lines with `id`.
    func contribution(_ id: String) -> Double {
        contributions.filter { $0.id == id }.reduce(0) { $0 + $1.amount }
    }

    /// The sum of the accruals to `scheme`.
    func accrued(_ scheme: String) -> Double {
        accruals.filter { $0.target == .pensionScheme(scheme) }.reduce(0) { $0 + $1.amount }
    }
}
