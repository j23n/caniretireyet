import Foundation
import Model
import Planner

// From the Planner's `PlanResult` to the app's `PlanResults`: plain values
// that feed the chart components and the Plan screens directly. Pure
// functions, so they're tested on Linux like the rest of the stores.

/// What the Planner adds to ``PlanResults`` beyond the charts: the numbers
/// the Plan screens show next to them (key numbers, "When it fails", the
/// what-if's starting values, comparing plans) and the run's warnings.
/// `nil` in results from ``PreviewPlanEngine``.
struct PlanResultDetails: Hashable, Sendable, Codable {
    /// `Planner.planHash` of the plan as it ran (with any what-if applied).
    var planHash: String
    /// Age on the start date.
    var currentAge: Int
    /// The last age the plan funds.
    var endAge: Int
    var birthDate: CalendarDate
    /// What retiring today would need, from the same simulation (PLANNER.md,
    /// "Assets needed to retire today"): the plan assets that make retiring
    /// at today's age reach the plan's confidence. `nil` from the preview
    /// engine's older samples and runs that don't look for it (a focus age).
    var assetsNeeded: AssetsNeeded? = nil
    /// The retirement age `sustainableSpending` in the headline is for.
    var sustainableSpendingAge: Int?
    /// Whether the success curve has every age (a full run) or a coarse
    /// grid refined around the answer (a fast run).
    var scansEveryAge: Bool
    /// Warnings from the plan and the library.
    var issues: [PlanIssue]
    /// The details that depend on the retirement age the charts are for.
    var focus: PlanFocusDetails
    /// The headline to record for this run (`PlanResult.headline()`, dated
    /// the check-in the plan started from): success rates to 3 decimals,
    /// readiness to 2, exactly as the CLI records it.
    var headline: Headline? = nil
    /// The earliest age saving nothing more (the coast age) and without
    /// each uncertain windfall (PLANNER.md, "Ages without"); empty from runs
    /// that don't look for them.
    var agesWithout: [AgeWithout] = []

    /// The coast age, when the run looked for it.
    var coast: AgeWithout? { agesWithout.first { $0.change == .saving } }

    /// The earliest age without the uncertain windfall at `index` of the
    /// plan's events, when the run looked for it.
    func withoutWindfall(_ index: Int) -> AgeWithout? {
        agesWithout.first { $0.change == .windfall(index: index) }
    }
}

/// The numbers that belong to one retirement age: the fan, paths and
/// failures of the run are for it (`PlanResult.focusAge`).
struct PlanFocusDetails: Hashable, Sendable, Codable {
    /// The retirement age the fan, income and failures are for.
    var age: Int
    /// The day work stops at that age.
    var retirementDate: CalendarDate?
    /// The chance of success at that age.
    var success: Double?
    /// Median plan assets at the end of the year you retire, and at the plan's end.
    var medianAtRetirement: Double?
    var medianAtEnd: Double?
    /// All taxes in the median run, in today's money.
    var lifetimeTaxes: Double
    /// Income per year in the deterministic run: work and pensions, after
    /// tax as the plan gives them (whole-year amounts).
    var netIncome: [YearValue]
    /// Each pension: when it starts and how much it pays a year.
    var pensions: [PlanPensionStart]
    /// Saving per month while working in the deterministic run: the
    /// what-if's starting value. `nil` when the plan has no working years.
    var monthlySaving: Decimal?
    /// Bridge failures (running out before locked money opens), most frequent first.
    var bridges: [PlanBridgeFailure]
    /// How many runs run out of money at each age, ascending: where each
    /// chapter's failures are (UI.md, "The plan").
    var failuresByAge: [AgeCount] = []
}

/// A pension in the results.
struct PlanPensionStart: Hashable, Sendable, Codable {
    /// The pension's position in the plan's `pensions`.
    var index: Int
    var name: String
    /// The age it starts at.
    var age: Int?
    /// What it pays in a whole year after tax, in today's money (a pension
    /// starting mid-year pays less in its first calendar year).
    var perYear: Double?
}

