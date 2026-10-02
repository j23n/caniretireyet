import Foundation
import TaxKit

/// `de.drv`: the German statutory pension (gesetzliche Rentenversicherung).
/// See docs/tax/DE.md, "Statutory pension".
///
/// - **Points.** Starts from the plan's `points` (Entgeltpunkte, from the
///   Renteninformation); each year of work adds its insured earnings
///   (the system's accrual) divided by that year's average earnings, which
///   grow by `realWageGrowth` in today's euros.
/// - **Amount.** Points × the pension value (€42.52 a month from July 2026,
///   growing by `realPensionValueGrowth` in today's euros, before and after
///   the claim) × the access factor, paid monthly.
/// - **Routes.** The standard pension at the standard age (67 for those born
///   from 1964) after 5 years; from 63 after 35 years, 0.3% less for each
///   month early; at 65 (by birth year) after 45 years, with no deduction;
///   0.5% more for each month deferred past the standard age. Years in other
///   EU/EEA countries, Switzerland and agreement countries count toward the
///   waiting times but add no points. `ageIncreaseMonthsPerYear` adds months
///   to every age for each year from 2032, to test the proposed link to life
///   expectancy.
public struct DRVPensionScheme: PensionScheme {
    /// `de.drv`.
    public static let schemeID = "de.drv"

    public let id = DRVPensionScheme.schemeID
    public let name = "Deutsche Rentenversicherung (statutory pension)"

    public init() {}

    /// The plan's options: the record so far, and the assumptions about wages,
    /// the pension value and pension ages.
    public var options: [OptionField] {
        [
            .money("points", "Pension points (Entgeltpunkte) so far", default: 0,
                   help: "From your Renteninformation: a number of points, not money."),
            .int("contributionYears", "German contribution years so far", default: 0, range: 0...60,
                 help: "Toward the 5- and 35-year waiting times."),
            .int("years45", "German years toward the 45-year waiting time", range: 0...60,
                 help: "Fewer periods count toward it. Default: the contribution years."),
            .int("foreignContributionYears", "Contribution years abroad", default: 0, range: 0...60,
                 help: "In other EU/EEA countries, Switzerland or an agreement country: they count toward the waiting "
                     + "times, but the other country pays for them."),
            .int("foreignYears45", "Years abroad toward the 45 years", range: 0...60,
                 help: "Compulsory years from work. Default: the years abroad."),
            .percent("realWageGrowth", "Real growth of average earnings per year", default: 0.01, range: -0.05...0.1,
                     help: "Future work earns points against average earnings. A plan assumption."),
            .percent("realPensionValueGrowth", "Real growth of the pension value per year", default: 0.005,
                     range: -0.05...0.1, help: "Before and after the pension starts. A plan assumption."),
            .int("ageIncreaseMonthsPerYear", "Pension ages rise by (months a year, from 2032)", default: 0,
                 range: 0...12, help: "To test the proposed link to life expectancy; 0 is the law today."),
        ]
    }

