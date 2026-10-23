import Foundation
import Glance
import Model
import Planner
import Tracker

// The words of Progress (UI.md, "Progress"; PROGRESS.md): the answer
// recorded at each check-in, each year's progress, and your actual numbers
// against a baseline. The numbers are the Planner's `PlanProgress`.

extension PlanAnswerHistory.Change {
    var label: String {
        switch self {
        case .plan: "Plan changed"
        case .engine: "Calculations updated"
        }
    }

    var systemImage: String {
        switch self {
        case .plan: "pencil"
        case .engine: "gearshape"
        }
    }
}

extension PlanAnswerHistory.Marker {
    var label: String { changes.map(\.label).joined(separator: " · ") }
}

extension PlanAnswerHistory {
    /// "54 now: 4 years sooner since Jan 2026.", "54 now: no change since
    /// Jan 2026.", "54 now."; `nil` without an earliest age.
    func nowLine(locale: Locale) -> String? {
        guard let latest = latestAge else { return nil }
        guard let change else { return "\(latest) now." }
        let since = GlanceText.shortMonthAndYear(change.since, locale: locale)
        let move = change.years == 0 ? "no change" : PlanProgressText.move(years: change.years)
        return "\(latest) now: \(move) since \(since)."
    }
}

extension PlanBaselineComparison {
    /// The line under the chart: which accounts, and in what money.
    func unitsNote(baseCurrency: CurrencyCode, locale: Locale = .current) -> String {
        let code = baseCurrency.rawValue
        if isInflationAdjusted {
            var note = "The baseline's accounts and those opened since, in \(code) of "
                + "\(AmountFormat.mediumDate(baseline.start.date, locale: locale))."
            if !actual.dropFirst().isEmpty,
               let standIn = PlanMoney.standInNote(inflation, currency: baseCurrency, locale: locale) {
                note += " " + standIn
            }
            return note
        } else if inflation == nil {
            return "The baseline's accounts and those opened since, in \(code) of each date: the library has no "
                + "inflation index."
        } else {
            return "The baseline's accounts and those opened since. Without inflation values for every date, some "
                + "are in the "
                + "\(code) of their time."
        }
    }

    /// The line under the baseline's chart: "61 in 100 of the futures you
    /// expected are below you"; empty when that isn't known.
    static func percentileText(_ position: Position) -> String {
        position.futuresBelow.map { "\($0) of the futures you expected are below you" } ?? ""
    }

    /// The picker's label: "Start of 2026 (automatic)", "Before going part-time (saved 12 Mar)".
    static func label(for baseline: Baseline, locale: Locale = .current) -> String {
        if baseline.kind == .past {
            let name = baseline.label ?? "What I planned in \(baseline.start.date.year)"
            return "\(name) (added \(AmountFormat.mediumDate(baseline.created, locale: locale)))"
        }
        let name = baseline.label ?? (baseline.kind == .yearly ? "Start of \(baseline.created.year)" : "Baseline")
        if baseline.kind == .yearly { return "\(name) (automatic)" }
        return "\(name) (saved \(AmountFormat.shortDate(baseline.created, locale: locale)))"
    }
}

// MARK: - Year by year

extension PlanProgressYear {
    /// "2026 so far", "2025".
    var title: String { isLatest ? "\(year) so far" : "\(year)" }

    /// What the year is measured against, in words: "your January plan"
    /// (its own automatic baseline, saved at its first check-in), the month
    /// it was saved in when that was later ("your October plan"), "your
    /// 2021 plan" (a past baseline).
    func expectation(locale: Locale = .current) -> String {
        guard let baseline else { return "your January plan" }
        return Self.expectation(baseline.baseline, year: year, locale: locale)
    }

    /// What `baseline` is in words for `year` measured against it, as
    /// ``expectation(locale:)`` says it: "your January plan", "your October
    /// plan", "your 2021 plan". The plan's *On track?* names it so too.
    static func expectation(_ baseline: Baseline, year: Int, locale: Locale = .current) -> String {
        let start = baseline.start.date
        if baseline.kind == .past { return "your \(start.year) plan" }
        guard start.year == year, start.month > 1 else { return "your January plan" }
        return "your \(AmountFormat.monthName(start, locale: locale)) plan"
    }

