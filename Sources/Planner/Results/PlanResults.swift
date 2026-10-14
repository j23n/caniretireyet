import Foundation
import Model
import Tracker

/// How thoroughly to run a plan.
public enum PlanRunMode: String, Hashable, Sendable, Codable {
    /// Every run the plan asks for (2,000 by default).
    case full
    /// Fewer runs with the same random draws: a what-if's quick estimate,
    /// before its full run (PLANNER.md, "Engine details").
    case fast
}

/// The results of one run of a plan as the app keeps and shows them: what
/// the Plan screens and the Overview show, and what a baseline saves. Plain
/// values that feed the charts directly, made from a ``PlanResult`` by
/// ``init(result:mode:birthDate:computedAt:)``.
public struct PlanResults: Hashable, Sendable, Codable {
    public var plan: PlanID
    public var computedAt: Date
    public var mode: PlanRunMode
    /// Monte Carlo runs made.
    public var runs: Int
    /// The engine version.
    public var engine: String
    /// The answer to "can I retire yet?".
    public var headline: RetirementAnswer
    /// Chance of success by retirement age.
    public var successByAge: [SuccessPoint]
    /// Portfolio percentiles over time, in today's money.
    public var portfolio: [FanPoint]
    /// Retirement, pension starts, locked money becoming accessible, windfalls.
    public var markers: [ChartMarker]
    /// Retirement income per year by source (median run).
    public var income: [IncomeSegment]
    /// Taxes per year, on investments and on wealth (median run).
    public var taxes: [IncomeSegment]
    /// The spending target per year, drawn over the income chart.
    public var spending: [YearValue]

    // For saving a baseline (PROGRESS.md, "Baselines").
    /// Where the projection starts: the date and value of the included accounts.
    public var start: BaselineStart
    /// The accounts included.
    public var accounts: [AccountID]
    /// Year-end percentiles and the expected path.
    public var years: [BaselineYear]

    /// What the Planner adds: key numbers, the what-if's starting values,
    /// the run's warnings.
    public var details: PlanResultDetails
    /// The currency of every amount: the library's base currency when they
    /// were calculated (`PlanResult.currency`).
    public var currency: CurrencyCode

    public init(plan: PlanID, computedAt: Date, mode: PlanRunMode, runs: Int, engine: String,
                headline: RetirementAnswer, successByAge: [SuccessPoint], portfolio: [FanPoint],
                markers: [ChartMarker], income: [IncomeSegment], taxes: [IncomeSegment], spending: [YearValue],
                start: BaselineStart, accounts: [AccountID], years: [BaselineYear], details: PlanResultDetails,
                currency: CurrencyCode) {
        self.plan = plan
        self.computedAt = computedAt
        self.mode = mode
        self.runs = runs
        self.engine = engine
        self.headline = headline
        self.successByAge = successByAge
        self.portfolio = portfolio
        self.markers = markers
        self.income = income
        self.taxes = taxes
        self.spending = spending
        self.start = start
        self.accounts = accounts
        self.years = years
        self.details = details
        self.currency = currency
    }
}

/// What the Planner adds to ``PlanResults`` beyond the charts: the numbers
/// the Plan screens show next to them (key numbers, "When it fails", the
/// what-if's starting values) and the run's warnings.
public struct PlanResultDetails: Hashable, Sendable, Codable {
    /// `Planner.planHash` of the plan as it ran (with any what-if applied).
    public var planHash: String
    /// Age on the start date.
    public var currentAge: Int
    /// The last age the plan funds.
    public var endAge: Int
    /// What retiring today would need, from the same simulation (PLANNER.md,
    /// "Assets needed to retire today"): the plan assets that make retiring
    /// at today's age reach the plan's confidence. `nil` from runs that
    /// don't look for it (a focus age).
    public var assetsNeeded: AssetsNeeded?
    /// The retirement age `sustainableSpending` in the headline is for.
    public var sustainableSpendingAge: Int?
    /// Warnings from the plan and the library.
    public var issues: [PlanIssue]
    /// The details that depend on the retirement age the charts are for.
    public var focus: PlanFocusDetails
    /// The headline to record for this run (`PlanResult.headline()`, dated
    /// the check-in the plan started from): success rates to 3 decimals,
    /// readiness rounded down to a whole percent, exactly as the CLI records it.
    public var headline: Headline
    /// The earliest age saving nothing more (the coast age) and without
    /// each uncertain windfall (PLANNER.md, "Ages without"); empty from runs
    /// that don't look for them.
    public var agesWithout: [AgeWithout]

