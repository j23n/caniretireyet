import Foundation
import Model
import Planner
import TaxKit

// From the Planner's `PlanResult` to the app's `PlanResults`: plain values
// that feed the chart components and the Plan screens directly. Pure
// functions, so they're tested on Linux like the rest of the stores.

/// What the Planner adds to ``PlanResults`` beyond the charts: the numbers
/// the Plan screens show next to them (key numbers, "When it fails", the
/// what-if's starting values, comparing plans) and the run's warnings.
/// `nil` in results from ``PreviewPlanEngine``.
struct PlanResultDetails: Hashable, Sendable {
    /// `Planner.planHash` of the plan as it ran (with any what-if applied).
    var planHash: String
    /// Age on the start date.
    var currentAge: Int
    /// The last age the plan funds.
    var endAge: Int
    var birthDate: CalendarDate
    /// The old rule of thumb: the spending your pensions don't cover, over
    /// a 4% withdrawal rate. Kept for compatibility, never shown: Results
    /// show ``assetsNeeded`` instead.
    var fiNumber: Double?
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
    /// Where the success curve steps because a pension's start changes.
    var pensionSteps: [PlanPensionStep]
    /// Warnings from the plan, the tax systems and the years assessed.
    var issues: [PlanIssue]
    /// The details that depend on the retirement age the charts are for.
    var focus: PlanFocusDetails
    /// The headline to record for this run (`PlanResult.headline()`, dated
    /// the check-in the plan started from): success rates to 3 decimals, FI
    /// progress and readiness to 2, exactly as the CLI records it.
    var headline: Headline? = nil
    /// How the plan read your library: the buckets it grouped the accounts
    /// into, and the accounts that start a pension scheme.
    var reading: PlanLibraryReading? = nil
}

/// How a plan read your library (PLANNER.md, "Buckets", and "Accounts that
/// hold a scheme's record" in TAXES.md): the accounts grouped by tax
/// wrapper, with their value on the start date, and the accounts whose value
/// became a pension scheme's starting balance instead of money to draw on.
struct PlanLibraryReading: Hashable, Sendable {
    /// Accounts with one wrapper.
    struct Bucket: Hashable, Sendable {
        /// The wrapper's name, e.g. "Pension fund".
        var name: String
        /// Drawn any time (taxable), or by the wrapper's rules.
        var isLiquid: Bool
        /// Whether new savings go here.
        var receivesSavings: Bool
        /// Its value on the start date, in the plan's currency.
        var value: Double
        var accounts: [AccountID]
    }

    /// Accounts that start a pension scheme (`PlanStart.schemeSeeds`).
    struct Seed: Hashable, Sendable {
        /// The scheme's ID and name, e.g. `ch.bvg`, "BVG".
        var scheme: String
        var name: String
        var accounts: [AccountID]
        /// Their value on the start date, in the plan's currency.
        var value: Double
        /// Whether it became the pension's starting balance (`false` when
        /// the plan sets one itself).
        var used: Bool
    }

    /// The check-in the plan started from.
    var date: CalendarDate
    var buckets: [Bucket]
    var seeds: [Seed]

    init(date: CalendarDate, buckets: [Bucket] = [], seeds: [Seed] = []) {
        self.date = date
        self.buckets = buckets
        self.seeds = seeds
    }

    /// From a Planner result.
    init(_ start: PlanStart) {
        self.init(
            date: start.date,
            buckets: start.buckets.map {
                Bucket(name: PlanResultsMapping.shortName($0.name), isLiquid: $0.category == .taxable,
                       receivesSavings: $0.receivesSavings, value: $0.value, accounts: $0.accounts)
            },
            seeds: start.schemeSeeds.map {
                Seed(scheme: $0.scheme, name: PlanResultsMapping.shortName($0.name), accounts: $0.accounts,
                     value: $0.value, used: $0.used)
            })
    }
}

/// The numbers that belong to one retirement age: the fan, paths and
/// failures of the run are for it (`PlanResult.focusAge`).
struct PlanFocusDetails: Hashable, Sendable {
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
    /// Net income per year in the deterministic run: work and pensions,
    /// after taxes and social contributions (whole-year amounts).
    var netIncome: [YearValue]
    /// Each pension: when it starts and how much it pays a year.
    var pensions: [PlanPensionStart]
    /// Saving per month while working in the deterministic run: the
    /// what-if's starting value. `nil` when the plan has no working years.
    var monthlySaving: Decimal?
    /// Bridge failures (running out before locked money opens), most frequent first.
    var bridges: [PlanBridgeFailure]
}