    /// ``expectation(locale:)`` starting a sentence: "Your January plan".
    func expectationTitle(locale: Locale = .current) -> String {
        let words = expectation(locale: locale)
        return words.capitalizedFirst
    }

    /// What deleting `entry` changes, for its confirmation: which of `years`
    /// measured against it are then measured against another baseline
    /// (``baseline(for:in:)`` among those left) and which have none; whether
    /// an automatic baseline comes back; where its copy is kept.
    ///
    /// - Parameter savingYear: the year a check-in would save an automatic
    ///   baseline for when it has none: for the main plan, the year of the
    ///   date a new check-in is suggested for (last year's in January's
    ///   first days, Tracker's `CheckInDates.suggested(today:lastCheckIn:)`);
    ///   `nil` for another plan (``PlanStore/checkInSaved(on:)``).
    static func deletionNote(of entry: PlanBaselineEntry, years: [Int], baselines: [PlanBaselineEntry],
                             savingYear: Int?, locale: Locale = .current) -> String {
        let rest = baselines.filter { $0.id != entry.id }
        let measured = years.filter { baseline(for: $0, in: baselines)?.id == entry.id }
        var sentences: [String] = []
        if measured.isEmpty {
            sentences.append("No year is measured against it.")
        }
        // The years in order, a sentence for each baseline that measures them then.
        var groups: [(next: PlanBaselineEntry?, years: [Int])] = []
        for year in measured {
            let next = baseline(for: year, in: rest)
            if let index = groups.firstIndex(where: { $0.next?.id == next?.id }) {
                groups[index].years.append(year)
            } else {
                groups.append((next, [year]))
            }
        }
        for group in groups {
            let list = Wording.list(group.years.map { String($0) })
            let one = group.years.count == 1
            if let next = group.next {
                let label = PlanBaselineComparison.label(for: next.baseline, locale: locale)
                sentences.append("\(list) \(one ? "is" : "are") then measured against “\(label)”.")
            } else {
                sentences.append("\(list) then \(one ? "has" : "have") no baseline to be measured against.")
            }
        }
        if entry.baseline.kind == .yearly {
            if yearlyBaseline(for: entry.baseline.created.year, in: rest) != nil {
                sentences.append("Its year keeps its other automatic baseline.")
            } else if entry.baseline.created.year == savingYear {
                sentences.append("Your next check-in saves a new automatic baseline, starting then.")
            } else {
                sentences.append("An automatic baseline is only saved in its own year, for the main plan, so this "
                    + "one won't come back.")
            }
        }
        sentences.append("A copy is kept in Sync & backups.")
        return sentences.joined(separator: " ")
    }
}

// MARK: - The years on a strip

/// Progress as a strip of years (UI.md, "Progress"): a card per year with
/// your money through it against what January expected (the Planner's
/// `PlanYearChart`), on a scale the cards on screen share, so December of
/// one year meets January of the next; where the answer moved; and the
/// year's story. Oldest first: the strip opens at today, on the right.
struct PlanProgressTimeline {
    /// Something that happened at a check-in of the year: the answer moved,
    /// or the plan or the calculations changed; a milestone was reached; you
    /// saved well above usual, or markets moved a lot.
    struct Note: Hashable, Sendable, Identifiable {
        var date: CalendarDate
        /// "Mar".
        var month: String
        /// Its words; an amount in them hides with the eye.
        var text: AmountSentence
        /// A milestone reached (PROGRESS.md, "Milestones"), in bold in the year's words.
        var isMilestone = false
        var id: String { "\(date) \(text.text)" }
    }

    /// A month's notes, as the year's words list them: one row a month.
    struct NoteRow: Hashable, Sendable, Identifiable {
        var date: CalendarDate
        /// "Mar".
        var month: String
        var notes: [Note]

        var id: String { "\(date.year)-\(date.month)" }

        /// Whether a milestone was reached in the month.
        var hasMilestone: Bool { notes.contains { $0.isMilestone } }

        /// The month's notes one after another, its milestones in bold (they
        /// read as ``PlanChapterStory/Run/value(_:)``).
        var runs: [PlanChapterStory.Run] {
            notes.enumerated().flatMap { offset, note -> [PlanChapterStory.Run] in
                let run: PlanChapterStory.Run = note.isMilestone ? .value(note.text) : .text(note.text)
                return offset > 0 ? [.text(" "), run] : [run]
            }
        }
    }

