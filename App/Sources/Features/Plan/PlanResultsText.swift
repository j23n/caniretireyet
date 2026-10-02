import Foundation
import Model
import Planner

// The words and numbers of the Results screen (UI.md, "Results"), from
// `PlanResults`. Plain Swift, so it's tested without SwiftUI; views add
// privacy (amounts go through `AmountText`) and colour.

/// A value in the key numbers, the headline or the comparison table.
/// Amounts stay numbers so views can hide them (`AmountText`).
enum PlanFigure: Hashable, Sendable {
    /// An amount in the currency of the screen (the plan's), e.g.
    /// `38.400 €`, with an optional unit after it, e.g. `/yr`.
    case amount(Decimal, unit: String?)
    /// An amount in a currency of its own, e.g. one of two plans compared
    /// that are in different currencies.
    case amountIn(Decimal, currency: CurrencyCode, unit: String?)
    /// A share, e.g. 0.92 → "92%".
    case percent(Double)
    /// Words or an age, e.g. "54 · Mar 2042".
    case text(String)
    /// Nothing to show.
    case missing
}

/// One row of a table of figures: "FI number · 780.000 €".
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
        return "Earliest at \(age) · \(monthYear(date, locale: locale))"
    }

    /// "March 2042".
    static func monthYear(_ date: CalendarDate, locale: Locale = .current) -> String {
        date.dateValue.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    /// "Mar 2042".
    static func shortMonthYear(_ date: CalendarDate, locale: Locale = .current) -> String {
        date.dateValue.formatted(.dateTime.month(.abbreviated).year().locale(locale))
    }

    /// A share as the simplest "k of n": 0.9 → (9, 10), 0.95 → (19, 20), 0.75 → (3, 4).
    static func fraction(_ share: Double) -> (Int, Int) {
        for denominator in [2, 3, 4, 5, 10, 20, 25, 50, 100] {
            let numerator = share * Double(denominator)
            if abs(numerator - numerator.rounded()) < 0.001 {
                return (Int(numerator.rounded()), denominator)
            }
        }
        return (Int((share * 100).rounded()), 100)
    }

    /// The confidence in plain words: "in 9 of 10 simulated futures".
    static func confidence(_ share: Double) -> String {
        let (numerator, denominator) = fraction(share)
        return "in \(numerator) of \(denominator) simulated futures"
    }

    /// "54 → 53" when a what-if moves the earliest age, else `nil`.
    static func change(from old: Int?, to new: Int?) -> String? {
        guard old != new else { return nil }
        return "\(old.map(String.init) ?? "none") → \(new.map(String.init) ?? "none")"
    }

    /// "1 in 10", for "When it fails (1 in 10)".
    static func oneIn(_ share: Double) -> String {
        guard share > 0 else { return "none" }
        if share < 0.005 { return "fewer than 1 in 200" }
        if share <= 0.5 { return "1 in \(Int((1 / share).rounded()))" }
        return "\(Int((share * 10).rounded())) in 10"
    }

    /// "When it fails (1 in 10)".
    static func failureTitle(_ failure: PlanFailureSummary?) -> String {
        guard let failure, failure.share > 0 else { return "When it fails" }
        return "When it fails (\(oneIn(failure.share)))"
    }

    /// The sentences of "When it fails", including bridge failures.
    static func failureSentences(_ failure: PlanFailureSummary?, locale: Locale = .current) -> [String] {
        guard let failure else { return [] }
        guard failure.share > 0 else { return ["None of the simulated futures run out of money."] }
        var sentences: [String] = []
        if let age = failure.typicalAge {
            sentences.append("Money usually runs out around \(age).")
        }
        if let share = failure.bridgeShare, share > 0 {
            let percent = AmountFormat.percent(share, digits: share < 0.01 ? 1 : 0, locale: locale)
            let what = failure.bridgeName.map { "the " + lowercasedFirst($0) } ?? "locked money"
            let opens = failure.bridgeAge.map { " opens at \($0)" } ?? " opens"
            sentences.append("\(percent) of futures run out before \(what)\(opens).")
        }
        return sentences
    }

    /// "Pension fund" → "pension fund"; "TFR" stays.
    static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first, text.dropFirst().first?.isLowercase ?? true else { return text }
        return first.lowercased() + text.dropFirst()
    }

    /// "64 and 67", "64, 65 and 67".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    /// "Steps at 64 and 67: that's when INPS can start." for the success curve.
    static func pensionStepNote(_ steps: [PlanPensionStep]) -> String? {
        guard !steps.isEmpty else { return nil }
        var names: [String] = []
        for step in steps {
            for name in step.pensions where !names.contains(name) { names.append(name) }
        }
        let ages = list(steps.prefix(4).map { String($0.age) })
        return "Steps at \(ages): retiring then changes when \(list(names)) can start."
    }

    // MARK: Key numbers

    /// The key numbers beside the charts (MacPlan: Earliest retirement,
    /// Success at 55, Spend at 55, FI number, Median at 54 and 95, Lifetime
    /// taxes, Runs out before 57).
    static func keyNumbers(_ results: PlanResults, locale: Locale = .current) -> [PlanFigureRow] {
        let headline = results.headline
        var rows: [PlanFigureRow] = []
        if let age = headline.earliestAge {
            let date = headline.earliestDate.map { " · " + shortMonthYear($0, locale: locale) } ?? ""
            rows.append(PlanFigureRow(label: "Earliest retirement", value: .text("\(age)\(date)"), isEmphasized: true))
        } else {
            rows.append(PlanFigureRow(label: "Earliest retirement", value: .text("None yet"), isEmphasized: true))
        }
        if let target = headline.targetAge, let success = headline.successAtTarget {
            rows.append(PlanFigureRow(label: "Success at \(target) (target)", value: .percent(success)))
        }
        if let spending = headline.sustainableSpending {
            let age = results.details?.sustainableSpendingAge ?? headline.targetAge
            rows.append(PlanFigureRow(label: age.map { "Spend at \($0)" } ?? "Sustainable spending",
                                      value: .amount(spending, unit: "/yr")))
        }
        guard let details = results.details else { return rows }
        if let fi = details.fiNumber {
            rows.append(PlanFigureRow(label: "FI number", value: .amount(whole(fi), unit: nil)))
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
        return rows
    }

    /// A `Double` in whole units of the currency.
    static func whole(_ value: Double) -> Decimal {
        guard value.isFinite else { return 0 }
        return Decimal(Int(value.rounded()))
    }

    /// The warnings to show as banners on Results: the run's, without
    /// repeats. Errors stop a run and show as its error instead.
    static func warnings(_ results: PlanResults?) -> [String] {
        warnings(results?.details?.issues ?? [])
    }

    /// The warnings among `issues`, each message once.
    static func warnings(_ issues: [PlanIssue]) -> [String] {
        var seen: [String] = []
        for issue in issues where !issue.isError && !seen.contains(issue.message) {
            seen.append(issue.message)
        }
        return seen
    }

    // MARK: How the plan reads your library

    /// "How the plan reads your library": a line per bucket (the accounts
    /// of one tax wrapper, their value on the start date, how they're
    /// drawn), then a line per group of accounts that starts a pension
    /// scheme instead (`PlanStart.schemeSeeds`).
    static func libraryNotes(_ reading: PlanLibraryReading, accounts: [AccountID: Account],
                             locale: Locale = .current) -> [PlanLibraryNote] {
        func names(_ ids: [AccountID]) -> String {
            let all = ids.map { accounts[$0]?.name ?? $0.rawValue }
            guard all.count > 3 else { return list(all) }
            return all.prefix(3).joined(separator: ", ") + " and \(all.count - 3) more"
        }
        let date = AmountFormat.mediumDate(reading.date, locale: locale)
        var notes: [PlanLibraryNote] = []
        for bucket in reading.buckets {
            var parts = [bucket.isLiquid ? "Drawn any time" : "Drawn as its tax rules allow"]
            if bucket.receivesSavings { parts.append("new savings go here") }
            if !bucket.accounts.isEmpty { parts.append(names(bucket.accounts)) }
            notes.append(PlanLibraryNote(title: bucket.name, detail: parts.joined(separator: " · "),
                                         amount: whole(bucket.value)))
        }
        for seed in reading.seeds {
            let detail = seed.used
                ? "\(names(seed.accounts)): their value on \(date) is where the pension starts, rather than "
                    + "money the plan draws on."
                : "\(names(seed.accounts)) isn't used: the plan gives the pension a starting balance of its own."
            notes.append(PlanLibraryNote(title: "\(seed.name) starting balance", detail: detail,
                                         amount: whole(seed.value)))
        }
        return notes
    }
}

/// One line of "How the plan reads your library": a bucket of accounts, or
/// accounts that start a pension scheme, with their value.
struct PlanLibraryNote: Hashable, Sendable, Identifiable {
    var title: String
    var detail: String
    /// In the plan's currency; shown through `AmountText`, so it hides.
    var amount: Decimal?

    var id: String { title + "|" + detail }
}
