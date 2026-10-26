import Foundation
import Glance
import Model
import Planner

/// Milestones in words (UI.md, "Milestones"). Amounts hide with the eye
/// (``AmountSentence``): a round amount's name is its amount, which draws as
/// a placeholder.
struct PlanMilestoneText {
    var currency: CurrencyCode
    var locale: Locale = .current

    private func amount(_ value: Decimal) -> AmountSentence {
        .amount(AmountFormat.amount(value, currency: currency, locale: locale))
    }

    /// What it is, for lists and the next one: "300.000 €", "10 years of
    /// spending", "Half of what retiring today needs", "The crossover".
    func name(_ milestone: Milestone) -> AmountSentence {
        switch milestone.kind {
        case .roundAmount:
            return amount(milestone.amount)
        case .yearsOfSpending(let years):
            return AmountSentence(years == 1 ? "A year of spending" : "\(years) years of spending")
        case .shareOfNeeded(let numerator, let denominator):
            return AmountSentence(Self.shareName(numerator, denominator) + " of what retiring today needs")
        case .crossover:
            return "The crossover"
        case .coastPoint:
            return "The coast point"
        }
    }

    /// Its name on a graph, short: "300.000 €", "10 years of spending", "A
    /// quarter of what you need", "Crossover", "Coast point".
    func label(_ milestone: Milestone) -> AmountSentence {
        switch milestone.kind {
        case .roundAmount:
            return amount(milestone.amount)
        case .yearsOfSpending(let years):
            return AmountSentence(years == 1 ? "A year of spending" : "\(years) years of spending")
        case .shareOfNeeded(let numerator, let denominator):
            return AmountSentence(Self.shareName(numerator, denominator) + " of what you need")
        case .crossover:
            return "Crossover"
        case .coastPoint:
            return "Coast point"
        }
    }