    /// One year's card: its chart, and its notes and summary in words.
    struct Card: Identifiable {
        let chart: PlanYearChart
        /// By date.
        let notes: [Note]
        /// The year in a line ("Two years sooner, and past 300.000 €."); `nil` for a quiet one.
        let summary: AmountSentence?

        var id: Int { chart.id }
        var year: PlanProgressYear { chart.year }
        var actual: [ChartPoint] { chart.actual }
        var expected: [ChartPoint] { chart.expected }
        var milestones: [ReachedMilestone] { chart.milestones }
        var checkIns: Set<Date> { chart.checkIns }
        var currency: CurrencyCode { chart.currency }
        var start: Date { chart.start }
        var end: Date { chart.end }
        var gaps: [PlanYearChart.Gap] { chart.gaps }

        func expected(on date: Date) -> Double? {
            chart.expected(on: date)
        }

        /// The notes a month at a time, in order.
        var noteRows: [NoteRow] {
            var rows: [NoteRow] = []
            for note in notes {
                if let last = rows.last, last.date.year == note.date.year, last.date.month == note.date.month {
                    rows[rows.count - 1].notes.append(note)
                } else {
                    rows.append(NoteRow(date: note.date, month: note.month, notes: [note]))
                }
            }
            return rows
        }
    }

    /// Oldest first.
    let cards: [Card]

    /// - Parameter text: the milestones' and the notes' words, with their currency.
    init(_ progress: PlanProgress, text: PlanMilestoneText) {
        let locale = text.locale
        cards = progress.charts.map { chart in
            let milestoneNotes = chart.milestones.map { reached in
                Note(date: reached.date, month: GlanceText.shortMonth(reached.date, locale: locale),
                     text: text.reachedInRow(reached.milestone), isMilestone: true)
            }
            let notes = (chart.answerEvents.map { Self.note($0, text: text) } + milestoneNotes
                + chart.notableEvents.map { Self.note($0, text: text) }).sorted { $0.date < $1.date }
            return Card(chart: chart, notes: notes,
                        summary: PlanProgressText.summary(chart.year, milestones: chart.milestones, text: text))
        }
    }

    /// The money scale fitted to the money between the screen's edges
    /// (UI.md, "Progress"): your money and what was expected, each card's
    /// plot `inset` in from its edges. `nil` without values.
    func scale(fitting window: PlanStripWindow, inset: Double = 0) -> PlanStripScale? {
        PlanStripScale(values: window.values(of: cards, inset: inset) { card, plot in
            let lines = [card.actual, card.expected].map { line in
                line.map { StripFit.Point(date: $0.date, value: $0.value) }
            }
            return StripFit.Card(plot: plot, start: card.start, end: card.end, lines: lines)
        })
    }

    /// An event's note: "55, a year sooner.", "Plan changed: 54 again.",
    /// "You saved 9.000 €, more than usual.", "Markets fell 12.000 €, 6%.".
    static func note(_ event: PlanYearEvent, text: PlanMilestoneText) -> Note {
        let month = GlanceText.shortMonth(event.date, locale: text.locale)
        let money = PlanWords(currency: text.currency, locale: text.locale)
        let words: AmountSentence
        switch event.kind {
        case let .answerMoved(age, years, again, planChanged):
            let cause = planChanged ? "Plan changed: " : ""
            let line = again ? "\(cause)\(age) again." : "\(cause)\(age), \(PlanProgressText.move(years: years))."
            words = AmountSentence(line)
        case .changed(let changes):
            words = AmountSentence("\(changes.map(\.label).joined(separator: " · ")).")
        case .noAge:
            words = "No age worked out."
        case .savedMore(let saved):
            words = "You saved \(money.unsigned(saved)), more than usual."
        case let .markets(markets, share):
            let percent = AmountFormat.percent(share.doubleValue, digits: 0, locale: text.locale)
            words = markets < 0 ? "Markets fell \(money.unsigned(markets)), \(percent)."
                : "Markets added \(money.unsigned(markets)), \(percent)."
        }
        return Note(date: event.date, month: month, text: words)
    }
}

