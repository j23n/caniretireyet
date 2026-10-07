import Foundation
import Model
import Planner
import Tracker

/// A plan's milestones as the screens show them (UI.md, "Milestones";
/// PROGRESS.md, "Milestones"): those its plan assets reached, those its
/// median future reaches, and the next with how far there.
struct PlanMilestones {
    let ladder: MilestoneLadder
    /// Oldest first.
    let reached: [ReachedMilestone]
    /// Soonest first; empty without results.
    let ahead: [ProjectedMilestone]
    let next: NextMilestone?
    /// The coast age now (PLANNER.md, "Ages without"): from the results
    /// shown, else the latest check-in's record; `nil` when no age works
    /// saving nothing more, or when it isn't known (``knowsCoastAge``).
    let coastAge: Int?
    /// Whether ``coastAge`` is known: a run looked for it, or a check-in recorded one.
    let knowsCoastAge: Bool

    /// - Parameters:
    ///   - results: the plan's results shown, for what retiring today needs
    ///     and the median future; without them, nothing is ahead.
    ///   - known: those reached, when already worked out (Progress keeps
    ///     them, ``PlanProgressModel``), or `[]` where only what's ahead
    ///     shows (the Plan screen, the widget). `nil` works them out, which
    ///     values plan assets at every month since the first record.
    init(plan: PlanDocument, library: Library, valuator: Valuator, asOf: CalendarDate, results: PlanResults?,
         reached known: [ReachedMilestone]? = nil) {
        let recorded = library.headlines(for: plan.id).filter { $0.date <= asOf }.max { $0.date < $1.date }
        let readiness = results?.headline.readiness.map(Self.share) ?? recorded?.readiness
        let needed = results?.details?.assetsNeeded?.amount.map { Decimal(wholeNumber: $0) }
        let ladder = MilestoneLadder(plan: plan, library: library, on: asOf, neededToday: needed)
        self.ladder = ladder
        reached = known ?? ladder.reached(plan: plan.id, library: library, valuator: valuator, through: asOf)
        let current: Decimal
        let median: [SeriesPoint]
        if let results, let start = results.portfolio.first {
            current = Decimal(wholeNumber: start.p50)
            median = results.portfolio.map {
                SeriesPoint(date: CalendarDate($0.date, in: .current), value: Decimal(wholeNumber: $0.p50))
            }
        } else {
            current = valuator.total(on: asOf, in: .planAssets).total
            median = []
        }
        ahead = ladder.ahead(of: current, readiness: readiness, median: median)
        next = ladder.next(after: current, readiness: readiness)
        if let coast = results?.details?.coast {
            coastAge = coast.earliestAge
            knowsCoastAge = true
        } else if let age = recorded?.coastAge {
            coastAge = age
            knowsCoastAge = true
        } else {
            coastAge = nil
            knowsCoastAge = false
        }
    }

    /// When the median future reaches the next milestone; `nil` without
    /// results, or when it never does.
    var nextDate: CalendarDate? {
        guard let next else { return nil }
        return ahead.first { $0.id == next.milestone.id }?.date
    }

    /// The milestones reached by a check-in on `date`: on its day, and at
    /// the ends of the months since the check-in before (`previous`), which
    /// are valued from what you held and its prices.
    func reached(since previous: CalendarDate?, through date: CalendarDate) -> [ReachedMilestone] {
        reached.filter { milestone in
            guard milestone.date <= date else { return false }
            guard let previous else { return milestone.date == date }
            return milestone.date > previous
        }
    }

    /// The coast point, when a check-in reached it; `nil` if none did.
    var coastPointReached: ReachedMilestone? {
        reached.last { if case .coastPoint = $0.milestone.kind { true } else { false } }
    }

    /// A share as the headline records it: rounded down to whole percent.
    static func share(_ value: Double) -> Decimal {
        Decimal(Int(wholeNumber: value * 100, rounding: .down)) / 100
    }
}

/// Milestones in words (UI.md, "Milestones"). Amounts hide with the eye.
struct PlanMilestoneText {
    var currency: CurrencyCode
    var hidesAmounts = false
    var locale: Locale = .current