/// A pension in the results.
struct PlanPensionStart: Hashable, Sendable {
    /// The pension's position in the plan's `pensions`.
    var index: Int
    var name: String
    /// The scheme, e.g. `it.inps` or `fixed`.
    var scheme: String
    /// The age it starts at, if it starts within the plan.
    var age: Int?
    /// The gross amount of a whole year when it starts, in today's money
    /// (a pension starting mid-year pays less in its first calendar year).
    var perYear: Double?
}

/// A step in the success curve: at `age`, retiring a year later changes
/// when these pensions start.
struct PlanPensionStep: Hashable, Sendable {
    var age: Int
    var pensions: [String]
}

/// Runs that ran out before one wrapper became accessible.
struct PlanBridgeFailure: Hashable, Sendable {
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
    init(result: PlanResult, mode: PlanRunMode, birthDate: CalendarDate, registry: TaxRegistry?,
         scansEveryAge: Bool, computedAt: Date = Date()) {
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
                sustainableSpending: answer.sustainableSpending.map { Decimal(Int($0.perYear.rounded(.down))) },
                fiProgress: answer.fiProgress, readiness: answer.readiness,
                needsMoreThanSearched: answer.assetsNeeded?.outcome == .moreThanMaximum,
                readinessIsLowerBound: answer.assetsNeeded?.outcome == .atMost),
            successByAge: result.successCurve.map { SuccessPoint(age: $0.age, success: $0.success) },
            portfolio: PlanResultsMapping.fan(result),
            markers: PlanResultsMapping.markers(result, birthDate: birthDate, retirementDate: focus?.retirementDate),
            income: PlanResultsMapping.income(medianRetired, plan: plan, registry: registry),
            taxes: PlanResultsMapping.taxes(medianRetired),
            spending: medianRetired.map { YearValue(year: $0.year, value: PlanResultsMapping.whole($0.spending, $0)) },
            failure: PlanResultsMapping.failure(result.failures),
            start: BaselineStart(date: result.start.date, value: result.start.planAssets),
            accounts: result.start.accounts,
            taxParameters: Dictionary(uniqueKeysWithValues: result.taxParameters.map { (TaxSystemID($0.key), $0.value) }),
            years: baseline.years)
        details = PlanResultDetails(
            planHash: result.planHash, currentAge: answer.currentAge, endAge: result.settings.endAge,
            birthDate: birthDate, fiNumber: answer.fiNumber, assetsNeeded: answer.assetsNeeded,
            sustainableSpendingAge: answer.sustainableSpending?.age, scansEveryAge: scansEveryAge,
            pensionSteps: PlanResultsMapping.pensionSteps(result.successCurve, plan: plan, registry: registry),
            issues: result.issues,
            focus: PlanFocusDetails(
                age: result.focusAge, retirementDate: focus?.retirementDate, success: focus?.success,
                medianAtRetirement: result.fan.first { $0.age == result.focusAge }?.p50,
                medianAtEnd: result.fan.last?.p50,
                lifetimeTaxes: result.medianPath.years.reduce(0) { $0 + $1.totalTax },
                netIncome: PlanResultsMapping.netIncome(result.expectedPath.years),
                pensions: PlanResultsMapping.pensions(result, plan: plan, registry: registry),
                monthlySaving: PlanResultsMapping.monthlySaving(result.expectedPath.years),
                bridges: result.failures.bridges.map {
                    PlanBridgeFailure(name: $0.name, accessibleFromAge: $0.accessibleFromAge, share: $0.share)
                }),
            headline: result.headline(),
            reading: PlanLibraryReading(result.start))
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

/// The pieces of ``PlanResults/init(result:mode:birthDate:registry:scansEveryAge:computedAt:)``.
enum PlanResultsMapping {
    /// The categories retirement income is stacked by, bottom first (UI.md,
    /// "Retirement income"). Each has its own colour slot, in the same order,
    /// so neighbours in the stack are neighbours in the validated palette.
    enum IncomeCategory: Hashable, Sendable {
        case withdrawals
        case work
        /// The plan's first public pension scheme, e.g. INPS. Another
        /// scheme's pension counts as one of the other pensions.
        case scheme(String)
        case otherPensions
        /// Money drawn as needed from tax-advantaged wrappers, e.g. a pension fund.
        case pensionSavings
        case windfalls
        /// Paid whether it's needed or not: a pension's lump sum in the year
        /// it's claimed, severance pay when a job ends (Italy's TFR), and
        /// payouts a wrapper's rules ask for (the whole balance at an age, or
        /// spread over a few years).
        case lumpSums
        case other

        /// The stacking order, bottom first, and the colour slot.
        var sortKey: Int {
            switch self {
            case .withdrawals: 0
            case .work: 1
            case .scheme: 2
            case .otherPensions: 3
            case .pensionSavings: 4
            case .windfalls: 5
            case .lumpSums: 6
            case .other: 7
            }
        }