/// Runs that ran out while some accounts were still locked away.
struct PlanBridgeFailure: Hashable, Sendable, Codable {
    var name: String
    var accessibleFromAge: Int?
    /// The share of all runs.
    var share: Double
}

extension PlanResults {
    /// The details, when the engine is the Planner.
    var planHash: String? { details?.planHash }

    /// When the charts' retirement happens: the focus age's retirement day,
    /// or the retirement marker's date (the preview engine has no details).
    var retirementDate: Date? {
        details?.focus.retirementDate?.dateValue
            ?? markers.first { $0.kind == .retirement || $0.systemImage == "figure.walk" }?.date
    }

    /// Results from a Planner run.
    ///
    /// - The fan starts at the check-in's value, then has one point per year-end.
    /// - Markers sit on the birthday in their year, so "retire at 55" is drawn where you turn 55.
    /// - Income, taxes and spending are the median run's retirement years (the year you
    ///   retire included), as whole-year amounts.
    init(result: PlanResult, mode: PlanRunMode, birthDate: CalendarDate, scansEveryAge: Bool,
         computedAt: Date = Date()) {
        let answer = result.answer
        let plan = result.plan
        let focus = result.successCurve.first { $0.age == result.focusAge }
        let baseline = result.baseline(created: result.start.date, kind: .manual)
        let medianRetired = result.medianPath.years.filter { $0.workingShare < 1 }

        self.init(
            plan: plan.id, computedAt: computedAt, mode: mode, runs: result.settings.runs, engine: result.engine,
            headline: PlanHeadline(
                confidence: answer.confidence, earliestAge: answer.earliestAge, earliestDate: answer.earliestDate,
                targetAge: answer.targetAge, successAtTarget: answer.successAtTarget,
                successToday: answer.successIfRetiringNow,
                sustainableSpending: answer.sustainableSpending.map { Decimal(wholeNumber: $0.perYear, rounding: .down) },
                readiness: answer.readiness,
                needsMoreThanSearched: answer.assetsNeeded?.outcome == .moreThanMaximum,
                readinessIsLowerBound: answer.assetsNeeded?.outcome == .atMost),
            successByAge: result.successCurve.map { SuccessPoint(age: $0.age, success: $0.success) },
            portfolio: PlanResultsMapping.fan(result),
            markers: PlanResultsMapping.markers(result, birthDate: birthDate, retirementDate: focus?.retirementDate),
            income: PlanResultsMapping.income(medianRetired),
            taxes: PlanResultsMapping.taxes(medianRetired),
            spending: medianRetired.map { YearValue(year: $0.year, value: PlanResultsMapping.whole($0.spending, $0)) },
            failure: PlanResultsMapping.failure(result.failures),
            start: BaselineStart(date: result.start.date, value: result.start.planAssets),
            accounts: result.start.accounts,
            years: baseline.years)
        details = PlanResultDetails(
            planHash: result.planHash, currentAge: answer.currentAge, endAge: result.settings.endAge,
            birthDate: birthDate, assetsNeeded: answer.assetsNeeded,
            sustainableSpendingAge: answer.sustainableSpending?.age, scansEveryAge: scansEveryAge,
            issues: result.issues,
            focus: PlanFocusDetails(
                age: result.focusAge, retirementDate: focus?.retirementDate, success: focus?.success,
                medianAtRetirement: result.fan.first { $0.age == result.focusAge }?.p50,
                medianAtEnd: result.fan.last?.p50,
                lifetimeTaxes: result.medianPath.years.reduce(0) { $0 + $1.totalTax },
                netIncome: PlanResultsMapping.netIncome(result.expectedPath.years),
                pensions: PlanResultsMapping.pensions(plan),
                monthlySaving: PlanResultsMapping.monthlySaving(result.expectedPath.years),
                bridges: result.failures.bridges.map {
                    PlanBridgeFailure(name: $0.name, accessibleFromAge: $0.accessibleFromAge, share: $0.share)
                },
                failuresByAge: result.failures.byAge),
            headline: result.headline(),
            agesWithout: answer.agesWithout)
        currency = result.currency
    }

