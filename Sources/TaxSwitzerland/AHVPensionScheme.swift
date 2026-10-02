import Foundation
import TaxKit

/// `ch.ahv`: the Swiss state pension (1st pillar, AHV/AVS), on scale 44. See
/// docs/tax/CH.md, "State pension".
///
/// - **Record.** Swiss contribution months, months abroad (for the one-year
///   minimum only) and the sum of credited incomes, in CHF. Credits are
///   nominal (revaluation factor 1.000) while the formula's limits follow the
///   mixed index, so the sum is kept relative to the limits: each year it
///   loses `inflation` and half of `realWageGrowth`, and each new credit is
///   divided by the limits' real growth since the plan's first year.
/// - **Amount.** The formula of Art. 34 AHVG on the average credited income
///   (Swiss years only), × min(years, 44) / 44, × the early reduction or the
///   deferral supplement; 13 payments a year, from the month after the
///   birthday; growing by half of `realWageGrowth` a year in today's money,
///   from the claim on.
/// - **Ages.** One claim option per age from 63 to 70 (`ch.ahv.early`,
///   `ch.ahv.reference`, `ch.ahv.deferred`); the plan's `claim` picks it.
public struct AHVPensionScheme: PensionScheme {
    /// `ch.ahv`.
    public static let schemeID = "ch.ahv"

    public let id = AHVPensionScheme.schemeID
    public let name = "AHV (state pension)"

    public init() {}

    public var options: [OptionField] {
        [
            .int("contributionYears", "Swiss contribution years so far", default: 0, range: 0...50,
                 help: "From your individual account statement (IK)."),
            .money("averageIncome", "Average yearly income of those years", default: 0,
                   help: "The average of the incomes credited in your IK statement, in the plan's currency."),
            .int("foreignContributionYears", "Contribution years abroad", default: 0, range: 0...50,
                 help: "In the EU/EFTA or an agreement country: they count only toward the minimum of one year; "
                     + "that country pays its own pension."),
            .percent("realWageGrowth", "Real wage growth", default: 0.01, range: -0.05...0.1,
                     help: "AHV amounts follow the mixed index, so in today's money they rise by half of it a year."),
            .percent("inflation", "Swiss inflation", default: 0.01, range: -0.05...0.2,
                     help: "Incomes are credited at their nominal value, so each year they lose this against the "
                         + "pension's limits."),
        ]
    }

