import TaxKit

extension SwissTaxSystem {
    /// The residence options. The canton and commune choices are built from
    /// the cantons in the parameter file (the latest year).
    static func systemOptions(parameters p: SwissParameters?) -> [OptionField] {
        let cantons = (p?.cantons.values.map { $0 } ?? []).sorted { $0.code < $1.code }
        let communes = cantons.flatMap { canton in
            canton.communes.keys.sorted().map { (value: $0, label: "\($0) (\(canton.code))") }
        }
        return [
            .choice("canton", "Canton", cantons.map { ($0.code, $0.name) }, required: true,
                    help: "Income and wealth tariffs, deductions, the capital-benefit tax and the communes."),
            .choice("commune", "Commune", communes + [(value: "custom", label: "Another commune")],
                    help: "Default: the cantonal capital. For another commune, choose \"Another commune\" and enter "
                        + "its multiplier."),
            .percent("communeMultiplier", "Communal tax multiplier", range: 0...3,
                     help: "The commune's tax rate as a share of the simple cantonal tax (Steuerfuss, "
                         + "moltiplicatore), e.g. 1.19 for 119%. Filled in from the commune; needed for another one."),
            .choice("tariff", "Tariff", [("single", "Single"), ("married", "Married")], default: "single",
                    help: "Only the single tariff is available: the planner models one person."),
            .percent("churchMultiplier", "Church tax multiplier", default: 0, range: 0...0.5,
                     help: "For members of a recognised church, as a share of the simple tax (e.g. 0.10)."),
            .choice("permit", "Residence permit", [("B", "B (residence)"), ("C", "C (settlement)")],
                    help: "For people without Swiss citizenship. Only for messages: the estimate always uses the "
                        + "ordinary assessment."),
            .money("otherDeductions", "Other deductions per year", default: 0,
                   help: "Deductions not modelled one by one: commuting, meals, medical costs, donations, childcare."),
            .percent("nonEmployedAdminRate", "Admin costs on AHV contributions without work",
                     default: p?.nonEmployed.adminCostMaximumRate,
                     range: 0...(p?.nonEmployed.adminCostMaximumRate ?? 0.05),
                     help: "The compensation office's surcharge; the default is the legal maximum."),
            .choice("capitalBenefitTable", "Capital-to-annuity table",
                    [("average", "Average"), ("male", "Men"), ("female", "Women")], default: "average",
                    help: "Ticino: which column of the ESTV table turns a capital benefit into an annuity for its rate."),
            .money("homeTaxValue", "Tax value of your home", default: 0,
                   help: "A home you own and live in, at its cantonal tax value: wealth tax and AHV without work."),
            .money("mortgage", "Mortgage", default: 0, help: "Deducted from wealth."),
            .money("imputedRentalValue", "Imputed rental value per year", default: 0,
                   help: "Taxed as income until 2028 (the imputed rent ends in 2029)."),
            .money("mortgageInterest", "Mortgage interest per year", default: 0,
                   help: "Deductible until 2028, up to investment income plus CHF 50,000."),
        ]
    }