    /// These results with the charts and details of `focused`, a run of the
    /// same plan for another retirement age: the headline and the success
    /// curve stay, everything that depends on the retirement age changes.
    func withFocus(of focused: PlanResults) -> PlanResults {
        var merged = self
        merged.portfolio = focused.portfolio
        merged.markers = focused.markers
        merged.income = focused.income
        merged.taxes = focused.taxes
        merged.spending = focused.spending
        merged.failure = focused.failure
        if let focus = focused.details?.focus {
            merged.details?.focus = focus
            merged.details?.focus.success = successByAge.first { $0.age == focus.age }?.success ?? focus.success
            if let issues = focused.details?.issues, let own = merged.details?.issues {
                merged.details?.issues = own + issues.filter { !own.contains($0) }
            }
        }
        return merged
    }
}

/// The pieces of ``PlanResults/init(result:mode:birthDate:scansEveryAge:computedAt:)``.
enum PlanResultsMapping {
    /// The categories retirement income is stacked by, bottom first (UI.md,
    /// "Retirement income"). Each has its own colour slot, in the same order,
    /// so neighbours in the stack are neighbours in the validated palette.
    enum IncomeCategory: Hashable, Sendable {
        case withdrawals
        case work
        case pensions
        case windfalls
        case other

        /// The stacking order, bottom first, and the colour slot.
        var sortKey: Int {
            switch self {
            case .withdrawals: 0
            case .work: 1
            case .pensions: 2
            case .windfalls: 5
            case .other: 7
            }
        }

        /// One-off amounts, which may run off the top of the chart.
        var isOneOff: Bool {
            self == .windfalls
        }
    }

    /// The label of the taxes on top of retirement income.
    static let taxesLabel = "Taxes"

    /// The fan in today's money: the start value, then each year-end.
    static func fan(_ result: PlanResult) -> [FanPoint] {
        let start = result.start.planAssets.doubleValue
        var points = [FanPoint(date: result.start.date.dateValue, p10: start, p25: start, p50: start, p75: start,
                               p90: start)]
        for year in result.fan {
            guard let end = YearMonth(year: year.year, month: 12)?.lastDay, end > result.start.date else { continue }
            points.append(FanPoint(date: end.dateValue, p10: year.p10, p25: year.p25, p50: year.p50, p75: year.p75,
                                   p90: year.p90))
        }
        return points
    }

    /// The date of something that happens in `year` at `age`: that year's
    /// birthday, or `exact` when it's known.
    static func date(year: Int, birthDate: CalendarDate, exact: CalendarDate? = nil) -> CalendarDate {
        if let exact, exact.year == year { return exact }
        return CalendarDate(year: year, month: birthDate.month, day: min(birthDate.day, 28))
            ?? YearMonth(year: year, month: 6)?.lastDay ?? birthDate
    }

    /// A name without the explanation in brackets: "State pension (estimate)"
    /// → "State pension".
    static func shortName(_ name: String) -> String {
        guard let bracket = name.range(of: " (") else { return name }
        let short = name[..<bracket.lowerBound].trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? name : short
    }

    static func markers(_ result: PlanResult, birthDate: CalendarDate, retirementDate: CalendarDate?) -> [ChartMarker] {
        markers(result.markers, birthDate: birthDate, retirementDate: retirementDate)
    }

