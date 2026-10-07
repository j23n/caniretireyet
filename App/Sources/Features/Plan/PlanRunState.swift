import Foundation
import Model

// What a plan's results area shows and says (UI.md, "Calculating" and
// "Out of date"): the results it has, why they're out of date, the run in
// progress and the button that brings them up to date. Plain Swift, so
// it's tested without SwiftUI; `PlanSession` fills it in from the stores.

/// The state of a plan's results area.
struct PlanResultsState: Hashable, Sendable {
    /// What's on screen.
    enum Content: Hashable, Sendable {
        /// Results calculated in this session, possibly out of date.
        case results(PlanResults)
        /// No results yet: the answer recorded at the last check-in, dated.
        /// `planChanged` when the plan was edited since it was recorded.
        case recorded(PlanHeadline, planChanged: Bool)
        /// Nothing calculated or recorded yet.
        case nothing
    }

    /// What the main button does.
    enum Action: Hashable, Sendable {
        /// Nothing calculated yet: "Calculate".
        case calculate
        /// The plan or the library changed: "Recalculate".
        case recalculate
        /// Only the what-if moved: "Run What-If".
        case runWhatIf
        /// Another retirement age was chosen for the charts: "Calculate".
        case calculateFocus(Int)

        var title: String {
            switch self {
            case .calculate, .calculateFocus: "Calculate"
            case .recalculate: "Recalculate"
            case .runWhatIf: "Run What-If"
            }
        }
    }

    var content: Content
    /// Why the results shown no longer fit, most important first; empty
    /// when they do.
    var staleReasons: [PlanStaleReason] = []
    /// The run in progress that the screen waits for.
    var progress: PlanRunProgress?
    /// Whether that run can be cancelled: a check-in's can't, it records
    /// the month's answer.
    var canCancel = true
    /// The retirement age chosen for the charts, when it isn't the plan's own.
    var focusAge: Int?
    /// Whether a run is going, for a state built without its ``progress``
    /// (``PlanSession/stateWithoutProgress``).
    var running = false

    init(content: Content, staleReasons: [PlanStaleReason] = [], progress: PlanRunProgress? = nil,
         canCancel: Bool = true, focusAge: Int? = nil, running: Bool = false) {
        self.content = content
        self.staleReasons = staleReasons
        self.progress = progress
        self.canCancel = canCancel
        self.focusAge = focusAge
        self.running = running
    }

    /// The results on screen, if any.
    var results: PlanResults? {
        if case .results(let results) = content { return results }
        return nil
    }

    var isRunning: Bool { running || progress != nil }

    /// Whether results are shown and fit the plan, library and what-if as
    /// they are now.
    var isUpToDate: Bool { results != nil && staleReasons.isEmpty }

    /// Whether the results shown are out of date.
    var isOutOfDate: Bool { results != nil && !staleReasons.isEmpty }

    /// Whether the results are shown dimmed: while a run replaces them, and
    /// while they're out of date.
    var dimsResults: Bool { results != nil && (isRunning || isOutOfDate) }

    /// The button that brings the screen up to date; `nil` when it is, or
    /// while a run is going.
    var action: Action? {
        guard !isRunning else { return nil }
        guard results != nil else { return .calculate }
        if staleReasons.contains(.plan) || staleReasons.contains(.library) { return .recalculate }
        if staleReasons.contains(.whatIf) { return .runWhatIf }
        if staleReasons.contains(.focusAge), let age = focusAge { return .calculateFocus(age) }
        return staleReasons.isEmpty ? nil : .recalculate
    }
}

/// The words of the results area.
enum PlanRunText {
    // MARK: Out of date

    static let outOfDateTitle = "Out of date"

    /// "Inputs changed since this was calculated." For the plan, the
    /// library and the what-if; another focus age has its own sentence.
    static func staleMessage(_ reasons: [PlanStaleReason], focusAge: Int? = nil) -> String? {
        var subjects: [String] = []
        if reasons.contains(.plan) { subjects.append("Inputs") }
        if reasons.contains(.library) { subjects.append("Your accounts or prices") }
        if reasons.contains(.whatIf) { subjects.append("What-if values") }
        if !subjects.isEmpty {
            let lowered = subjects.enumerated().map { $0.offset == 0 ? $0.element : lowercasedFirst($0.element) }
            return "\(PlanResultsText.list(lowered)) changed since this was calculated."
        }
        if reasons.contains(.focusAge) {
            guard let focusAge else { return "These charts are for another retirement age." }
            return "Calculate to see the charts for retiring at \(focusAge)."
        }
        return nil
    }

    /// "What-if values" → "what-if values"; "Inputs" → "inputs".
    private static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    /// The headline next to the sliders while the what-if hasn't run:
    /// "Before your what-if changes".
    static let beforeWhatIf = "From before your what-if changes"

    // MARK: Nothing yet