    public init(planHash: String, currentAge: Int, endAge: Int, assetsNeeded: AssetsNeeded? = nil,
                sustainableSpendingAge: Int?, issues: [PlanIssue], focus: PlanFocusDetails, headline: Headline,
                agesWithout: [AgeWithout] = []) {
        self.planHash = planHash
        self.currentAge = currentAge
        self.endAge = endAge
        self.assetsNeeded = assetsNeeded
        self.sustainableSpendingAge = sustainableSpendingAge
        self.issues = issues
        self.focus = focus
        self.headline = headline
        self.agesWithout = agesWithout
    }
}

/// The numbers that belong to one retirement age: the fan, paths and
/// failures of the run are for it (`PlanResult.focusAge`).
public struct PlanFocusDetails: Hashable, Sendable, Codable {
    /// The retirement age the fan, income and failures are for.
    public var age: Int
    /// The day work stops at that age.
    public var retirementDate: CalendarDate?
    /// The chance of success at that age.
    public var success: Double?
    /// Median plan assets at the end of the year you retire, and at the plan's end.
    public var medianAtRetirement: Double?
    public var medianAtEnd: Double?
    /// All taxes in the median run, in today's money.
    public var lifetimeTaxes: Double
    /// Saving per month while working in the deterministic run: the
    /// what-if's starting value. `nil` when the plan has no working years.
    public var monthlySaving: Decimal?
    /// Bridge failures (running out before locked money opens), most frequent first.
    public var bridges: [PlanBridgeFailure]
    /// How many runs run out of money at each age, ascending: where each
    /// chapter's failures are (UI.md, "The plan").
    public var failuresByAge: [AgeCount]

    public init(age: Int, retirementDate: CalendarDate?, success: Double?, medianAtRetirement: Double?,
                medianAtEnd: Double?, lifetimeTaxes: Double, monthlySaving: Decimal?, bridges: [PlanBridgeFailure],
                failuresByAge: [AgeCount] = []) {
        self.age = age
        self.retirementDate = retirementDate
        self.success = success
        self.medianAtRetirement = medianAtRetirement
        self.medianAtEnd = medianAtEnd
        self.lifetimeTaxes = lifetimeTaxes
        self.monthlySaving = monthlySaving
        self.bridges = bridges
        self.failuresByAge = failuresByAge
    }
}

/// Runs that ran out while some accounts were still locked away.
public struct PlanBridgeFailure: Hashable, Sendable, Codable {
    public var name: String
    public var accessibleFromAge: Int?
    /// The share of all runs.
    public var share: Double

    public init(name: String, accessibleFromAge: Int?, share: Double) {
        self.name = name
        self.accessibleFromAge = accessibleFromAge
        self.share = share
    }
}

extension PlanResults {
    /// When the charts' retirement happens: the focus age's retirement day.
    public var retirementDate: Date? {
        details.focus.retirementDate?.dateValue
    }