    /// The planner's markers on the time axis: "Retire at 55", "State pension 67",
    /// "Pension fund 67", "Inheritance 62", "New car 2031", each with its
    /// icon and kind, on its birthday (retirement on `retirementDate`).
    static func markers(_ markers: [TimelineMarker], birthDate: CalendarDate,
                        retirementDate: CalendarDate?) -> [ChartMarker] {
        markers.map { marker in
            let when = date(year: marker.year, birthDate: birthDate,
                            exact: marker.kind == .retirement ? retirementDate : nil)
            let label: String
            let symbol: String
            let kind: ChartMarker.Kind?
            switch marker.kind {
            case .retirement:
                label = "Retire at \(marker.age)"
                symbol = "figure.walk"
                kind = .retirement
            case .pensionStart:
                label = "\(shortName(marker.label)) \(marker.age)"
                symbol = "building.columns"
                kind = .pension
            case .accessible:
                label = "\(shortName(marker.label)) \(marker.age)"
                symbol = "lock.open"
                kind = .accessible
            case .windfall:
                label = "\(marker.label) \(marker.age)"
                symbol = "gift"
                kind = .windfall
            case .expense:
                label = "\(marker.label) \(marker.year)"
                symbol = "cart"
                kind = .expense
            default:
                label = marker.label
                symbol = "star"
                kind = nil
            }
            return ChartMarker(date: when.dateValue, label: label, systemImage: symbol, kind: kind)
        }
    }

    /// A year's amount for a whole year: the first year may be only the
    /// part after the check-in.
    static func whole(_ amount: Double, _ year: YearDetail) -> Double {
        year.fraction > 0.01 ? amount / year.fraction : amount
    }

    /// The name the planner gives the pension at `index` (PlanInterpreter):
    /// its own, else "Pension", or "Pension 2" when there are several.
    static func pensionName(_ pension: PlanPension, index: Int, of count: Int) -> String {
        pension.name ?? (count == 1 ? "Pension" : "Pension \(index + 1)")
    }

    static func category(of item: IncomeItem) -> IncomeCategory {
        switch item.kind {
        case .withdrawal: .withdrawals
        case .pension: .pensions
        case .windfall: .windfalls
        case .work: .work
        default: .other
        }
    }

    /// A category's label. Pensions take the name of their one source when
    /// they have one ("State pension"), else a name for all of them.
    static func label(of category: IncomeCategory, sources: Set<String> = []) -> String {
        switch category {
        case .withdrawals: "Withdrawals"
        case .pensions: sources.count == 1 ? sources.first! : "Pensions"
        case .windfalls: "Windfalls"
        case .work: "Work"
        case .other: "Other"
        }
    }

    /// Each category's colour slot: its place in the stack, so the stack runs
    /// through the palette in its validated order (withdrawals blue, work
    /// orange, pensions aqua, windfalls green, other red). The taxes on top
    /// are a neutral grey (``ChartColor/taxes``): they're not a source.
    static func color(of category: IncomeCategory) -> ChartColor {
        .series(category.sortKey)
    }

    /// Retirement income per year by source, bottom first, with the taxes
    /// it pays on top (UI.md, "Retirement income").
    ///
    /// A withdrawal is what's sold, before the tax on its gain, and the
    /// year's income also pays the wealth tax and last year's tax on
    /// investment income. So a year's income reaches spending plus taxes.
    /// To read right against the spending line, each source is
    /// shown after its share of the year's taxes (``paidFromIncome(_:)``,
    /// shared in proportion to the amounts), keeping its gross amount in
    /// `gross`, and the taxes are a segment of their own on top: the
    /// sources add up to spending, expenses and what's saved, and the stack
    /// to that plus taxes.
    static func income(_ years: [YearDetail]) -> [IncomeSegment] {
        func category(_ item: IncomeItem) -> IncomeCategory { self.category(of: item) }
        // The names behind each category over all the years, so a category
        // keeps one label (its single source's, else a general one).
        var sources: [IncomeCategory: Set<String>] = [:]
        for year in years {
            for item in year.income where item.amount > 0.5 {
                sources[category(item), default: []].insert(shortName(item.label))
            }
        }
        var segments: [IncomeSegment] = []
        for year in years {
            var gross: [IncomeCategory: Double] = [:]
            for item in year.income where item.amount > 0.5 {
                gross[category(item), default: 0] += whole(item.amount, year)
            }
            let total = gross.values.reduce(0, +)
            guard total > 0.5 else { continue }
            let taxes = min(total, whole(paidFromIncome(year), year))
            let share = (total - taxes) / total
            for category in gross.keys.sorted(by: { $0.sortKey < $1.sortKey }) {
                guard let amount = gross[category], amount * share > 0.5 else { continue }
                segments.append(IncomeSegment(
                    year: year.year, source: label(of: category, sources: sources[category] ?? []),
                    amount: amount * share, color: color(of: category), isOneOff: category.isOneOff, gross: amount))
            }
            if taxes > 0.5 {
                segments.append(IncomeSegment(year: year.year, source: taxesLabel, amount: taxes, color: .taxes))
            }
        }
        return segments
    }