    private func amount(_ value: Decimal) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(value, currency: currency, locale: locale)
    }

    /// What it is, for lists and the next one: "300.000 €", "10 years of
    /// spending", "Half of what retiring today needs", "The crossover".
    func name(_ milestone: Milestone) -> String {
        switch milestone.kind {
        case .roundAmount:
            return hidesAmounts ? "A round amount" : amount(milestone.amount)
        case .yearsOfSpending(let years):
            return years == 1 ? "A year of spending" : "\(years) years of spending"
        case .shareOfNeeded(let numerator, let denominator):
            return Self.shareName(numerator, denominator) + " of what retiring today needs"
        case .crossover:
            return "The crossover"
        case .coastPoint:
            return "The coast point"
        }
    }

    /// Its name on a graph, short: "300.000 €", "10 years of spending", "A
    /// quarter of what you need", "Crossover", "Coast point".
    func label(_ milestone: Milestone) -> String {
        switch milestone.kind {
        case .roundAmount:
            return hidesAmounts ? "A round amount" : amount(milestone.amount)
        case .yearsOfSpending(let years):
            return years == 1 ? "A year of spending" : "\(years) years of spending"
        case .shareOfNeeded(let numerator, let denominator):
            return Self.shareName(numerator, denominator) + " of what you need"
        case .crossover:
            return "Crossover"
        case .coastPoint:
            return "Coast point"
        }
    }

    /// Under the next milestone: the amount its name doesn't say, and when
    /// the median future typically reaches it: "180.000 € · typically by
    /// late 2028", "Typically by mid 2027"; `nil` with neither.
    func caption(_ next: NextMilestone, date: CalendarDate?) -> String? {
        var parts: [String] = []
        switch next.milestone.kind {
        case .roundAmount, .coastPoint:
            break
        case .yearsOfSpending, .shareOfNeeded, .crossover:
            parts.append(amount(next.milestone.amount))
        }
        if let date { parts.append("typically by \(Self.when(date))") }
        guard !parts.isEmpty else { return nil }
        let text = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    /// What it means, under its name: "Enough to pay for 10 years of the
    /// spending you plan for retirement: 360.000 €."
    func detail(_ milestone: Milestone) -> String? {
        switch milestone.kind {
        case .roundAmount:
            return nil
        case .yearsOfSpending(let years):
            let span = years == 1 ? "a year" : "\(years) years"
            return "Enough to pay for \(span) of the spending you plan for retirement: \(amount(milestone.amount))."
        case .shareOfNeeded:
            return "Your plan assets against what retiring today would need."
        case .crossover:
            return "From about \(amount(milestone.amount)), a typical year's growth adds as much as you save."
        case .coastPoint(let age):
            return "Saving nothing more, you could still retire at \(age), when your first pension starts."
        }
    }

    /// The sentence when a check-in reaches it: "Passed 300.000 €.",
    /// "Halfway to what retiring today needs."
    func reached(_ milestone: Milestone) -> String {
        switch milestone.kind {
        case .roundAmount:
            return hidesAmounts ? "Passed a round amount." : "Passed \(amount(milestone.amount))."
        case .yearsOfSpending(let years):
            let span = years == 1 ? "a year" : "\(years) years"
            return "Enough for \(span) of the spending you plan for retirement."
        case .shareOfNeeded(let numerator, let denominator):
            if numerator == denominator { return "All that retiring today needs: you could stop." }
            if numerator * 2 == denominator { return "Halfway to what retiring today needs." }
            return Self.shareName(numerator, denominator) + " of what retiring today needs."
        case .crossover:
            return "A typical year now adds more than you save."
        case .coastPoint(let age):
            return "Passed the coast point: saving nothing more, you could still retire at \(age)."
        }
    }

    /// "A quarter", "A third", "Half", "Two thirds", "Three quarters",
    /// "9 in 10", "All".
    static func shareName(_ numerator: Int, _ denominator: Int) -> String {
        switch (numerator, denominator) {
        case (1, 4): "A quarter"
        case (1, 3): "A third"
        case (1, 2): "Half"
        case (2, 3): "Two thirds"
        case (3, 4): "Three quarters"
        case (let n, let d) where n == d: "All"
        case (let n, let d): "\(n) in \(d)"
        }
    }

    /// The part of the year: "early 2028", "mid 2028", "late 2028".
    static func when(_ date: CalendarDate) -> String {
        let part = date.month <= 4 ? "early" : date.month <= 8 ? "mid" : "late"
        return "\(part) \(date.year)"
    }

    /// "If you stopped saving today, you could still retire at 63; the coast
    /// point is 67, when your first pension starts."
    static func coast(_ age: Int?, target: Int?) -> String {
        guard let age else { return "If you stopped saving today, no age would reach your bar yet." }
        let could = "If you stopped saving today, you could still retire at \(age)"
        guard let target else { return could + "." }
        if age <= target {
            return could + ", by your first pension at \(target): you're past the coast point."
        }
        return could + "; the coast point is \(target), when your first pension starts."
    }

    /// Under the coast age (UI.md, "Milestones"): where it stands against
    /// the coast point, and when you reached it if you're no longer past it:
    /// "You're past the coast point: your first pension starts at 67.", "In
    /// August it was 67, when your first pension starts: the coast point.",
    /// "The coast point is 67, when your first pension starts."
    static func coastCaption(_ age: Int?, target: Int?, reached: ReachedMilestone?,
                             asOf: CalendarDate, locale: Locale = .current) -> String {
        guard let age else { return "If you stopped saving today, no age would reach your bar yet." }
        guard let target else { return "If you stopped saving today, you could still retire at \(age)." }
        if age <= target { return "You're past the coast point: your first pension starts at \(target)." }
        if let reached, case .coastPoint(let then) = reached.milestone.kind {
            let month = reached.date.year == asOf.year ? AmountFormat.monthName(reached.date, locale: locale)
                : PlanResultsText.monthYear(reached.date, locale: locale)
            return "In \(month) it was \(then), when your first pension starts: the coast point."
        }
        return "The coast point is \(target), when your first pension starts."
    }

    /// "88% there".
    func progress(_ next: NextMilestone) -> String {
        "\(AmountFormat.percent(next.progress, digits: 0, locale: locale)) there"
    }

    /// "Next milestone: 400.000 €, 88% there, typically by mid 2027."
    func nextSentence(_ next: NextMilestone, date: CalendarDate?) -> String {
        var text = "Next milestone: \(name(next.milestone)), \(progress(next))"
        if let date { text += ", typically by \(Self.when(date))" }
        return text + "."
    }
}