        /// One-off amounts, which may run off the top of the chart.
        var isOneOff: Bool {
            self == .windfalls || self == .lumpSums
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

    /// A pension's or wrapper's name without the explanation in brackets:
    /// "INPS (contributory system)" → "INPS".
    static func shortName(_ name: String) -> String {
        guard let bracket = name.range(of: " (") else { return name }
        let short = name[..<bracket.lowerBound].trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? name : short
    }

    static func markers(_ result: PlanResult, birthDate: CalendarDate, retirementDate: CalendarDate?) -> [ChartMarker] {
        markers(result.markers, birthDate: birthDate, retirementDate: retirementDate)
    }

    /// The planner's markers on the time axis: "Retire at 55", "INPS 67",
    /// "Pension fund 57", "Inheritance 62", "New car 2031", each with its
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

    /// The pension a plan's `pension-N` ID stands for.
    static func planPension(id: String, in plan: PlanDocument) -> (index: Int, pension: PlanPension)? {
        guard id.hasPrefix("pension-"), let index = Int(id.dropFirst("pension-".count)),
              plan.pensions.indices.contains(index) else { return nil }
        return (index, plan.pensions[index])
    }

    /// The name the planner gives a pension: its own, or its scheme's.
    static func pensionName(_ pension: PlanPension, registry: TaxRegistry?) -> String {
        if let name = pension.name { return name }
        if pension.scheme == .fixed { return "Pension" }
        return registry?.pensionScheme(pension.scheme.rawValue)?.name ?? pension.scheme.rawValue
    }

    /// The suffix of a pension's lump sum's ID (`pension-0.lumpSum`): the
    /// planner pays it once, in the year the pension is claimed.
    static let lumpSumSuffix = ".lumpSum"

    static func category(of item: IncomeItem, plan: PlanDocument, registry: TaxRegistry? = nil) -> IncomeCategory {
        switch item.kind {
        case .withdrawal: return .withdrawals
        case .pension:
            if item.id.hasSuffix(lumpSumSuffix) { return .lumpSums }
            guard let found = planPension(id: item.id, in: plan) else { return .otherPensions }
            return found.pension.scheme == .fixed ? .otherPensions : .scheme(found.pension.scheme.rawValue)
        case .payout:
            guard let rule = registry?.wrapper(item.id) else { return .pensionSavings }
            return paysOutByRule(rule) ? .lumpSums : .pensionSavings
        case .windfall: return .windfalls
        case .work: return .work
        default: return .other
        }
    }

    /// Whether a wrapper's money is paid out whether it's needed or not:
    /// severance pay when a job ends, a balance its rules pay out whole at
    /// some point (`mustPayOut`), or payouts spread over a few years
    /// (`preferredPayoutYears`).
    static func paysOutByRule(_ rule: WrapperRule) -> Bool {
        rule.mustPayOut != nil || (rule.preferredPayoutYears ?? 0) > 0 || AccountWrapperDefaults.isPaidWhenJobEnds(rule)
    }

    /// What an income item is called in the chart's legend: a pension's lump
    /// sum by its pension ("BVG lump sum"), anything else by its own label,
    /// without the explanation in brackets.
    static func sourceName(of item: IncomeItem, plan: PlanDocument, registry: TaxRegistry?) -> String {
        if item.kind == .pension, item.id.hasSuffix(lumpSumSuffix),
           let found = planPension(id: String(item.id.dropLast(lumpSumSuffix.count)), in: plan) {
            return "\(shortName(pensionName(found.pension, registry: registry))) lump sum"
        }
        return shortName(item.label)
    }

    /// A category's label. Pension savings and lump sums take the name of
    /// their one source when they have one ("Pension fund", "TFR"), else
    /// a name for all of them.
    static func label(of category: IncomeCategory, registry: TaxRegistry?, sources: Set<String> = []) -> String {
        switch category {
        case .withdrawals: "Withdrawals"
        case .scheme(let id): shortName(registry?.pensionScheme(id)?.name ?? id)
        case .otherPensions: "Other pensions"
        case .pensionSavings: sources.count == 1 ? sources.first! : "Pension savings"
        case .lumpSums: sources.count == 1 ? sources.first! : "Lump sums and payouts"
        case .windfalls: "Windfalls"
        case .work: "Work"
        case .other: "Other"
        }
    }

    /// Each category's colour slot: its place in the stack, so the stack runs
    /// through the palette in its validated order (withdrawals blue, work
    /// orange, the public pension aqua, other pensions yellow, pension
    /// savings magenta, windfalls green, lump sums and payouts violet, other
    /// red). The taxes on top are a neutral grey (``ChartColor/taxes``):
    /// they're not a source.
    static func color(of category: IncomeCategory) -> ChartColor {
        .series(category.sortKey)
    }

    /// Retirement income per year by source, bottom first, with the taxes
    /// it pays on top (UI.md, "Retirement income").
    ///
    /// The planner reports income gross: a withdrawal is what's sold,
    /// before the tax withheld on the sale, and it also pays last year's
    /// wealth tax and tax on interest. So a year's income reaches spending
    /// plus taxes, which in a rich run's later years can be twice the
    /// spending. To read right against the spending line, each source is
    /// shown after its share of the year's taxes (``paidFromIncome(_:)``,
    /// shared in proportion to the amounts), keeping its gross amount in
    /// `gross`, and the taxes are a segment of their own on top: the
    /// sources add up to spending, expenses and what's saved, and the stack
    /// to that plus taxes.
    static func income(_ years: [YearDetail], plan: PlanDocument, registry: TaxRegistry?) -> [IncomeSegment] {
        let firstScheme = plan.pensions.first { $0.scheme != .fixed }?.scheme.rawValue
        func category(_ item: IncomeItem) -> IncomeCategory {
            let category = self.category(of: item, plan: plan, registry: registry)
            if case .scheme(let id) = category, id != firstScheme { return .otherPensions }
            return category
        }
        // The names behind each category over all the years, so a category
        // keeps one label (its single source's, else a general one).
        var sources: [IncomeCategory: Set<String>] = [:]
        for year in years {
            for item in year.income where item.amount > 0.5 {
                sources[category(item), default: []].insert(sourceName(of: item, plan: plan, registry: registry))
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
                    year: year.year, source: label(of: category, registry: registry, sources: sources[category] ?? []),
                    amount: amount * share, color: color(of: category), isOneOff: category.isOneOff, gross: amount))
            }
            if taxes > 0.5 {
                segments.append(IncomeSegment(year: year.year, source: taxesLabel, amount: taxes, color: .taxes))
            }
        }
        return segments
    }

