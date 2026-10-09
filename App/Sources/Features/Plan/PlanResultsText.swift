import Foundation
import Glance
import Model
import Planner

// The words and numbers of the plan's charts (UI.md, "More charts"), from
// `PlanResults`. Plain Swift, so it's tested without SwiftUI; views add
// privacy (amounts go through `AmountText`) and colour.

/// A value in the key numbers. Amounts stay numbers so views can hide them
/// (`AmountText`).
enum PlanFigure: Hashable, Sendable {
    /// An amount in the currency of the screen (the plan's), e.g.
    /// `38.400 €`, with an optional unit after it, e.g. `/yr`.
    case amount(Decimal, unit: String?)
    /// A share, e.g. 0.92 → "92%".
    case percent(Double)
    /// Words or an age, e.g. "54 · Mar 2042".
    case text(String)
}

/// One row of a table of figures: "Needed to retire today · 1.240.000 €".
struct PlanFigureRow: Hashable, Sendable, Identifiable {
    var label: String
    var value: PlanFigure
    /// Bold, for the row that answers the question.
    var isEmphasized = false

    var id: String { label }
}

enum PlanResultsText {
    // MARK: Headline

    /// "Yes." or "Not yet.".
    static func answer(_ headline: PlanHeadline) -> String {
        headline.canRetireNow ? "Yes." : "Not yet."
    }

    /// "Earliest at 54 · March 2042", or why there's no age.
    static func earliest(_ headline: PlanHeadline, locale: Locale = .current) -> String {
        guard let age = headline.earliestAge else { return "No retirement age reaches it yet" }
        if headline.canRetireNow { return "You could stop working today" }
        guard let date = headline.earliestDate else { return "Earliest at \(age)" }
        return "Earliest at \(age) · \(GlanceText.monthAndYear(date, locale: locale))"
    }

    /// "54 → 53" when a what-if moves the earliest age, else `nil`.
    static func change(from old: Int?, to new: Int?) -> String? {
        guard old != new else { return nil }
        return "\(old.map(String.init) ?? "none") → \(new.map(String.init) ?? "none")"
    }

    // MARK: What retiring today needs

    /// The most times today's plan assets the planner looks for, as words: "20".
    static var searchedScale: String { String(Int(AssetsNeeded.maximumScale)) }

    /// The readiness as a share to show: below 100% rounded down to a whole
    /// percent, as headlines record it, so it never reads 100% while
    /// retiring today falls short.
    static func readinessShare(_ readiness: Double) -> Double {
        guard readiness < 1 else { return readiness }
        return min(0.99, max(0, Planner.recordedReadiness(readiness).doubleValue))
    }

    /// The readiness bar's value: the share, at most 100%.
    static func readinessBar(_ readiness: Double) -> Double {
        min(1, max(0, readinessShare(readiness)))
    }

    /// "58% of what you'd need to retire today": today's plan assets
    /// against what retiring today with the plan's confidence needs
    /// (PLANNER.md, "Assets needed to retire today"). `nil` when there's no
    /// readiness, as in answers recorded before it existed: their old
    /// "of the way to financial independence" disagreed with the chance of
    /// retiring today, so it isn't shown.
    static func readiness(_ headline: PlanHeadline, locale: Locale = .current) -> String? {
        if headline.needsMoreThanSearched {
            return "Retiring today would need more than \(searchedScale) times your plan assets"
        }
        guard let readiness = headline.readiness else { return nil }
        if readiness >= AssetsNeeded.maximumScale {
            return "\(searchedScale) times what you'd need to retire today, or more"
        }
        let percent = AmountFormat.percent(readinessShare(readiness), digits: 0, locale: locale)
        return headline.readinessIsLowerBound ? "\(percent) or more of what you'd need to retire today"
            : "\(percent) of what you'd need to retire today"
    }

