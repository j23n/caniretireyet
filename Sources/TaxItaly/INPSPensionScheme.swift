import Foundation
import TaxKit

/// `it.inps`: the INPS pension under the contributory system (for anyone who
/// started contributing after 1995). See docs/tax/IT.md, "INPS pension".
///
/// - **Montante.** Starts from the plan's `montante` (today's money in the
///   plan's currency, kept in euros in the record) and grows each year by
///   `realRevaluation` (the revaluation follows nominal GDP, which in
///   today's euros is roughly real GDP growth), then adds the year's credits
///   from work (33% of salary for employees, 25% of the Gestione Separata
///   base).
/// - **Currency.** The record is in euros; claim options are converted to
///   the plan's currency with the claim context's rate.
/// - **Amount.** Montante × the conversion coefficient for the age at the
///   start (by month), paid in 13 instalments. After the table's last year
///   the coefficients fall by `coefficientDeclinePerYear` a year.
/// - **Routes.** Anticipata contributiva (64, 20 years, 3× the assegno
///   sociale, a 3-month wait, capped at 5× the minimum pension until the
///   vecchiaia age), vecchiaia (67, 20 years, 1×) and vecchiaia contributiva
///   (71, 5 years). Ages rise by the parameter file's steps, then by
///   `ageIncreaseMonthsPerYear` a year. Contributions abroad count toward the
///   years.
/// - **Indexation.** In today's euros the pension keeps its value up to 4×
///   the minimum pension and loses a little above it (90% and 75% of
///   inflation passed on), assuming `indexationInflation`.
public struct INPSPensionScheme: PensionScheme {
    /// `it.inps`.
    public static let schemeID = "it.inps"

    public let id = INPSPensionScheme.schemeID
    public let name = "INPS (contributory system)"

    public init() {}

    /// The plan's options for the pension: the starting montante and years,
    /// and the assumptions about revaluation, coefficients, ages and indexation.
    public var options: [OptionField] {
        [
            .money("montante", "Montante so far", default: 0,
                   help: "From your estratto conto contributivo, revalued to today."),
            .int("contributionYears", "Years of INPS contributions so far", default: 0, range: 0...60),
            .int("foreignContributionYears", "Years of contributions abroad", default: 0, range: 0...60,
                 help: "In the EU or a country with a social-security agreement; they count toward the 20 (or 5) years."),
            .percent("realRevaluation", "Real revaluation of the montante", default: 0.005, range: -0.05...0.1,
                     help: "Roughly real GDP growth."),
            .percent("coefficientDeclinePerYear", "Yearly decline of the conversion coefficients", default: 0.004,
                     range: 0...0.05, help: "After the published table, as life expectancy rises."),
            .int("ageIncreaseMonthsPerYear", "Pension ages rise by (months a year)", default: 1, range: 0...12,
                 help: "After the legislated steps, following life expectancy."),
            .int("motherOfChildren", "Children (mothers)", default: 0, range: 0...20,
                 help: "Lowers the anticipata's minimum to 2.8× (one child) or 2.6× (two or more)."),
            .percent("indexationInflation", "Inflation for pension indexation", default: 0.02, range: 0...0.2),
        ]
    }