    /// What a year's income pays in taxes and social contributions: on work
    /// and pensions, the tax withheld on what's sold and paid out, and the
    /// market taxes of the year before (wealth tax, tax on interest), which
    /// are paid in this one. Taxes on rebalancing are paid inside the
    /// portfolio and aren't in it. Worked out from the year's flows: the
    /// income from outside the plan's accounts (work, pensions, windfalls),
    /// less spending, expenses and what was saved.
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

    /// Net income per year: work and pensions, less taxes and contributions.
    static func netIncome(_ years: [YearDetail]) -> [YearValue] {
        years.map { year in
            let gross = year.income.filter { $0.kind == .work || $0.kind == .pension }.reduce(0) { $0 + $1.amount }
            return YearValue(year: year.year, value: whole(gross - year.totalTax - year.totalContributions, year))
        }
    }

    /// Saving per month in the first working year (a whole one if there is one).
    static func monthlySaving(_ years: [YearDetail]) -> Decimal? {
        let working = years.filter { $0.workingShare > 0 }
        guard let year = working.first(where: { $0.workingShare > 0.999 && $0.fraction > 0.999 }) ?? working.first
        else { return nil }
        let share = year.fraction * year.workingShare
        guard share > 0.01 else { return nil }
        return Decimal(Int((year.savings / share / 12).rounded()))
    }

    /// Each pension of the plan with its start at the focus age, from the
    /// success curve and the markers.
    static func pensions(_ result: PlanResult, plan: PlanDocument, registry: TaxRegistry?) -> [PlanPensionStart] {
        let starts = result.successCurve.first { $0.age == result.focusAge }?.pensionStartAges ?? [:]
        return plan.pensions.enumerated().map { index, pension in
            let name = pensionName(pension, registry: registry)
            let age = starts["pension-\(index)"]
            let marker = result.markers.first { $0.kind == .pensionStart && $0.label == name && (age == nil || $0.age == age) }
            return PlanPensionStart(index: index, name: name, scheme: pension.scheme.rawValue, age: age ?? marker?.age,
                                    perYear: marker?.amount)
        }
    }

    /// The ages where retiring a year later changes when a pension starts.
    static func pensionSteps(_ curve: [AgeSuccess], plan: PlanDocument, registry: TaxRegistry?) -> [PlanPensionStep] {
        let sorted = curve.sorted { $0.age < $1.age }
        var steps: [PlanPensionStep] = []
        for (previous, next) in zip(sorted, sorted.dropFirst()) where next.age == previous.age + 1 {
            let changed = Set(previous.pensionStartAges.keys).union(next.pensionStartAges.keys)
                .filter { previous.pensionStartAges[$0] != next.pensionStartAges[$0] }
                .sorted()
            guard !changed.isEmpty else { continue }
            let names = changed.map { id in
                planPension(id: id, in: plan).map { shortName(pensionName($0.pension, registry: registry)) } ?? id
            }
            steps.append(PlanPensionStep(age: next.age, pensions: names))
        }
        return steps
    }
}