    /// What the readiness compares, for its ⓘ.
    static func readinessExplanation(confidence: Double, locale: Locale = .current) -> String {
        let percent = AmountFormat.percent(confidence, digits: 0, locale: locale)
        return "Your plan assets compared with what retiring now would need for a \(percent) chance (the plan's "
            + "confidence), including the years before your pensions start and taxes. The plan finds it by "
            + "simulating retiring today with extra money added to the money you can draw now, or with money taken "
            + "out of it; accounts available only from a later age stay as they are. At 100% you could retire today."
    }

    /// Under an answer recorded before readiness existed, instead of a number.
    static let readinessNotRecorded = "Calculate the plan to see how close you are to retiring today."

    /// "Needed to retire today" in the key numbers: the amount, or words
    /// when the search ended at one of its limits.
    static func neededToday(_ needed: AssetsNeeded) -> PlanFigure? {
        switch needed.outcome {
        case .found:
            return needed.amount.map { .amount(whole($0), unit: nil) }
        case .atMost:
            return needed.leavesOnlyLockedMoney ? .text("At most what's locked away")
                : .text("Under 1/\(searchedScale) of your plan assets")
        case .moreThanMaximum:
            return .text("Over \(searchedScale)× your plan assets")
        case .noPlanAssets:
            return needed.amount == 0 ? .text("None") : nil
        }
    }

    // MARK: Key numbers

    /// The key numbers beside the charts (MacPlan: Earliest retirement,
    /// Success at 55, Spend at 55, Needed to retire today and the share you
    /// have, Median at 54 and 95, Lifetime taxes, Runs out before 57). The
    /// old FI number isn't among them: the amount needed today replaces it.
    static func keyNumbers(_ results: PlanResults, locale: Locale = .current) -> [PlanFigureRow] {
        let headline = results.headline
        var rows: [PlanFigureRow] = []
        if let age = headline.earliestAge {
            let date = headline.earliestDate.map { " · " + GlanceText.shortMonthAndYear($0, locale: locale) } ?? ""
            rows.append(PlanFigureRow(label: "Earliest retirement", value: .text("\(age)\(date)"), isEmphasized: true))
        } else {
            rows.append(PlanFigureRow(label: "Earliest retirement", value: .text("None yet"), isEmphasized: true))
        }
        if let target = headline.targetAge, let success = headline.successAtTarget {
            rows.append(PlanFigureRow(label: "Success at \(target) (target)", value: .percent(success)))
        }
        if let spending = headline.sustainableSpending {
            let age = results.details.sustainableSpendingAge ?? headline.targetAge
            rows.append(PlanFigureRow(label: age.map { "Spend at \($0)" } ?? "Sustainable spending",
                                      value: .amount(spending, unit: "/yr")))
        }
        let details = results.details
        if let needed = details.assetsNeeded, let figure = neededToday(needed) {
            rows.append(PlanFigureRow(label: "Needed to retire today", value: figure))
            if needed.outcome == .found, let extra = needed.extra, extra >= 0.5 {
                rows.append(PlanFigureRow(label: "Extra in accounts you can draw now",
                                          value: .amount(whole(extra), unit: nil)))
            }
            if needed.outcome == .found, let readiness = needed.readiness {
                rows.append(PlanFigureRow(label: "You have", value: .percent(readinessShare(readiness))))
            }
        }
        if let median = details.focus.medianAtRetirement {
            rows.append(PlanFigureRow(label: "Median at \(details.focus.age)", value: .amount(whole(median), unit: nil)))
        }
        if let median = details.focus.medianAtEnd {
            rows.append(PlanFigureRow(label: "Median at \(details.endAge)", value: .amount(whole(median), unit: nil)))
        }
        rows.append(PlanFigureRow(label: "Lifetime taxes, median",
                                  value: .amount(whole(details.focus.lifetimeTaxes), unit: nil)))
        if let bridge = details.focus.bridges.first, let age = bridge.accessibleFromAge {
            rows.append(PlanFigureRow(label: "Runs out before \(age)", value: .percent(bridge.share)))
        }
        if let coast = details.agesWithout.coast {
            rows.append(PlanFigureRow(label: "Saving nothing more, retire at",
                                      value: .text(coast.earliestAge.map { "\($0)" } ?? "None")))
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
