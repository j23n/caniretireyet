import TaxKit

/// The IDs of the Italian regimes.
public enum ItalyRegime {
    /// Employees (the default for employee work).
    public static let employee = "it.employee"
    /// Freelancers under the regime ordinario (the default for self-employed work).
    public static let professional = "it.professional"
    /// Freelancers under the regime forfettario.
    public static let forfettario = "it.forfettario"
    /// Impatriati, for moves from 2024 (D.Lgs. 209/2023).
    public static let impatriati2024 = "it.impatriati-2024"
    /// Impatriati, for moves up to 2023 (D.Lgs. 147/2015).
    public static let impatriati2015 = "it.impatriati-2015"
}

/// The IDs of the Italian wrappers.
public enum ItalyWrapper {
    /// Current and savings accounts, brokerage, crypto, gold.
    public static let ordinary = "it.ordinary"
    /// Previdenza complementare.
    public static let pensionFund = "it.pensionFund"
    /// TFR left with the employer.
    public static let tfr = "it.tfr"
}

/// The route an early pension-fund payout takes (RITA).
public enum ItalyAccessRoute {
    public static let rita = "it.rita"
}

extension ItalyTaxSystem {
    /// The residence options.
    static func systemOptions() -> [OptionField] {
        [
            .percent("addizionaleRegionale", "Addizionale regionale", default: 0.0173, range: 0...0.05,
                     help: "Your region's IRPEF surcharge rate (1.23-3.33%)."),
            .percent("addizionaleComunale", "Addizionale comunale", default: 0.008, range: 0...0.02,
                     help: "Your comune's IRPEF surcharge rate (0-0.9%)."),
            .money("otherTaxCredits", "Other tax credits per year", default: 0,
                   help: "Detrazioni not modelled one by one: medical expenses, mortgage interest, …"),
        ]
    }

    /// The regime descriptors. Option defaults that come from the law are
    /// read from `parameters` (the latest year), so the form shows them.
    static func regimeDescriptors(parameters: ItalyParameters?) -> [RegimeDescriptor] {
        let employeeRate = parameters?.inps.employeeRate
        let separataRate = parameters?.inps.separataRate
        let newRegime = parameters?.impatriati2024
        let oldRegime = parameters?.impatriati2015
        let oldRegimeLastYear = oldRegime.map { $0.lastMoveYear + $0.years + $0.extensionYears - 1 }
        return [
            RegimeDescriptor(
                id: ItalyRegime.employee, name: "Employee", scope: .earnedIncome([.employee]),
                options: [
                    .choice("tfr", "TFR goes to", [("employer", "The employer"), ("pensionFund", "A pension fund")],
                            default: "employer"),
                    .percent("inpsRate", "Employee INPS rate", default: employeeRate, range: 0...0.2,
                             help: "The share of gross salary withheld for INPS."),
                ],
                summary: "Gross salary less INPS, taxed with IRPEF, the employment detrazione and the cuneo relief. "
                    + "33% of gross salary is credited to the INPS pension; TFR builds up by about 6.9% a year."),
            RegimeDescriptor(
                id: ItalyRegime.professional, name: "Regime ordinario", scope: .earnedIncome([.selfEmployed]),
                options: [
                    .percent("contributionRate", "Contribution rate", default: separataRate, range: 0...0.5,
                             help: "Gestione Separata, or your professional cassa's rate."),
                ],
                summary: "Revenue less costs; Gestione Separata contributions are deducted, and the rest is taxed "
                    + "with IRPEF and the self-employment detrazione."),
            RegimeDescriptor(
                id: ItalyRegime.forfettario, name: "Regime forfettario", scope: .earnedIncome([.selfEmployed]),
                options: [
                    .percent("coefficient", "Profitability coefficient", range: 0.4...0.86, required: true,
                             help: "67% for IT work (ATECO 62.01, 62.02), 78% for professional activities."),
                    .year("startedIn", "Activity started in",
                          help: "For the 5% start-up rate in the first 5 years of a new activity."),
                    .percent("contributionRate", "Contribution rate", default: separataRate, range: 0...0.5,
                             help: "Gestione Separata, or your professional cassa's rate."),
                ],
                excludes: [ItalyRegime.impatriati2024, ItalyRegime.impatriati2015],
                summary: "Revenue × coefficient, less contributions, taxed at a flat 15% (5% in the first 5 years). "
                    + "No IRPEF or addizionali. Needs prior-year revenue of at most €85,000."),
            RegimeDescriptor(
                id: ItalyRegime.impatriati2024, name: "Impatriati (2024 regime)", scope: .overlay,
                options: [
                    .year("movedIn", "Moved to Italy in", required: true),
                    .bool("minorChild", "With a minor child", help: "60% exempt instead of 50%."),
                ],
                excludes: [ItalyRegime.forfettario],
                firstYear: newRegime?.firstMoveYear,
                summary: "50% of employment and professional income exempt (60% with a minor child), on up to "
                    + "€600,000 a year, for the year of the move and the 4 years after."),
            RegimeDescriptor(
                id: ItalyRegime.impatriati2015, name: "Impatriati (2015 regime)", scope: .overlay,
                options: [
                    .year("movedIn", "Moved to Italy in", required: true),
                    .bool("south", "Moved to the South", help: "90% exempt instead of 70%."),
                    .choice("extension", "Extension for 5 more years",
                            [("none", "None"), ("minorChild", "With a minor child"), ("home", "Home bought in Italy")],
                            default: "none"),
                    .bool("threeMinorChildren", "Three or more minor children", help: "90% exempt in the extension."),
                ],
                excludes: [ItalyRegime.forfettario],
                lastYear: oldRegimeLastYear,
                summary: "70% of employment and professional income exempt (90% in the South) for 5 years; for moves "
                    + "from 2020, 5 more years at 50% (90% with 3+ minor children) with a minor child or a home."),
        ]
    }
}