/// A year's words (UI.md, "Progress"): its change, where it stands against
/// January, its story and January's note. Amounts hide with the eye
/// (``AmountSentence``).
enum PlanProgressText {
    /// "+34.000 €", or "so far" for the year still going.
    static func change(_ year: PlanProgressYear, currency: CurrencyCode,
                       locale: Locale = .current) -> AmountSentence {
        guard !year.isLatest else { return "so far" }
        return .amount(AmountFormat.signedAmount(year.change.change, currency: currency, locale: locale))
    }

    /// "18.400 € ahead of your January plan", "3.000 € behind your 2021 plan"; `nil` without a baseline.
    static func againstJanuary(_ year: PlanProgressYear, currency: CurrencyCode,
                               locale: Locale = .current) -> AmountSentence? {
        guard let position = year.position else { return nil }
        let gap = PlanWords(currency: currency, locale: locale).unsigned(position.gap)
        let expectation = year.expectation(locale: locale)
        return position.gap >= 0 ? "\(gap) ahead of \(expectation)" : "\(gap) behind \(expectation)"
    }

    /// "You saved 13.200 € and markets added 22.200 €. Your answer moved from
    /// 56 to 54, two years sooner."
    static func story(_ year: PlanProgressYear, currency: CurrencyCode,
                      locale: Locale = .current) -> AmountSentence {
        var sentences: [AmountSentence] = []
        if let note = pricesNote(year, locale: locale) {
            sentences.append(AmountSentence(note))
        }
        if year.from != year.to {
            sentences.append(PlanWords(currency: currency, locale: locale)
                .savedAndMarkets(saved: year.change.saved, markets: year.change.market).capitalizedFirst)
        }
        if let from = year.answerFrom?.earliestAge, let to = year.answerTo?.earliestAge {
            if from == to {
                sentences.append("Your answer stayed at \(to).")
            } else {
                sentences.append("Your answer moved from \(from) to \(to), \(move(years: to - from)).")
            }
        }
        return sentences.joined(separator: " ")
    }

    /// "No check-ins this year: what you held is valued at its prices.", "No
    /// check-ins after June: …"; `nil` for a year with check-ins to its end.
    static func pricesNote(_ year: PlanProgressYear, locale: Locale = .current) -> String? {
        if year.checkIns == 0 { return "No check-ins this year: what you held is valued at its prices." }
        guard !year.isLatest, let last = year.lastCheckIn, last.month < 12 else { return nil }
        return "No check-ins after \(AmountFormat.monthName(last, locale: locale)): what you held is valued at its "
            + "prices."
    }

    /// "Your January plan expected 298.000 € by now", "… by 31 Dec", with `amount`'s
    /// words; `nil` without a position.
    static func expected(_ year: PlanProgressYear, amount: (Decimal) -> AmountSentence,
                         locale: Locale = .current) -> AmountSentence? {
        guard let position = year.position else { return nil }
        let when = year.isLatest ? "by now" : "by \(AmountFormat.shortDate(year.to, locale: locale))"
        return "\(year.expectationTitle(locale: locale)) expected \(amount(position.median)) \(when)"
    }

    /// "Your January plan expected 298.000 € by now. You're 18.400 € ahead, more than
    /// in 68 of its 100 futures."
    static func january(_ year: PlanProgressYear, currency: CurrencyCode,
                        locale: Locale = .current) -> AmountSentence? {
        let amount = PlanWords(currency: currency, locale: locale).unsigned
        guard let position = year.position, var text = expected(year, amount: amount, locale: locale)
        else { return nil }
        let december = CalendarDate.lastDay(ofYear: year.year)
        if year.isLatest, let entry = year.baseline, december > year.to,
           let bands = entry.baseline.percentiles(on: december) {
            text += " and \(amount(Decimal(wholeNumber: bands[2]))) by December"
        }
        text += ". "
        let side = position.gap >= 0 ? "ahead" : "behind"
        text += year.isLatest ? "You're \(amount(position.gap)) \(side)" : "You ended \(amount(position.gap)) \(side)"
        text += futuresClause(position)
        return text
    }

    /// How the money compares with the baseline's futures, ending a
    /// sentence: ", more than in 68 of its 100 futures.", ", less than in 9
    /// of its 10 futures."; "." when that isn't known.
    private static func futuresClause(_ position: PlanBaselineComparison.Position) -> AmountSentence {
        if let percentile = position.percentile {
            return ", more than in \(Int(wholeNumber: percentile)) of its 100 futures."
        }
        if position.isAboveNinetieth { return ", more than in 9 of its 10 futures." }
        if position.isBelowTenth { return ", less than in 9 of its 10 futures." }
        return "."
    }