    /// Results from a Planner run.
    ///
    /// - The fan starts at the check-in's value, then has one point per year-end.
    /// - Markers sit on the birthday in their year, so "retire at 55" is drawn where you turn 55.
    /// - Income, taxes and spending are the median run's retirement years (the year you
    ///   retire included), as whole-year amounts.
    public init(result: PlanResult, mode: PlanRunMode, birthDate: CalendarDate, computedAt: Date = Date()) {
        let answer = result.answer
        let focus = result.successCurve.first { $0.age == result.focusAge }
        let baseline = result.baseline(created: result.start.date, kind: .manual)
        let medianRetired = result.medianPath.years.filter { $0.workingShare < 1 }
        let details = PlanResultDetails(
            planHash: result.planHash, currentAge: answer.currentAge, endAge: result.settings.endAge,
            assetsNeeded: answer.assetsNeeded, sustainableSpendingAge: answer.sustainableSpending?.age,
            issues: result.issues,
            focus: PlanFocusDetails(
                age: result.focusAge, retirementDate: focus?.retirementDate, success: focus?.success,
                medianAtRetirement: result.fan.first { $0.age == result.focusAge }?.p50,
                medianAtEnd: result.fan.last?.p50,
                lifetimeTaxes: result.medianPath.years.reduce(0) { $0 + $1.totalTax },
                monthlySaving: PlanResultsMapping.monthlySaving(result.expectedPath.years),
                bridges: result.failures.bridges.map {
                    PlanBridgeFailure(name: $0.name, accessibleFromAge: $0.accessibleFromAge, share: $0.share)
                },
                failuresByAge: result.failures.byAge),
            headline: result.headline(),
            agesWithout: answer.agesWithout)

        self.init(
            plan: result.plan.id, computedAt: computedAt, mode: mode, runs: result.settings.runs, engine: result.engine,
            headline: RetirementAnswer(
                confidence: answer.confidence, earliestAge: answer.earliestAge, earliestDate: answer.earliestDate,
                targetAge: answer.targetAge, successAtTarget: answer.successAtTarget,
                successToday: answer.successIfRetiringNow,
                sustainableSpending: answer.sustainableSpending.map { Decimal(wholeNumber: $0.perYear, rounding: .down) },
                readiness: answer.readiness,
                readinessIsLowerBound: answer.assetsNeeded?.outcome == .atMost,
                needsMoreThanSearched: answer.assetsNeeded?.outcome == .moreThanMaximum,
                canRetireNow: answer.canRetireNow),
            successByAge: result.successCurve.map { SuccessPoint(age: $0.age, success: $0.success) },
            portfolio: PlanResultsMapping.fan(result),
            markers: PlanResultsMapping.markers(result.markers, birthDate: birthDate,
                                                retirementDate: focus?.retirementDate),
            income: PlanResultsMapping.income(medianRetired),
            taxes: PlanResultsMapping.taxes(medianRetired),
            spending: medianRetired.map { YearValue(year: $0.year, value: PlanResultsMapping.whole($0.spending, $0)) },
            start: BaselineStart(date: result.start.date, value: result.start.planAssets),
            accounts: result.start.accounts,
            years: baseline.years,
            details: details,
            currency: result.currency)
    }

    /// These results with the charts and details of `focused`, a run of the
    /// same plan for another retirement age: the headline and the success
    /// curve stay, everything that depends on the retirement age changes.
    public func withFocus(of focused: PlanResults) -> PlanResults {
        var merged = self
        merged.portfolio = focused.portfolio
        merged.markers = focused.markers
        merged.income = focused.income
        merged.taxes = focused.taxes
        merged.spending = focused.spending
        let focus = focused.details.focus
        merged.details.focus = focus
        merged.details.focus.success = successByAge.first { $0.age == focus.age }?.success ?? focus.success
        merged.details.issues = details.issues + focused.details.issues.filter { !details.issues.contains($0) }
        return merged
    }

    /// What one unit of the results' money is in `currency`: 1 when they're
    /// in it, else (results calculated before the base currency changed) the
    /// exchange rate on the plan's start date, as the planner valued the
    /// starting portfolio (both are today's money); `nil` without a rate.
    public func exchangeRate(into currency: CurrencyCode, valuator: Valuator) -> Double? {
        guard self.currency != currency else { return 1 }
        return valuator.fx.quote(from: self.currency, to: currency, on: start.date)?.convert(1).doubleValue
    }

    /// The fan in `currency` (``exchangeRate(into:valuator:)``): what the
    /// Overview's projection, the plan's chapters and the milestones ahead
    /// read, in the base currency (*More charts* shows the results in their
    /// own). Empty without a rate.
    public func portfolio(in currency: CurrencyCode, valuator: Valuator) -> [FanPoint] {
        guard self.currency != currency else { return portfolio }
        guard let rate = exchangeRate(into: currency, valuator: valuator) else { return [] }
        return portfolio.map {
            FanPoint(date: $0.date, p10: $0.p10 * rate, p25: $0.p25 * rate, p50: $0.p50 * rate, p75: $0.p75 * rate,
                     p90: $0.p90 * rate)
        }
    }

    /// The answer with the sustainable spending in `currency`, as the
    /// Overview and the widgets show it: converted at
    /// ``exchangeRate(into:valuator:)`` for results calculated before the
    /// base currency changed, and left out without that rate, as the
    /// milestones and the chapters leave their money out.
    public func answer(in currency: CurrencyCode, valuator: Valuator) -> RetirementAnswer {
        var answer = headline
        let rate = exchangeRate(into: currency, valuator: valuator)
        answer.sustainableSpending = rate.flatMap { rate in
            headline.sustainableSpending.map {
                rate == 1 ? $0 : Decimal(wholeNumber: $0.doubleValue * rate, rounding: .down)
            }
        }
        return answer
    }
}