    /// The record from the plan's `montante`, `contributionYears` and
    /// `foreignContributionYears`, for a plan in euros.
    public func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore) -> PensionRecord {
        startingRecord(options: options, year: year, parameters: parameters, currencyRate: 1)
    }

    /// The record from the plan's options, with the `montante` (in the
    /// plan's currency) converted to euros at `currencyRate`.
    public func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore,
                               currencyRate: Double) -> PensionRecord {
        let options = options.withDefaults(from: self.options)
        let montante = max(0, options.double("montante", default: 0))
        return PensionRecord(
            scheme: id, montante: currencyRate > 0 && currencyRate != 1 ? montante * currencyRate : montante,
            contributionMonths: max(0, options.int("contributionYears", default: 0)) * 12,
            foreignContributionMonths: max(0, options.int("foreignContributionYears", default: 0)) * 12)
    }

    /// Revalues the montante, then adds the year's credits (for a plan in euros).
    public func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                       parameters: ParameterSet) {
        accrue(accruals, in: year, to: &record, options: options, parameters: parameters, currencyRate: 1)
    }

    /// Revalues the montante, then adds the year's credits, converted from
    /// the plan's currency to euros at `currencyRate`. At most 12 months are
    /// credited in a year.
    public func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                       parameters: ParameterSet, currencyRate: Double) {
        let options = options.withDefaults(from: self.options)
        record.montante *= 1 + options.double("realRevaluation", default: 0)
        let mine = accruals.filter { $0.target == .pensionScheme(id) }
        let credits = mine.reduce(0) { $0 + $1.amount }
        record.montante += currencyRate > 0 && currencyRate != 1 ? credits * currencyRate : credits
        record.contributionMonths += min(12, mine.reduce(0) { $0 + max(0, $1.contributionMonths) })
    }

    /// One option per age at which the pension can start, from the context's
    /// year: the route, the first year's amount (pro rata) and later changes
    /// (the anticipata's cap ending, partial indexation), in the plan's
    /// currency (the context's rate). Empty when no route's conditions can be
    /// met.
    public func claimOptions(for record: PensionRecord, context: ClaimContext, parameters: any ParameterStore)
        -> [ClaimOption] {
        INPSClaims(record: record, context: context, options: context.options.withDefaults(from: options),
                   store: parameters).claimOptions()
    }

    /// The vecchiaia age in `year`, in whole years (rounded down).
    public func oldAgePensionAge(in year: Int, options: OptionValues, parameters: any ParameterStore) -> Int? {
        oldAgePensionAgeInMonths(in: year, options: options, parameters: parameters).map { $0 / 12 }
    }

    /// The vecchiaia age in `year`, in months: 67 years plus the rise in
    /// pension ages (the parameter file's steps, then
    /// `ageIncreaseMonthsPerYear`).
    public func oldAgePensionAgeInMonths(in year: Int, options: OptionValues, parameters: any ParameterStore) -> Int? {
        guard let set = try? parameters.parameters(for: year),
              let rules = try? INPSPensionParameters(ParameterNode(set)["inpsPension"]) else { return nil }
        let perYear = options.withDefaults(from: self.options).int("ageIncreaseMonthsPerYear", default: 0)
        return rules.vecchiaia.age * 12 + rules.ageIncrease(in: year, perYear: perYear)
    }

    /// A public pension, as other countries' systems see it.
    public func pensionKind(options: OptionValues) -> PensionKind? {
        .statutory
    }
}

extension INPSPensionParameters {
    /// Months added to every route's age in `year`: the legislated steps,
    /// then `perYear` more for every year after the last step.
    func ageIncrease(in year: Int, perYear: Int) -> Int {
        var schedule = ageIncreaseMonths
        schedule.yearlyStepAfterLastChange = Double(perYear)
        return Int(schedule.value(in: year).rounded())
    }

    /// Months added to the anticipata's 20 years of contributions in `year`.
    func anticipataContributionIncrease(in year: Int) -> Int {
        Int(anticipataContributionIncreaseMonths.value(in: year).rounded())
    }
}

/// Works out the claim options for one record: routes, dates, amounts.
/// Dates are month indexes (`year × 12 + month − 1`).
struct INPSClaims {
    let record: PensionRecord
    let context: ClaimContext
    let options: OptionValues
    let store: any ParameterStore
    /// The rules of each parameter file, by the file's year.
    private let rulesByFileYear: [Int: INPSPensionParameters]

    init(record: PensionRecord, context: ClaimContext, options: OptionValues, store: any ParameterStore) {
        self.record = record
        self.context = context
        self.options = options
        self.store = store
        var rules: [Int: INPSPensionParameters] = [:]
        for year in store.years {
            if let set = try? store.parameters(for: year),
               let parsed = try? INPSPensionParameters(ParameterNode(set)["inpsPension"]) {
                rules[set.year] = parsed
            }
        }
        rulesByFileYear = rules
    }