    /// The regime descriptors. Defaults that come from the law are read
    /// from `p` (the latest year); money defaults stay unset and come from
    /// the parameter file, since options are in the plan's currency.
    static func regimeDescriptors(parameters p: SwissParameters?) -> [RegimeDescriptor] {
        let creditRates = (p?.bvg.ageCredits ?? []).map { band in
            OptionField.percent("bvgCreditRate\(band.fromAge)", "BVG age credit from \(band.fromAge)",
                                default: band.rate, range: 0...0.5,
                                help: "Share of the coordinated salary saved each year; the default is the legal minimum.")
        }
        let maxYears = p?.expatriateYears ?? 5
        return [
            RegimeDescriptor(
                id: SwissRegime.employee, name: "Employee", scope: .earnedIncome([.employee]),
                options: [
                    .choice("bvgPlan", "Pension fund (BVG)", [("minimum", "The legal minimum or more"),
                                                              ("none", "None")], default: "minimum",
                            help: "Compulsory from a yearly salary of CHF 22,680."),
                    .percent("bvgEmployerShare", "Employer's share of the age credits",
                             default: p?.bvg.minimumEmployerShare, range: (p?.bvg.minimumEmployerShare ?? 0.5)...1,
                             help: "At least half; the rest is withheld from salary."),
                    .money("bvgCoordinationDeduction", "Coordination deduction",
                           help: "Default: the legal one (CHF 26,460 in 2026); 0 for funds without one."),
                    .money("bvgInsuredSalaryCap", "Highest insured salary",
                           help: "Default: the legal upper limit (CHF 90,720 in 2026); higher for funds that "
                               + "insure more."),
                ] + creditRates + [
                    .percent("employeeInsuranceRate", "Accident and sickness insurance withheld", default: 0,
                             range: 0...0.05, help: "Non-occupational accident (NBU) and daily sickness (KTG) premiums."),
                ],
                summary: "Gross salary less AHV/IV/EO (5.3%), ALV (1.1% up to CHF 148,200) and the BVG contribution, "
                    + "taxed by the Confederation, the canton and the commune. The salary is credited to the AHV "
                    + "record; the age credits (both shares) to the BVG."),
            RegimeDescriptor(
                id: SwissRegime.selfEmployed, name: "Self-employed", scope: .earnedIncome([.selfEmployed]),
                options: [
                    .percent("bvgSavingsRate", "Voluntary pension fund (BVG)", default: 0, range: 0...0.25,
                             help: "Share of net income paid into a pension fund; with one, the smaller 3a "
                                 + "maximum applies."),
                    .percent("ahvAdminRate", "AHV admin costs", default: 0, range: 0...0.05,
                             help: "The compensation office's surcharge on AHV contributions."),
                ],
                summary: "Revenue less costs; AHV/IV/EO on the sliding scale (10% from CHF 60,500), deducted. No ALV, "
                    + "and a pension fund only by choice; pillar 3a takes up to 20% of net income without one."),
            RegimeDescriptor(
                id: SwissRegime.expatriate, name: "Expatriate deductions", scope: .overlay,
                options: [
                    .year("assignmentStart", "Assignment started in", required: true),
                    .choice("deduction", "Deduction", [("flat", "Flat CHF 1,500 a month"), ("actual", "Actual costs")],
                            default: "flat"),
                    .money("actualAmount", "Actual costs per year", default: 0,
                           help: "Moving, travel home, housing while keeping a home abroad, school fees."),
                ],
                excludes: [SwissRegime.selfEmployed, SwissRegime.lumpSum],
                summary: "Executives and specialists on a temporary assignment deduct extra costs, or CHF 1,500 a "
                    + "month, for at most \(maxYears) years. A permanent move doesn't qualify."),
            RegimeDescriptor(
                id: SwissRegime.lumpSum, name: "Lump-sum taxation", scope: .overlay,
                options: [
                    .money("livingExpenses", "Yearly living expenses", required: true,
                           help: "The household's worldwide spending."),
                    .money("annualRent", "Yearly rent or rental value", required: true,
                           help: "Seven times it is a minimum for the base."),
                    .year("firstYear", "Taxed on expenditure from", required: true,
                          help: "The first year of Swiss residence, or after 10 years away."),
                ],
                excludes: [SwissRegime.employee, SwissRegime.selfEmployed, SwissRegime.expatriate],
                summary: "Taxation on expenditure instead of income and wealth, for people without Swiss citizenship "
                    + "who don't work in Switzerland, where the canton allows it (Ticino; Zurich abolished it). The base "
                    + "is the highest of the living expenses, 7 × the rent and the minimums."),
        ]
    }
}

/// The resolved place of residence in a year: the canton, the commune's
/// multiplier, church tax and the capital-to-annuity factor.
struct SwissPlace: Sendable {
    var canton: SwissCanton
    var commune: String
    var communeMultiplier: Double
    var churchMultiplier: Double
    var conversionFactor: Double

    /// The place from a residence entry's options, or the problem with them.
    static func resolve(_ options: OptionValues, parameters p: SwissParameters, year: Int? = nil)
        -> Result<SwissPlace, SwissPlaceProblem> {
        guard let code = options.string("canton") else { return .failure(.missingCanton) }
        guard let canton = p.cantons[code] ?? p.cantons[code.uppercased()] else {
            return .failure(.unsupportedCanton(code))
        }
        let commune = options.string("commune") ?? canton.capital
        let multiplier: Double
        if let own = options.double("communeMultiplier") {
            if commune != "custom" && canton.communes[commune] == nil {
                return .failure(.communeOutsideCanton(commune, canton))
            }
            multiplier = own
        } else if commune == "custom" {
            return .failure(.customWithoutMultiplier)
        } else if let known = canton.communes[commune] {
            multiplier = known
        } else {
            return .failure(.communeOutsideCanton(commune, canton))
        }
        return .success(SwissPlace(
            canton: canton, commune: commune, communeMultiplier: multiplier,
            churchMultiplier: options.double("churchMultiplier") ?? 0,
            conversionFactor: canton.conversionFactor(table: options.string("capitalBenefitTable") ?? "average")))
    }
}

/// Why a residence entry's options don't name a usable place.
enum SwissPlaceProblem: Error, Sendable {
    case missingCanton
    case unsupportedCanton(String)
    case communeOutsideCanton(String, SwissCanton)
    case customWithoutMultiplier

    /// The problem as an error issue, listing what's supported.
    func issue(supported: [SwissCanton], year: Int?) -> TaxIssue {
        let list = supported.sorted { $0.code < $1.code }.map { "\($0.name) (\($0.code))" }
        switch self {
        case .missingCanton:
            return .error("ch.canton.missing", "Choose the canton you live in: \(list.joined(separator: " or ")).",
                          year: year, option: "canton")
        case .unsupportedCanton(let code):
            return .error("ch.canton.unsupported",
                          "The canton \(code) isn't supported: the Swiss system covers "
                              + "\(list.joined(separator: " and ")).",
                          year: year, option: "canton")
        case .communeOutsideCanton(let commune, let canton):
            let communes = canton.communes.keys.sorted().joined(separator: ", ")
            return .error("ch.commune.unknown",
                          "\(commune) isn't one of the communes listed for \(canton.name) (\(communes)); choose "
                              + "\"Another commune\" and enter its multiplier.", year: year, option: "commune")
        case .customWithoutMultiplier:
            return .error("ch.commune.multiplierMissing",
                          "For another commune, enter its tax multiplier (e.g. 1.19 for 119%).", year: year,
                          option: "communeMultiplier")
        }
    }
}
