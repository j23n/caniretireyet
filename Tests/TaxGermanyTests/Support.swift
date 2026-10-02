@testable import TaxGermany
import TaxKit

/// Shared helpers for the German tests. Made-up people only.
enum Germany {
    static let system = GermanTaxSystem()

    static func parameters(_ year: Int = 2026) throws -> ParameterSet {
        try system.parameters.parameters(for: year)
    }

    /// A year with one work phase.
    static func workYear(_ kind: EarnedIncomeKind, regime: String, gross: Double, costs: Double = 0,
                         options: OptionValues = [:], systemOptions: OptionValues = [:], year: Int = 2026,
                         age: Int = 40, pensions: [FixedYear.Pension] = [],
                         contributions: [FixedYear.WrapperContribution] = []) -> FixedYear {
        FixedYear(year: year, age: age, systemOptions: systemOptions,
                  work: [.init(phaseID: "work", kind: kind, regime: regime, options: options, gross: gross, costs: costs)],
                  pensions: pensions, wrapperContributions: contributions)
    }

    /// A pensioner's year with a DRV pension started the year before.
    static func pensionYear(_ amount: Double, year: Int = 2031, systemOptions: OptionValues = [:]) -> FixedYear {
        FixedYear(year: year, age: 68, systemOptions: systemOptions,
                  pensions: [.init(id: "drv", scheme: DRVPensionScheme.schemeID, amount: amount, startYear: year - 1)])
    }

    /// Prepares `year`.
    static func prepare(_ year: FixedYear, state: TaxState = .empty) throws -> any PreparedTaxYear {
        system.prepare(year, state: state, parameters: try parameters(year.year))
    }
}

extension TaxAssessment {
    /// The sum of the lines with `id`.
    func total(_ id: String) -> Double {
        lines.filter { $0.id == id }.reduce(0) { $0 + $1.amount }
    }

    /// The sum of the contributions with `id`.
    func contribution(_ id: String) -> Double {
        contributions.filter { $0.id == id }.reduce(0) { $0 + $1.amount }
    }
}