    public func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore) -> PensionRecord {
        let options = options.withDefaults(from: self.options)
        let years = max(0, options.int("contributionYears", default: 0))
        let foreign = max(0, options.int("foreignContributionYears", default: 0))
        let years45 = max(0, options.int("years45") ?? years)
        let foreign45 = max(0, options.int("foreignYears45") ?? foreign)
        return PensionRecord(scheme: id, contributionMonths: years * 12, foreignContributionMonths: foreign * 12,
                             extra: [Self.points: max(0, options.double("points", default: 0)),
                                     Self.months45: Double((years45 + foreign45) * 12)])
    }

    public func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                       parameters: ParameterSet) {
        accrue(accruals, in: year, to: &record, options: options, parameters: parameters, currencyRate: 1)
    }

    /// Adds the year's insured earnings as points, and its months toward the
    /// waiting times (at most 12 a year).
    public func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                       parameters: ParameterSet, currencyRate: Double) {
        let mine = accruals.filter { $0.target == .pensionScheme(id) }
        guard !mine.isEmpty, let rules = try? DRVParameters(parameters) else { return }
        let options = options.withDefaults(from: self.options)
        let earnings = mine.reduce(0) { $0 + max(0, $1.amount) } * (currencyRate > 0 ? currencyRate : 1)
        let average = rules.averageEarnings(in: year, growth: options.double("realWageGrowth", default: 0))
        record.extra[Self.points, default: 0] += average > 0 ? earnings / average : 0
        let months = min(12, mine.reduce(0) { $0 + max(0, $1.contributionMonths) })
        record.contributionMonths += months
        record.extra[Self.months45, default: 0] += Double(months)
    }

    public func claimOptions(for record: PensionRecord, context: ClaimContext, parameters: any ParameterStore)
        -> [ClaimOption] {
        guard let set = try? parameters.parameters(for: context.year), let rules = try? DRVParameters(set) else {
            return []
        }
        return DRVClaims(record: record, context: context, options: context.options.withDefaults(from: options),
                         rules: rules).claimOptions()
    }

    /// The standard retirement age in `year` for those born from 1964, in
    /// whole years (rounded down).
    public func oldAgePensionAge(in year: Int, options: OptionValues, parameters: any ParameterStore) -> Int? {
        oldAgePensionAgeInMonths(in: year, options: options, parameters: parameters).map { $0 / 12 }
    }

    /// The standard retirement age in `year`, in months, for those born from
    /// 1964 (the scheme doesn't know the birth year here), plus
    /// `ageIncreaseMonthsPerYear` for each year from 2032.
    public func oldAgePensionAgeInMonths(in year: Int, options: OptionValues, parameters: any ParameterStore) -> Int? {
        guard let set = try? parameters.parameters(for: year), let rules = try? DRVParameters(set) else { return nil }
        let perYear = options.withDefaults(from: self.options).int("ageIncreaseMonthsPerYear", default: 0)
        return (rules.standardAge.last?.months ?? 67 * 12) + rules.ageIncrease(in: year, perYear: perYear)
    }

    /// A public pension.
    public func pensionKind(options: OptionValues) -> PensionKind? {
        .statutory
    }

    static let points = "points"
    static let months45 = "months45"
}

/// The DRV rules of one parameter file.
struct DRVParameters: Sendable {
    var year: Int
    var averageEarnings: Double
    var pensionValue: Double
    var payments: Double
    var standardAge: [AgeStep]
    var waitingYears: Double
    var longInsuredAge: Int
    var longInsuredYears: Double
    var reductionPerMonth: Double
    var veryLongYears: Double
    var veryLongAge: [AgeStep]
    var deferralPerMonth: Double
    var minimumOwnMonths: Int
    var lastAge: Int
    var ageIncreaseFromYear: Int

    init(_ set: ParameterSet) throws {
        let drv = ParameterNode(set)["drv"]
        year = set.year
        averageEarnings = try drv["averageEarnings"]["value"].double()
        pensionValue = try drv["pensionValue"]["value"].double()
        payments = try drv["payments"]["value"].double()
        standardAge = try AgeStep.read(drv["standardAge"]["byBirthYear"])
        waitingYears = try drv["standardAge"]["waitingYears"].double()
        longInsuredAge = try drv["longInsured"]["earliestAge"].int()
        longInsuredYears = try drv["longInsured"]["waitingYears"].double()
        reductionPerMonth = try drv["longInsured"]["reductionPerMonth"].double()
        veryLongYears = try drv["veryLongInsured"]["waitingYears"].double()
        veryLongAge = try AgeStep.read(drv["veryLongInsured"]["byBirthYear"])
        deferralPerMonth = try drv["deferralIncreasePerMonth"]["value"].double()
        minimumOwnMonths = try drv["foreignPeriods"]["minimumOwnPeriodMonths"].int()
        lastAge = try drv["claims"]["lastAge"].int()
        ageIncreaseFromYear = try drv["claims"]["ageIncreaseFromYear"].int()
    }

    /// Average earnings in `year`, in today's euros.
    func averageEarnings(in year: Int, growth: Double) -> Double {
        averageEarnings * pow(1 + growth, Double(max(0, year - self.year)))
    }

    /// The monthly pension value in `year`, in today's euros.
    func pensionValue(in year: Int, growth: Double) -> Double {
        pensionValue * pow(1 + growth, Double(max(0, year - self.year)))
    }

    /// Months added to every claim age in `year`.
    func ageIncrease(in year: Int, perYear: Int) -> Int {
        year >= ageIncreaseFromYear ? (year - ageIncreaseFromYear + 1) * max(0, perYear) : 0
    }
}

/// Works out the claim options for one record. Dates are month indexes
/// (`year × 12 + month − 1`).
struct DRVClaims {
    let record: PensionRecord
    let context: ClaimContext
    let options: OptionValues
    let rules: DRVParameters

    enum Route: String {
        case standard, longInsured, veryLongInsured, deferred

        var id: String { "de.drv.\(rawValue)" }