    /// Why there's a Calculate button and nothing else.
    static func calculateExplanation(runs: Int, locale: Locale = .current) -> String {
        "Calculating simulates \(AmountFormat.number(Decimal(runs), locale: locale)) possible futures to find "
            + "when you could retire. It takes a few seconds, and runs only when you ask."
    }

    /// "Recorded at the check-in on 30 Sep 2026".
    static func recorded(_ headline: PlanHeadline, planChanged: Bool, locale: Locale = .current) -> String? {
        guard let date = headline.recordedOn else { return nil }
        let base = "Recorded at the check-in on \(AmountFormat.mediumDate(date, locale: locale))"
        return planChanged ? base + ", before the plan's latest changes" : base
    }

    /// In the plan menu, about the answer shown: "Calculated at 09:41 with
    /// 2.000 runs"; for results kept on the device from an earlier day
    /// "Calculated on 30 Sep at 09:41 with 400 runs, a quick estimate", with
    /// the year when it isn't this one.
    static func calculated(_ results: PlanResults, now: Date = Date(), calendar: Calendar = .current,
                           locale: Locale = .current) -> String {
        let date = results.computedAt
        let time = formatted(date, .dateTime.hour().minute(), calendar: calendar, locale: locale)
        let when: String
        if calendar.isDate(date, inSameDayAs: now) {
            when = "at \(time)"
        } else {
            var day = Date.FormatStyle.dateTime.day().month(.abbreviated)
            if !calendar.isDate(date, equalTo: now, toGranularity: .year) { day = day.year() }
            when = "on \(formatted(date, day, calendar: calendar, locale: locale)) at \(time)"
        }
        let runs = AmountFormat.number(Decimal(results.runs), locale: locale)
        let quick = results.mode == .fast ? ", a quick estimate" : ""
        return "Calculated \(when) with \(runs) runs\(quick)"
    }

    private static func formatted(_ date: Date, _ style: Date.FormatStyle, calendar: Calendar,
                                  locale: Locale) -> String {
        var styled = style.locale(locale)
        styled.calendar = calendar
        styled.timeZone = calendar.timeZone
        return date.formatted(styled)
    }

    /// Under a recorded answer: the charts need a calculation.
    static let chartsNeedCalculation = "Calculate the plan to see its charts."

    // MARK: Progress

    /// "Calculating…", "Quick estimate…", or a check-in's "Working out this
    /// month's answer…".
    static func title(_ progress: PlanRunProgress, isCheckIn: Bool = false) -> String {
        if isCheckIn { return "Working out this month's answer…" }
        return progress.mode == .fast ? "Quick estimate…" : "Calculating…"
    }

    /// "Simulating 1.234 / 2.000 runs", "Earliest age · ages 41–75: 12 / 35",
    /// "Sustainable spending: step 4 / 12", "Needed to retire today: step 3 /
    /// 9", in the locale's numbers.
    static func phase(_ progress: PlanRunProgress, locale: Locale = .current) -> String {
        let done = AmountFormat.number(Decimal(progress.completed), locale: locale)
        let total = AmountFormat.number(Decimal(progress.total), locale: locale)
        switch progress.phase {
        case .starting:
            return "Starting…"
        case .earliestAge:
            let ages = progress.ages.map { " · ages \($0.lowerBound)–\($0.upperBound)" } ?? ""
            return "Earliest age\(ages): \(done) / \(total)"
        case .simulating:
            return "Simulating \(done) / \(total) runs"
        case .sustainableSpending:
            return "Sustainable spending: step \(done) / \(total)"
        case .assetsNeeded:
            return "Needed to retire today: step \(done) / \(total)"
        case .agesWithout:
            return "Coast age and windfalls: step \(done) / \(total)"
        case .summarising:
            return "Summarising"
        }
    }

    /// The whole run's share: "34%".
    static func overall(_ progress: PlanRunProgress, locale: Locale = .current) -> String {
        AmountFormat.percent(min(1, max(0, progress.fraction)), digits: 0, locale: locale)
    }

    /// "Calculating, 34%, Simulating 1.234 / 2.000 runs", for VoiceOver.
    static func accessibility(_ progress: PlanRunProgress, isCheckIn: Bool = false, locale: Locale = .current)
        -> String {
        let title = String(title(progress, isCheckIn: isCheckIn).dropLast())
        return "\(title), \(overall(progress, locale: locale)) done, \(phase(progress, locale: locale))"
    }

    /// "Calculating 34%", for a status line.
    static func status(_ progress: PlanRunProgress, isCheckIn: Bool = false, locale: Locale = .current) -> String {
        "\(title(progress, isCheckIn: isCheckIn).dropLast()) \(overall(progress, locale: locale))"
    }

    /// A short form for small places (the answer pill): "34%".
    static func short(_ progress: PlanRunProgress, locale: Locale = .current) -> String {
        progress.phase == .starting ? "…" : overall(progress, locale: locale)
    }
}