    /// What a year's income pays in taxes: the tax on the gain part of
    /// what's sold, the wealth tax, and last year's tax on investment
    /// income. Worked out from the year's flows: the income from outside the
    /// plan's accounts (work, pensions, windfalls), less spending, expenses
    /// and what was saved.
    static func paidFromIncome(_ year: YearDetail) -> Double {
        let outside = year.income.filter { $0.kind == .work || $0.kind == .pension || $0.kind == .windfall }
            .reduce(0) { $0 + $1.amount }
        return max(0, outside - year.spending - year.expenses - year.savings)
    }

    /// Taxes per year by tax line, the largest lines first; beyond seven
    /// lines the rest fold into "Other taxes" (colours are never cycled).
    static func taxes(_ years: [YearDetail]) -> [IncomeSegment] {
        var totals: [String: Double] = [:]
        var labels: [String: String] = [:]
        for year in years {
            for line in year.taxes where line.amount > 0.5 {
                totals[line.id, default: 0] += whole(line.amount, year)
                labels[line.id] = line.label
            }
        }
        let ranked = totals.keys.sorted { (totals[$0]!, $1) > (totals[$1]!, $0) }
        let kept = ranked.count > 8 ? Array(ranked.prefix(7)) : ranked
        var segments: [IncomeSegment] = []
        for year in years {
            var byLine: [String: Double] = [:]
            for line in year.taxes where line.amount > 0.5 {
                let key = kept.contains(line.id) ? line.id : "other"
                byLine[key, default: 0] += whole(line.amount, year)
            }
            for (slot, id) in (kept + ["other"]).enumerated() {
                guard let amount = byLine[id], amount > 0.5 else { continue }
                segments.append(IncomeSegment(year: year.year, source: id == "other" ? "Other taxes" : labels[id] ?? id,
                                              amount: amount, color: .series(min(slot, 7))))
            }
        }
        return segments
    }

    static func failure(_ failures: FailureSummary) -> PlanFailureSummary {
        let bridge = failures.bridges.first
        return PlanFailureSummary(share: failures.failureRate, typicalAge: failures.medianFailureAge,
                                  bridgeShare: bridge?.share, bridgeAge: bridge?.accessibleFromAge,
                                  bridgeName: bridge?.name)
    }

    /// Income per year from work and pensions, after tax as the plan gives it.
    static func netIncome(_ years: [YearDetail]) -> [YearValue] {
        years.map { year in
            let net = year.income.filter { $0.kind == .work || $0.kind == .pension }.reduce(0) { $0 + $1.amount }
            return YearValue(year: year.year, value: whole(net, year))
        }
    }

    /// Saving per month in the first working year (a whole one if there is one).
    static func monthlySaving(_ years: [YearDetail]) -> Decimal? {
        let working = years.filter { $0.workingShare > 0 }
        guard let year = working.first(where: { $0.workingShare > 0.999 && $0.fraction > 0.999 }) ?? working.first
        else { return nil }
        let share = year.fraction * year.workingShare
        guard share > 0.01 else { return nil }
        return Decimal(wholeNumber: year.savings / share / 12)
    }

    /// Each pension of the plan: when it starts and what it pays a year.
    static func pensions(_ plan: PlanDocument) -> [PlanPensionStart] {
        plan.pensions.enumerated().map { index, pension in
            PlanPensionStart(index: index, name: pensionName(pension, index: index, of: plan.pensions.count),
                             age: pension.fromAge, perYear: pension.perYear?.doubleValue)
        }
    }
}