    /// The year in a line: how the answer moved, the milestone it passed, or
    /// what markets did: "Two years sooner, and past 300.000 €.", "A strong
    /// year for markets, and a year sooner."; `nil` for a quiet year.
    static func summary(_ year: PlanProgressYear, milestones: [ReachedMilestone],
                        text: PlanMilestoneText) -> AmountSentence? {
        var parts: [AmountSentence] = []
        if let change = year.ageChange, change != 0 {
            parts.append(AmountSentence(move(years: change, spelled: true)))
        }
        let rounds = milestones.filter { $0.milestone.kind == .roundAmount }
        if let top = rounds.max(by: { $0.milestone.amount < $1.milestone.amount }) {
            parts.append("past \(text.name(top.milestone))")
        } else if milestones.contains(where: { $0.milestone.kind == .crossover }) {
            parts.append("past the crossover")
        } else if milestones.contains(where: { if case .coastPoint = $0.milestone.kind { true } else { false } }) {
            parts.append("past the coast point")
        }
        if parts.count < 2, let markets = year.marketYear?.yearWords {
            parts.insert(AmountSentence(markets), at: 0)
        }
        guard let first = parts.first else { return nil }
        let sentence: AmountSentence = parts.count > 1 ? "\(first), and \(parts[1])" : first
        return "\(sentence.capitalizedFirst)."
    }

    /// How the earliest age moved by `change` years (negative is sooner):
    /// "a year sooner", "2 years later", `spelled` "two years later".
    static func move(years change: Int, spelled: Bool = false) -> String {
        let count = abs(change)
        let span = count == 1 ? "a year" : (spelled ? number(count) : "\(count)") + " years"
        return "\(span) \(change < 0 ? "sooner" : "later")"
    }

    /// "Two", "three", … up to ten, then digits.
    static func number(_ value: Int) -> String {
        let words = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return words.indices.contains(value - 1) ? words[value - 1] : "\(value)"
    }

    /// A year's card without a position against a baseline: "No check-ins ·
    /// from prices", "Measured from your next check-in" (its baseline starts
    /// at its latest one), "No plan kept in January".
    static func unmeasured(_ year: PlanProgressYear) -> String {
        if year.checkIns == 0 { return "No check-ins · from prices" }
        guard year.baseline != nil else { return "No plan kept in January" }
        return year.isLatest ? "Measured from your next check-in" : "Baseline saved at its last check-in"
    }

    /// "Ahead of plan.", "On plan.", "Behind plan." for the latest year:
    /// where you are among its baseline's futures
    /// (``PlanBaselineComparison/Standing``).
    static func headline(_ position: PlanBaselineComparison.Position?) -> String {
        position?.standing.title ?? "Not measured yet."
    }

    /// "You have 18.400 € more than January expected, more than in 68 of its
    /// 100 futures." for the latest year; without a position, why not.
    static func headlineDetail(_ year: PlanProgressYear?, currency: CurrencyCode,
                               locale: Locale = .current) -> AmountSentence {
        guard let year, let position = year.position else {
            if year?.baseline != nil {
                return "This year's baseline starts at your latest check-in, so your next check-in is the first "
                    + "measured against it."
            }
            return "Your plan is kept at the first check-in of each year, and the year is measured against it."
        }
        let gap = PlanWords(currency: currency, locale: locale).unsigned(position.gap)
        let expectation = year.expectation(locale: locale)
        let text: AmountSentence = position.gap >= 0 ? "You have \(gap) more than \(expectation) expected"
            : "You have \(gap) less than \(expectation) expected"
        return text + futuresClause(position)
    }
}

extension PlanBaselineComparison.Position {
    /// How many of the baseline's 100 futures are below your money: "61 in
    /// 100", "Over 9 in 10", "Under 1 in 10"; `nil` when that isn't known.
    var futuresBelow: String? {
        if let percentile { return "\(Int(wholeNumber: percentile)) in 100" }
        if isAboveNinetieth { return "Over 9 in 10" }
        if isBelowTenth { return "Under 1 in 10" }
        return nil
    }
}