    enum Route: CaseIterable {
        case anticipata, vecchiaia, contributiva

        var id: String {
            switch self {
            case .anticipata: "it.inps.anticipata"
            case .vecchiaia: "it.inps.vecchiaia"
            case .contributiva: "it.inps.vecchiaiaContributiva"
            }
        }

        var label: String {
            switch self {
            case .anticipata: "Anticipata contributiva"
            case .vecchiaia: "Vecchiaia"
            case .contributiva: "Vecchiaia contributiva"
            }
        }
    }

    /// One way to start the pension in a given year.
    struct Start {
        var route: Route
        /// The first month paid.
        var month: Int
        /// The monthly amount before any cap, in today's euros.
        var monthly: Double
    }

    private var birth: Int { context.birthDate.year * 12 + context.birthDate.month - 1 }

    /// The rules in `year` (from the latest parameter file at or before it).
    private func rules(_ year: Int) -> INPSPensionParameters? {
        store.parameterYear(for: year).flatMap { rulesByFileYear[$0] }
    }

    private func route(_ route: Route, in rules: INPSPensionParameters) -> INPSPensionParameters.Route {
        switch route {
        case .anticipata: rules.anticipata
        case .vecchiaia: rules.vecchiaia
        case .contributiva: rules.contributiva
        }
    }

    /// The month the age requirement is met, under the rules of the year it's met in.
    private func requirementMonth(_ route: Route) -> Int? {
        let perYear = options.int("ageIncreaseMonthsPerYear", default: 0)
        guard let first = rules(context.year) else { return nil }
        var month = birth + self.route(route, in: first).age * 12
        for _ in 0..<6 {
            let year = month / 12
            guard let rules = rules(year) else { return nil }
            let next = birth + self.route(route, in: rules).age * 12 + rules.ageIncrease(in: year, perYear: perYear)
            if next == month { break }
            month = next
        }
        return month
    }

    /// The earliest start in `year` by `route`, if the route's conditions hold.
    private func start(_ route: Route, in year: Int, requirement: Int) -> Start? {
        guard let rules = rules(year) else { return nil }
        let routeRules = self.route(route, in: rules)
        let earliest = requirement + 1 + routeRules.windowMonths
        guard earliest / 12 <= year else { return nil }
        let month = max(earliest, year * 12)
        var requiredMonths = Int((routeRules.contributionYears * 12).rounded())
        if route == .anticipata { requiredMonths += rules.anticipataContributionIncrease(in: requirement / 12) }
        guard record.contributionMonths + record.foreignContributionMonths >= requiredMonths else { return nil }
        let monthly = monthlyAmount(startingIn: month, rules: rules)
        let multiple: Double
        if route == .anticipata {
            let children = options.int("motherOfChildren", default: 0)
            multiple = children > 0 && !rules.motherMultiples.isEmpty
                ? rules.motherMultiples[min(children, rules.motherMultiples.count) - 1]
                : routeRules.assegnoSocialeMultiple
        } else {
            multiple = routeRules.assegnoSocialeMultiple
        }
        guard monthly >= multiple * rules.assegnoSociale - 1e-9 else { return nil }
        return Start(route: route, month: month, monthly: monthly)
    }

    /// The monthly pension for a start in `month`, in today's euros.
    private func monthlyAmount(startingIn month: Int, rules: INPSPensionParameters) -> Double {
        let year = month / 12
        let revaluation = options.double("realRevaluation", default: 0)
        let montante = record.montante * pow(1 + revaluation, Double(max(0, year - context.year)))
        let decline = options.double("coefficientDeclinePerYear", default: 0)
        let coefficient = rules.coefficient(ageInMonths: month - birth)
            * pow(1 - decline, Double(max(0, year - rules.coefficientsLastYear)))
        return montante * coefficient / rules.instalments
    }

