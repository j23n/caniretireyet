import Foundation
import Model
import Planner
import Tracker

/// A plan's milestones as the screens show them (UI.md, "Milestones";
/// PROGRESS.md, "Milestones"): those its check-ins reached, those its
/// median future reaches, and the next with how far there.
struct PlanMilestones {
    let ladder: MilestoneLadder
    /// Oldest first.
    let reached: [ReachedMilestone]
    /// Soonest first; empty without results.
    let ahead: [ProjectedMilestone]
    let next: NextMilestone?

    /// - Parameters:
    ///   - results: the plan's results shown, for what retiring today needs
    ///     and the median future; without them, nothing is ahead.
    init(plan: PlanDocument, library: Library, valuator: Valuator, asOf: CalendarDate, results: PlanResults?) {
        let recorded = library.headlines(for: plan.id).filter { $0.date <= asOf }.max { $0.date < $1.date }
        let readiness = results?.headline.readiness.map(Self.share) ?? recorded?.readiness
        let needed = results?.details?.assetsNeeded?.amount.map { Decimal(wholeNumber: $0) }
        let ladder = MilestoneLadder(plan: plan, library: library, on: asOf, neededToday: needed)
        self.ladder = ladder
        reached = ladder.reached(plan: plan.id, library: library, valuator: valuator, through: asOf)
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
    }

    /// When the median future reaches the next milestone; `nil` without
    /// results, or when it never does.
    var nextDate: CalendarDate? {
        guard let next else { return nil }
        return ahead.first { $0.id == next.milestone.id }?.date
    }

    /// The milestones a check-in on `date` reached.
    func reached(on date: CalendarDate) -> [ReachedMilestone] {
        reached.filter { $0.date == date }
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