    /// Under the next milestone: the amount its name doesn't say, and when
    /// the median future typically reaches it: "180.000 € · typically by
    /// late 2028", "Typically by mid 2027"; `nil` with neither.
    func caption(_ next: NextMilestone, date: CalendarDate?) -> AmountSentence? {
        var parts: [AmountSentence] = []
        switch next.milestone.kind {
        case .roundAmount, .coastPoint:
            break
        case .yearsOfSpending, .shareOfNeeded, .crossover:
            parts.append(amount(next.milestone.amount))
        }
        if let date { parts.append(AmountSentence("typically by \(Self.when(date))")) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ").capitalizedFirst
    }

    /// What it means, under its name: "Enough to pay for 10 years of the
    /// spending you plan for retirement: 360.000 €."
    func detail(_ milestone: Milestone) -> AmountSentence? {
        switch milestone.kind {
        case .roundAmount:
            return nil
        case .yearsOfSpending(let years):
            let span = years == 1 ? "a year" : "\(years) years"
            return "Enough to pay for \(span) of the spending you plan for retirement: \(amount(milestone.amount))."
        case .shareOfNeeded:
            return "The money in your plan against what retiring today would need."
        case .crossover:
            return "From about \(amount(milestone.amount)), a typical year's growth adds as much as you save."
        case .coastPoint(let age):
            return "Saving nothing more, you could still retire at \(age), when your first pension starts."
        }
    }

    /// A kind's heading in *All Milestones*: "Round amounts", "Years of
    /// spending", "What retiring today needs", "The crossover", "The coast point".
    static func title(_ kind: PlanMilestoneKind) -> String {
        switch kind {
        case .roundAmount: "Round amounts"
        case .yearsOfSpending: "Years of spending"
        case .shareOfNeeded: "What retiring today needs"
        case .crossover: "The crossover"
        case .coastPoint: "The coast point"
        }
    }

    /// What a milestone of a kind is, as a tile's heading over its name
    /// (*Coming up* on Today): "Your plan passes" over "500.000 €", "Saved"
    /// over "10 years of spending".
    static func kindName(_ kind: Milestone.Kind) -> String {
        switch PlanMilestoneKind(kind) {
        case .roundAmount: "Your plan passes"
        case .yearsOfSpending: "Saved"
        case .shareOfNeeded: "You'll have"
        case .crossover: "Growth matches saving"
        case .coastPoint: "You could stop saving"
        }
    }

    /// What a kind means and why it matters, under its heading in *All
    /// Milestones*: "The money in your plan passing 10.000 €, 15.000 €, 20.000 €,
    /// 25.000 € and on, each about a quarter above the last: simple marks of
    /// the money growing."
    func meaning(of kind: PlanMilestoneKind, in milestones: PlanMilestones) -> AmountSentence {
        switch kind {
        case .roundAmount:
            let lowest = MilestoneLadder.roundFloor
            let first = MilestoneLadder.roundAmounts(in: lowest...(lowest * 5 / 2))
            let amounts = first.map { amount($0) }.joined(separator: ", ")
            return "The money in your plan passing \(amounts) and on, each about a quarter above the last: "
                + "simple marks of the money growing."
        case .yearsOfSpending:
            guard let spending = milestones.ladder.spending else {
                return "What you have, counted in years of the spending you plan for retirement."
            }
            return "What you have, counted in years of the \(amount(spending)) a year "
                + "you plan to spend in retirement."
        case .shareOfNeeded:
            return "The money in your plan against what retiring today would need. All of it means you could stop now."
        case .crossover:
            let growth = "a typical year's growth adds as much as you save: "
                + "from there, markets do more than your saving."
            guard let crossover = milestones.ladder.crossover
                ?? milestones.latestReached(.crossover)?.milestone.amount else {
                return AmountSentence("Where " + growth)
            }
            return "From about \(amount(crossover)), " + AmountSentence(growth)
        case .coastPoint:
            let reachedAge = milestones.coastPointReached.flatMap { reached -> Int? in
                guard case .coastPoint(let age) = reached.milestone.kind else { return nil }
                return age
            }
            guard let target = milestones.ladder.coastTarget ?? reachedAge else {
                return "When you could stop saving and still retire when your first pension starts."
            }
            return "When you could stop saving and still retire when your first pension starts, at \(target)."
        }
    }

    /// The sentence when a check-in reaches it: "Passed 300.000 €.",
    /// "Halfway to what retiring today needs."
    func reached(_ milestone: Milestone) -> AmountSentence {
        switch milestone.kind {
        case .roundAmount:
            return "Passed \(amount(milestone.amount))."
        case .yearsOfSpending(let years):
            let span = years == 1 ? "a year" : "\(years) years"
            return "Enough for \(span) of the spending you plan for retirement."
        case .shareOfNeeded(let numerator, let denominator):
            if numerator == denominator { return "All that retiring today needs: you could stop." }
            if numerator * 2 == denominator { return "Halfway to what retiring today needs." }
            return AmountSentence(Self.shareName(numerator, denominator) + " of what retiring today needs.")
        case .crossover:
            return "A typical year now adds more than you save."
        case .coastPoint(let age):
            return "Passed the coast point: saving nothing more, you could still retire at \(age)."
        }
    }

    /// The milestone in a year's row of words, where the Milestones card
    /// beside it explains the coast point: as ``reached(_:)``, but "Passed
    /// the coast point: 67."
    func reachedInRow(_ milestone: Milestone) -> AmountSentence {
        if case .coastPoint(let age) = milestone.kind { return "Passed the coast point: \(age)." }
        return reached(milestone)
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
        guard let age else { return "If you stopped saving today, no age would work out yet." }
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
        guard let age else { return "If you stopped saving today, no age would work out yet." }
        guard let target else { return "If you stopped saving today, you could still retire at \(age)." }
        if age <= target { return "You're past the coast point: your first pension starts at \(target)." }
        if let reached, case .coastPoint(let then) = reached.milestone.kind {
            let month = GlanceText.month(reached.date, relativeTo: asOf, locale: locale)
            return "In \(month) it was \(then), when your first pension starts: the coast point."
        }
        return "The coast point is \(target), when your first pension starts."
    }

    /// "88% there".
    func progress(_ next: NextMilestone) -> String {
        "\(AmountFormat.percent(next.progress, digits: 0, locale: locale)) there"
    }
}