    func claimOptions() -> [ClaimOption] {
        let requirements = Route.allCases.compactMap { route in requirementMonth(route).map { (route, $0) } }
        guard let contributiva = requirements.first(where: { $0.0 == .contributiva })?.1,
              let vecchiaia = requirements.first(where: { $0.0 == .vecchiaia })?.1,
              let youngest = rules(context.year)?.coefficients.keys.min() else { return [] }
        let firstYear = max(context.year, context.birthDate.year + youngest)
        let lastYear = max((contributiva + 1) / 12, context.birthDate.year + 71, firstYear)
        var result: [ClaimOption] = []
        for year in firstYear...lastYear {
            let starts = requirements.compactMap { start($0.0, in: year, requirement: $0.1) }
            // The earliest start wins; on the same month, a route without the cap.
            guard let best = starts.min(by: { ($0.month, $0.route == .anticipata ? 1 : 0)
                < ($1.month, $1.route == .anticipata ? 1 : 0) }) else { continue }
            result.append(option(for: best, capEnd: vecchiaia + 1))
        }
        return result
    }

    /// The claim option for a start: the first year's amount (pro rata), then
    /// the changes from the cap ending and from partial indexation, and a
    /// whole year at the starting rate (monthly × instalments) when the
    /// first year is only part of one.
    private func option(for start: Start, capEnd: Int) -> ClaimOption {
        let rules = rules(start.month / 12)
        let instalments = rules?.instalments ?? 13
        let cap = start.route == .anticipata
            ? (rules.map { $0.anticipataCapMinimumPensionMultiple * $0.minimumPension } ?? .infinity) : .infinity
        let inflation = options.double("indexationInflation", default: 0)
        let startYear = start.month / 12
        var monthly = start.monthly
        var amounts: [(age: Int, amount: Double)] = []
        for year in startYear...max(startYear, context.birthDate.year + 100) {
            if year > startYear, let rules {
                let indexed = rules.minimumPension * rules.indexation.tax(on: monthly / rules.minimumPension)
                monthly = (monthly + inflation * indexed) / (1 + inflation)
            }
            var total = 0.0
            for month in max(start.month, year * 12)...(year * 12 + 11) {
                total += month < capEnd ? min(monthly, cap) : monthly
            }
            amounts.append((year - context.birthDate.year, total * instalments / 12))
        }
        var changes: [ClaimOption.AmountChange] = []
        var previous = amounts[0].amount
        for entry in amounts.dropFirst() where abs(entry.amount - previous) > 0.005 {
            changes.append(.init(age: entry.age, annualAmount: entry.amount))
            previous = entry.amount
        }
        let ageMonths = start.month - birth
        var note = "Starts in \(monthName(start.month % 12)) \(startYear), at \(ageMonths / 12) years"
            + (ageMonths % 12 > 0 ? " and \(ageMonths % 12) months" : "") + "."
        if start.route == .anticipata, let window = rules?.anticipata.windowMonths, window > 0 {
            note += " Paid after a \(window)-month wait"
            if start.monthly > cap { note += ", and capped at \(euros(cap)) a month until the vecchiaia age" }
            note += "."
        }
        // A start after January pays only part of the first year: the whole
        // year at the starting rate is what the pension is worth a year.
        let startingRate = start.month < capEnd ? min(start.monthly, cap) : start.monthly
        let option = ClaimOption(route: start.route.id, label: start.route.label,
                                 age: startYear - context.birthDate.year, annualAmount: amounts[0].amount,
                                 changes: changes, note: note,
                                 fullYearAmount: start.month % 12 == 0 ? nil : startingRate * instalments)
        return inPlanCurrency(option)
    }

    /// An option computed in euros, with its amounts in the plan's currency
    /// (itself for a plan in euros). The note's amounts stay in euros, as
    /// the law states them.
    private func inPlanCurrency(_ option: ClaimOption) -> ClaimOption {
        let rate = context.currencyRate
        guard rate > 0, rate != 1 else { return option }
        var option = option
        option.annualAmount /= rate
        option.changes = option.changes.map { .init(age: $0.age, annualAmount: $0.annualAmount / rate) }
        option.fullYearAmount = option.fullYearAmount.map { $0 / rate }
        return option
    }

    private func monthName(_ index: Int) -> String {
        ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
         "November", "December"][index]
    }
}