        var label: String {
            switch self {
            case .standard: "Regelaltersrente"
            case .longInsured: "Altersrente für langjährig Versicherte"
            case .veryLongInsured: "Altersrente für besonders langjährig Versicherte"
            case .deferred: "Regelaltersrente, deferred"
            }
        }
    }

    private var birth: Int { context.birthDate.year * 12 + context.birthDate.month - 1 }

    /// The first month paid for an age of `months`: the month after it's
    /// reached (that month for someone born on the 1st), with the age
    /// increase of the year it's reached.
    private func start(atAge months: Int) -> Int {
        let perYear = options.int("ageIncreaseMonthsPerYear", default: 0)
        let offset = context.birthDate.day == 1 ? 0 : 1
        var month = birth + months + offset
        for _ in 0..<6 {
            let next = birth + months + rules.ageIncrease(in: month / 12, perYear: perYear) + offset
            if next == month { break }
            month = next
        }
        return month
    }

    func claimOptions() -> [ClaimOption] {
        let points = record.extra[DRVPensionScheme.points] ?? 0
        let total = Double(record.contributionMonths + record.foreignContributionMonths) / 12
        let years45 = (record.extra[DRVPensionScheme.months45] ?? 0) / 12
        // Germany pays nothing for less than a year of its own periods.
        guard points > 0, record.contributionMonths >= rules.minimumOwnMonths, total >= rules.waitingYears else {
            return []
        }
        let standard = start(atAge: AgeStep.months(rules.standardAge, bornIn: context.birthDate.year))
        let long = total >= rules.longInsuredYears ? start(atAge: rules.longInsuredAge * 12) : nil
        let veryLong = years45 >= rules.veryLongYears
            ? start(atAge: AgeStep.months(rules.veryLongAge, bornIn: context.birthDate.year)) : nil
        let firstYear = max(context.year, ([standard, long, veryLong].compactMap { $0 }.min() ?? standard) / 12)
        let lastYear = max(context.birthDate.year + rules.lastAge, standard / 12 + 1)
        guard firstYear <= lastYear else { return [] }
        var result: [ClaimOption] = []
        for year in firstYear...lastYear {
            // Each route's earliest start in the year. A route that starts at or
            // after the standard age is the standard pension (or a deferred one).
            var starts: [(route: Route, month: Int, factor: Double)] = []
            func consider(_ route: Route, _ earliest: Int?) {
                guard let earliest else { return }
                let month = max(earliest, year * 12)
                guard month / 12 == year else { return }
                let factor: Double
                var route = route
                if month >= standard {
                    factor = 1 + rules.deferralPerMonth * Double(month - standard)
                    route = month > standard ? .deferred : .standard
                } else {
                    factor = route == .longInsured ? 1 - rules.reductionPerMonth * Double(standard - month) : 1
                }
                guard !starts.contains(where: { $0.month == month && $0.factor == factor }) else { return }
                starts.append((route, month, factor))
            }
            consider(.standard, standard)
            consider(.veryLongInsured, veryLong)
            consider(.longInsured, long)
            // The best first (the one a plan claiming at this age gets): the
            // highest access factor, then the earliest start; the others can be
            // chosen with the pension's `claimRoute`.
            for start in starts.sorted(by: { ($0.factor, -$0.month) > ($1.factor, -$1.month) }) {
                result.append(option(start.route, month: start.month, factor: start.factor, points: points))
            }
        }
        return result
    }

    private func option(_ route: Route, month: Int, factor: Double, points: Double) -> ClaimOption {
        let year = month / 12
        let growth = options.double("realPensionValueGrowth", default: 0)
        let monthly = points * rules.pensionValue(in: year, growth: growth) * factor
        let paidMonths = Double(12 - month % 12)
        let rate = context.currencyRate > 0 ? context.currencyRate : 1
        let ageMonths = month - birth
        var note = "Starts in \(Self.monthName(month % 12)) \(year), at \(ageMonths / 12) years"
            + (ageMonths % 12 > 0 ? " and \(ageMonths % 12) months" : "")
        if factor < 1 {
            note += ", \(percent(1 - factor)) less for starting early"
        } else if factor > 1 {
            note += ", \(percent(factor - 1)) more for deferring"
        }
        note += "."
        return ClaimOption(
            route: route.id, label: route.label, age: year - context.birthDate.year,
            annualAmount: monthly * paidMonths * rules.payments / 12 / rate, note: note,
            fullYearAmount: month % 12 == 0 ? nil : monthly * rules.payments / rate,
            realGrowthPerYear: growth == 0 ? nil : growth)
    }

    private static func monthName(_ index: Int) -> String {
        ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
         "November", "December"][index]
    }
}