    public func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore) -> PensionRecord {
        startingRecord(options: options, year: year, parameters: parameters, currencyRate: 1)
    }

    /// The record from the plan's years and average income (in the plan's
    /// currency, converted to CHF).
    public func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore,
                               currencyRate: Double) -> PensionRecord {
        let options = options.withDefaults(from: self.options)
        let years = max(0, options.int("contributionYears", default: 0))
        let average = max(0, options.double("averageIncome", default: 0)) * currencyRate
        return PensionRecord(scheme: id, montante: average * Double(years), contributionMonths: years * 12,
                             foreignContributionMonths: max(0, options.int("foreignContributionYears", default: 0)) * 12,
                             extra: [Self.startYearKey: Double(year)])
    }

    public func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                       parameters: ParameterSet) {
        accrue(accruals, in: year, to: &record, options: options, parameters: parameters, currencyRate: 1)
    }

    /// Lets the credited incomes drift against the limits, then adds the
    /// year's credits (in the plan's currency) and at most 12 months.
    public func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                       parameters: ParameterSet, currencyRate: Double) {
        let options = options.withDefaults(from: self.options)
        let start = Int(record.extra[Self.startYearKey] ?? Double(year))
        record.extra[Self.startYearKey] = Double(start)
        if year > start { record.montante *= Self.drift(options) }
        let mine = accruals.filter { $0.target == .pensionScheme(id) }
        let credit = mine.reduce(0) { $0 + max(0, $1.amount) } * currencyRate
        record.montante += credit / pow(Self.limitGrowth(options), Double(max(0, year - start)))
        record.contributionMonths += min(12, mine.reduce(0) { $0 + max(0, $1.contributionMonths) })
    }

    /// One option per age from the earliest (63) to the latest (70), or at
    /// the age in the context's year when that's later. None without at
    /// least a year of contributions (abroad included) or without Swiss years.
    public func claimOptions(for record: PensionRecord, context: ClaimContext, parameters: any ParameterStore)
        -> [ClaimOption] {
        guard let rules = Self.rules(in: context.year, parameters: parameters) else { return [] }
        let options = context.options.withDefaults(from: self.options)
        let swissYears = Double(record.contributionMonths) / 12
        let allYears = swissYears + Double(record.foreignContributionMonths) / 12
        guard swissYears > 0, allYears >= rules.minimumContributionYears else { return [] }
        let birth = context.birthDate
        let currentAge = context.year - birth.year
        let start = Int(record.extra[Self.startYearKey] ?? Double(context.year))
        let average = max(0, record.montante) / swissYears
        let drift = Self.drift(options)
        let growth = Self.limitGrowth(options)
        let scale = min(swissYears, rules.fullScaleYears) / rules.fullScaleYears
        let months = max(0, 12 - birth.month)
        var result: [ClaimOption] = []
        for age in max(rules.earliestAge, currentAge)...max(rules.latestAge, currentAge) {
            let claimYear = birth.year + age
            let averageThen = average * pow(drift, Double(max(0, claimYear - context.year)))
            let factor = rules.adjustment(claimAge: min(age, rules.latestAge))
            let monthly = rules.fullMonthlyPension(averageIncome: averageThen) * scale * factor
                * pow(growth, Double(claimYear - start))
            let payments = rules.payments(in: claimYear)
            let full = context.inPlanCurrency(monthly * payments)
            let first = context.inPlanCurrency(monthly * Double(months) * payments / 12)
            let route: String
            let label: String
            if age < rules.referenceAge {
                route = "ch.ahv.early"
                label = "AHV \(rules.referenceAge - age) year\(age == rules.referenceAge - 1 ? "" : "s") early "
                    + "(−\(percent(1 - factor)))"
            } else if age == rules.referenceAge {
                route = "ch.ahv.reference"
                label = "AHV at the reference age"
            } else {
                route = "ch.ahv.deferred"
                label = "AHV deferred \(min(age, rules.latestAge) - rules.referenceAge) year"
                    + "\(age == rules.referenceAge + 1 ? "" : "s") (+\(percent(factor - 1)))"
            }
            let note = "From the month after the \(age)th birthday, \(Int(payments)) payments a year; "
                + "\(Int((scale * rules.fullScaleYears).rounded())) of \(Int(rules.fullScaleYears)) years."
            result.append(ClaimOption(
                route: route, label: label, age: age, annualAmount: first,
                changes: months < 12 ? [.init(age: age + 1, annualAmount: full)] : [], note: note,
                fullYearAmount: months < 12 ? full : nil, realGrowthPerYear: growth != 1 ? growth - 1 : nil))
        }
        return result
    }

    /// The reference age (65).
    public func oldAgePensionAge(in year: Int, options: OptionValues, parameters: any ParameterStore) -> Int? {
        Self.rules(in: year, parameters: parameters)?.referenceAge
    }

    /// A public pension, as other countries' systems see it.
    public func pensionKind(options: OptionValues) -> PensionKind? {
        .statutory
    }

    static let startYearKey = "startYear"

    /// The pension rules of the file for `year`.
    static func rules(in year: Int, parameters: any ParameterStore) -> SwissParameters.AHVPension? {
        guard let set = try? parameters.parameters(for: year) else { return nil }
        return try? SwissParameters.AHVPension(ParameterNode(set)["ahvPension"])
    }

    /// The yearly factor of the formula's limits in today's money: half of
    /// real wage growth (the mixed index).
    static func limitGrowth(_ options: OptionValues) -> Double {
        1 + options.double("realWageGrowth", default: 0) / 2
    }

    /// The yearly factor of credited incomes against the limits.
    static func drift(_ options: OptionValues) -> Double {
        1 / ((1 + options.double("inflation", default: 0)) * limitGrowth(options))
    }
}
