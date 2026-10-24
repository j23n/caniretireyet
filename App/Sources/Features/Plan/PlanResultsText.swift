import Foundation
import Glance
import Model
import Planner

// The words and numbers of the plan's results (UI.md, "The plan"), from
// `PlanResults`. Plain Swift, so it's tested without SwiftUI; amounts are
// `AmountSentence`s, so they hide with the eye.

/// One of the key numbers, a row: "You could spend from 55 · 2.350 € a
/// month".
struct PlanKeyNumber: Hashable, Sendable, Identifiable {
    var label: String
    /// Its value; amounts and ages in it hide (``AmountSentenceText``).
    var value: AmountSentence
    /// Whether the label holds the person's data (an age), hidden in a
    /// feedback screenshot.
    var personalLabel = true

    var id: String { label }
}

enum PlanResultsText {
    // MARK: Headline

    /// "Yes." or "Not yet.".
    static func answer(_ headline: RetirementAnswer) -> String {
        headline.canRetireNow ? "Yes." : "Not yet."
    }

    /// "You could retire at 54 · March 2042", or why there's no age.
    static func earliest(_ headline: RetirementAnswer, locale: Locale = .current) -> String {
        guard let age = headline.earliestAge else { return "No retirement age reaches it yet" }
        if headline.canRetireNow { return "You could stop working today" }
        guard let date = headline.earliestDate else { return "You could retire at \(age)" }
        return "You could retire at \(age) · \(GlanceText.monthAndYear(date, locale: locale))"
    }

    /// "54 → 53" when a what-if moves the earliest age, else `nil`.
    static func change(from old: Int?, to new: Int?) -> String? {
        guard old != new else { return nil }
        return "\(old.map(String.init) ?? "none") → \(new.map(String.init) ?? "none")"
    }

    // MARK: What retiring today needs

    /// The most times today's plan assets the planner looks for, as words: "20".
    static var searchedScale: String { String(Int(AssetsNeeded.maximumScale)) }


    /// "58% of what you'd need to retire today": today's plan assets
    /// against what retiring today with the plan's confidence needs
    /// (PLANNER.md, "Assets needed to retire today"). `nil` when there's no
    /// readiness, as in answers recorded before it existed: their old
    /// "of the way to financial independence" disagreed with the chance of
    /// retiring today, so it isn't shown.
    static func readiness(_ headline: RetirementAnswer, locale: Locale = .current) -> String? {
        if headline.needsMoreThanSearched {
            return "Retiring today would need more than \(searchedScale) times the money in your plan"
        }
        guard let readiness = headline.readiness else { return nil }
        if readiness >= AssetsNeeded.maximumScale {
            return "\(searchedScale) times what you'd need to retire today, or more"
        }
        let percent = AmountFormat.percent(Readiness.shown(readiness), digits: 0, locale: locale)
        return headline.readinessIsLowerBound ? "\(percent) or more of what you'd need to retire today"
            : "\(percent) of what you'd need to retire today"
    }

    /// Under an answer recorded before readiness existed, instead of a number.
    static let readinessNotRecorded = "Calculate the plan to see how close you are to retiring today."

    /// "Needed to retire today" in the key numbers: the amount, or words
    /// when the search ended at one of its limits.
    static func neededToday(_ needed: AssetsNeeded, words: PlanWords) -> AmountSentence? {
        switch needed.outcome {
        case .found:
            return needed.amount.map { words.amount(whole($0)) }
        case .atMost:
            return needed.leavesOnlyLockedMoney ? "At most what's locked away"
                : AmountSentence("Under 1/\(searchedScale) of your money")
        case .moreThanMaximum:
            return AmountSentence("Over \(searchedScale)× your money")
        case .noPlanAssets:
            return needed.amount == 0 ? "None" : nil
        }
    }

    // MARK: Key numbers

    /// The key numbers under the chapters, a row each: what you could spend
    /// a month from the age the charts are for, and when you could stop if
    /// you saved nothing more. With `more` (the Mac and iPad, where they
    /// have a column) also when saving at last year's pace, what retiring
    /// today would need, the money at the plan's end and the taxes over a
    /// lifetime, typically, and how often the money runs out before a
    /// locked account opens. In today's money.
    static func keyNumbers(_ results: PlanResults, words: PlanWords, more: Bool = false) -> [PlanKeyNumber] {
        let headline = results.headline
        let details = results.details
        var rows: [PlanKeyNumber] = []
        if let spending = headline.sustainableSpending {
            let age = details.sustainableSpendingAge ?? headline.targetAge
            let label = age.map { more ? "Could spend from \($0)" : "You could spend from \($0)" } ?? "You could spend"
            rows.append(PlanKeyNumber(label: label, value: "\(words.monthly(spending)) a month"))
        }
        if let coast = details.agesWithout.coast {
            rows.append(PlanKeyNumber(label: more ? "Saving nothing more" : "If you stopped saving now",
                                      value: AmountSentence(coast.earliestAge.map { "stop at \($0)" } ?? "no age works"),
                                      personalLabel: false))
        }
        guard more else { return rows }
        if let pace = details.agesWithout.pace {
            rows.append(PlanKeyNumber(label: "Saving at last year's pace",
                                      value: AmountSentence(pace.earliestAge.map { "stop at \($0)" } ?? "no age works"),
                                      personalLabel: false))
        }
        if let needed = details.assetsNeeded, let value = neededToday(needed, words: words) {
            rows.append(PlanKeyNumber(label: "Needed to retire today", value: value, personalLabel: false))
        }
        if let median = details.focus.medianAtEnd {
            rows.append(PlanKeyNumber(label: "Money at \(details.endAge), typically", value: words.amount(whole(median))))
        }
        rows.append(PlanKeyNumber(label: "Lifetime taxes, typically",
                                  value: words.amount(whole(details.focus.lifetimeTaxes)), personalLabel: false))
        if let bridge = details.focus.bridges.first, let age = bridge.accessibleFromAge {
            let share = AmountFormat.percent(bridge.share, digits: 0, locale: words.locale)
            rows.append(PlanKeyNumber(label: "Runs out before \(age)", value: AmountSentence("\(share) of futures")))
        }
        return rows
    }

    /// A `Double` in whole units of the currency (0 when it isn't a number).
    static func whole(_ value: Double) -> Decimal {
        Decimal(wholeNumber: value)
    }

    /// The warnings among `issues`, each message once.
    static func warnings(_ issues: [PlanIssue]) -> [PlanIssue] {
        var seen: [PlanIssue] = []
        for issue in issues where !issue.isError && !seen.contains(where: { $0.message == issue.message }) {
            seen.append(issue)
        }
        return seen
    }
}
