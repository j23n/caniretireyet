import Foundation
import Glance
import Model
import Planner

// The words and numbers of the plan's results (UI.md, "The plan"), from
// `PlanResults`. Plain Swift, so it's tested without SwiftUI; amounts are
// `AmountSentence`s, so they hide with the eye.

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

    /// "Needed to stop today" on its tile: the amount, or words
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
