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
                return (Int(wholeNumber: numerator), denominator)
            }
        }
        return (Int(wholeNumber: share * 100), 100)
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
        if share <= 0.5 { return "1 in \(Int(wholeNumber: 1 / share))" }
        return "\(Int(wholeNumber: share * 10)) in 10"
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

    // MARK: Flexible spending

    /// "Flexible spending (cuts of 10% down to 80%)", the card's title.
    static func flexibleTitle(_ summary: FlexibleSpendingSummary, locale: Locale = .current) -> String {
        "Flexible spending (cuts of \(AmountFormat.percent(summary.cut, digits: 0, locale: locale)) down to "
            + "\(AmountFormat.percent(summary.floor, digits: 0, locale: locale)))"
    }

    /// The card's sentences (UI.md, "Results"): how low spending goes in a
    /// bad case and how many futures never cut, how long spending stays below
    /// the plan's, and when a cut comes. "In a bad case (1 in 10) you'd spend
    /// as little as 29.000 € a year for a while; half of all futures never
    /// cut." Amounts read `•••••` while hidden.
    static func flexibleSentences(_ summary: FlexibleSpendingSummary, currency: CurrencyCode,
                                  hidesAmounts: Bool = false, locale: Locale = .current) -> [String] {
        func money(_ value: Double) -> String {
            hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(whole(value), currency: currency, locale: locale)
        }
        let never = neverCut(1 - summary.shareWithCut, locale: locale)
        var sentences: [String] = []
        if let lowest = summary.p10LowestSpending {
            sentences.append(lowest >= summary.planSpending - 0.5
                ? "Even in a bad case (1 in 10) you'd never cut; \(never)."
                : "In a bad case (1 in 10) you'd spend as little as \(money(lowest)) a year for a while; \(never).")
        } else {
            sentences.append("In a bad case (1 in 10) the money runs out even at the floor; \(never).")
        }
        if summary.medianYearsBelow > 0 {
            sentences.append("Half of all futures spend \(summary.medianYearsBelow) or more of "
                + "\(summary.retirementYears) years in retirement below your plan's spending.")
        }
        return sentences
    }

    /// The rule under the card's sentences: "Spending is cut by 10% of the
    /// plan's when the share of your money you draw rises 20% above the first
    /// year's, and restored when it falls 20% below: never under 28.800 € a
    /// year, nor above 36.000 €."
    static func flexibleRule(_ summary: FlexibleSpendingSummary, currency: CurrencyCode, hidesAmounts: Bool = false,
                             locale: Locale = .current) -> String {
        func money(_ value: Double) -> String {
            hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(whole(value), currency: currency, locale: locale)
        }
        let upper = AmountFormat.percent(summary.upperGuardrail, digits: 0, locale: locale)
        let lower = AmountFormat.percent(summary.lowerGuardrail, digits: 0, locale: locale)
        return "Spending is cut by \(AmountFormat.percent(summary.cut, digits: 0, locale: locale)) of the plan's when "
            + "the share of your money you draw rises \(upper) above the first year's, and restored when it falls "
            + "\(lower) below: never under \(money(summary.floorSpending)) a year, nor above "
            + "\(money(summary.planSpending)). Retiring at \(summary.age)."
    }

    /// "half of all futures never cut", "72% of futures never cut".
    static func neverCut(_ share: Double, locale: Locale = .current) -> String {
        if share >= 0.995 { return "no future cuts" }
        if share < 0.005 { return "every future cuts at some point" }
        if abs(share - 0.5) < 0.05 { return "half of all futures never cut" }
        return "\(AmountFormat.percent(share, digits: 0, locale: locale)) of futures never cut"
    }

    // MARK: What retiring today needs

    /// The most times today's plan assets the planner looks for, as words: "20".
    static var searchedScale: String { String(Int(AssetsNeeded.maximumScale)) }

    /// The readiness as a share to show: below 100% rounded down to a whole
    /// percent, so it never reads 100% while retiring today falls short.
    static func readinessShare(_ readiness: Double) -> Double {
        guard readiness < 1 else { return readiness }
        return min(0.99, max(0, (readiness * 100 + 1e-9).rounded(.down) / 100))
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
            + "simulating retiring today with extra money added to accounts you can draw now, or with money taken "
            + "out of them; money locked in pension funds stays as it is. At 100% you could retire today."
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
        return rows
    }

    /// A `Double` in whole units of the currency (0 when it isn't a number).
    static func whole(_ value: Double) -> Decimal {
        Decimal(wholeNumber: value)
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
