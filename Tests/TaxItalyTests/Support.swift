@testable import TaxItaly
import TaxKit

/// Shared helpers for the Italian tests.
enum Italy {
    static let system = ItalyTaxSystem()
    static let addizionali: OptionValues = ["addizionaleRegionale": "0.0173", "addizionaleComunale": "0.008"]

    static func parameters(_ year: Int = 2026) throws -> ParameterSet {
        try system.parameters.parameters(for: year)
    }

    /// A year with one work phase.
    static func workYear(_ kind: EarnedIncomeKind, regime: String, gross: Double, costs: Double = 0,
                         options: OptionValues = [:], overlays: [RegimeChoice] = [], year: Int = 2026,
                         pensions: [FixedYear.Pension] = [], contributions: [FixedYear.WrapperContribution] = [])
        -> FixedYear {
        FixedYear(year: year, age: 40, systemOptions: addizionali, overlays: overlays,
                  work: [.init(phaseID: "work", kind: kind, regime: regime, options: options, gross: gross, costs: costs)],
                  pensions: pensions, wrapperContributions: contributions)
    }

    static func pensionYear(_ amount: Double, year: Int = 2026) -> FixedYear {
        FixedYear(year: year, age: 70, systemOptions: addizionali,
                  pensions: [.init(id: "inps", scheme: "it.inps", amount: amount)])
    }

    /// Prepares `year` and returns the prepared year.
    static func prepare(_ year: FixedYear, state: TaxState = .empty) throws -> ItalyPreparedYear {
        ItalyYearCalculator.prepare(system: system, year: year, state: state, parameters: try parameters(year.year))
    }

    /// Runs the fixed stages and returns the calculator, to inspect the IRPEF breakdown.
    static func calculate(_ year: FixedYear, state: TaxState = .empty) throws -> ItalyYearCalculator {
        let set = try parameters(year.year)
        let scale = ThresholdIndexing.scale(for: year, parameterYear: set.year)
        var calculator = ItalyYearCalculator(system: system, year: year, state: state,
                                             parameters: try ItalyParameters(set).scaled(by: scale))
        calculator.computeWork()
        calculator.applyOverlays()
        calculator.computeIrpef()
        return calculator
    }
}

extension TaxAssessment {
    /// The sum of the lines with `id`.
    func total(_ id: String) -> Double {
        lines.filter { $0.id == id }.reduce(0) { $0 + $1.amount }
    }
}
