import Model
import Planner
import SwiftUI
import Tracker

// The chosen year in figures and rows (UI.md, "Year"), under its chart:
// what you saved and what markets did, what happened, and why you're ahead
// or behind on a tap. On the Mac and iPad the figures are rows beside the
// chart, and the check-ins a table under it.

/// What you saved and what markets did in the year, two small cards side by
/// side on iPhone: "You saved 15.890 €, planned 13.463 € by now" and
/// "Markets added 8.940 €, expected 1.982 €".
struct PlanYearFigurePair: View {
    let card: PlanProgressTimeline.Card

    @Environment(\.locale) private var locale

    private var year: PlanProgressYear { card.year }

    var body: some View {
        let saved = year.change.saved
        let market = year.change.market
        EqualColumns(spacing: Metrics.m, equalHeights: true) {
            TimelineFigureCard(title: saved >= 0 ? "You saved" : "You took out", detail: savedDetail) {
                AmountText(abs(saved), currency: card.currency, tabular: false)
            }
            TimelineFigureCard(title: market >= 0 ? "Markets added" : "Markets took", detail: marketsDetail) {
                AmountText(abs(market), currency: card.currency, tabular: false)
            }
        }
    }

    private func amount(_ value: Decimal) -> String {
        AmountFormat.amount(abs(value), currency: card.currency, locale: locale)
    }

    /// "planned 13.463 € by now", "planned 12.000 €"; `nil` without a plan.
    private var savedDetail: AmountSentence? {
        guard let planned = year.explanation?.inWholeUnits.plannedSaving ?? year.plannedSaving else { return nil }
        let byNow = year.isLatest ? " by now" : ""
        return "planned \(amount: amount(planned))\(byNow)"
    }

    /// "expected 1.982 €", or what kind of year it was for markets.
    private var marketsDetail: AmountSentence? {
        if let expected = year.explanation?.inWholeUnits.expectedMarket {
            return "expected \(amount: amount(expected))"
        }
        return year.marketYear?.yearWords.map { AmountSentence($0) }
    }
}

/// The year's figures as rows beside its chart on the Mac and iPad: where
/// it started, what you saved and what markets did, where it is now (or
/// ended), what was planned, and how the earliest age moved.
struct PlanYearFiguresCard: View {
    let card: PlanProgressTimeline.Card

    private var year: PlanProgressYear { card.year }

    var body: some View {
        TimelineTitledRows(title: year.title, personal: true) {
            CardRow("Started at") { AmountText(year.change.start, currency: card.currency) }
            CardRow(year.change.saved >= 0 ? "You saved" : "You took out") {
                AmountText(abs(year.change.saved), currency: card.currency)
            }
            CardRow("Markets") {
                AmountText(year.change.market, currency: card.currency, signed: true)
                    .foregroundStyle(year.change.market < 0 ? Palette.orangeStroke : Palette.positive)
            }
            CardRow(year.isLatest ? "Now" : "Ended at") {
                AmountText(year.change.end, currency: card.currency)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
            }
            if let planned = year.plannedSaving {
                CardRow("Planned to save") { AmountText(planned, currency: card.currency) }
            }
            if let age = PlanYearHappenings.ageWords(year) {
                CardRow("Earliest age") {
                    Text(age)
                        .monospacedDigit()
                        .privacySensitiveInFeedback()
                }
            }
        }
    }
}

/// What happened in the year, as rows on a card: how the earliest age
/// moved, then a row for each note, newest first, its month on the left
/// and its words on the right on one line ("July · Passed 150.000 €",
/// "March · Markets fell 6.200 €, 4%"), a milestone flagged; then why
/// you're ahead or behind, which opens it in full (``PlanYearWhy``). Under
/// the card, check-ins that stop early, and missing prices or rates.
struct PlanYearHappenings: View {
    let card: PlanProgressTimeline.Card

    @Environment(\.locale) private var locale
    @State private var showsWhy = false
    @State private var fillsPastPrices = false

    private var year: PlanProgressYear { card.year }

    private struct Line: Identifiable {
        var id: Int
        var month: String
        var words: AmountSentence
        var flagged: Bool
    }

    /// Each note of the year, newest first.
    private var lines: [Line] {
        var lines: [Line] = []
        for note in card.notes.reversed() {
            lines.append(Line(id: lines.count, month: AmountFormat.monthName(note.date, locale: locale),
                              words: Self.withoutFinalPeriod(note.text), flagged: note.isMilestone))
        }
        return lines
    }

    /// "56 → 55", "55, no change"; `nil` without an age at the year's end.
    static func ageWords(_ year: PlanProgressYear) -> String? {
        guard let to = year.answerTo?.earliestAge else { return nil }
        guard let from = year.answerFrom?.earliestAge, from != to else { return "\(to), no change" }
        return "\(from) → \(to)"
    }

    /// "Why you're ahead", "Why you ended behind"; "Against your January
    /// plan" without the split.
    private var whyTitle: String {
        guard let explanation = year.explanation else { return "Against \(year.expectation(locale: locale))" }
        let side = explanation.end >= 0 ? "ahead" : "behind"
        return year.isLatest ? "Why you're \(side)" : "Why you ended \(side)"
    }

    var body: some View {
        let lines = self.lines
        VStack(alignment: .leading, spacing: Metrics.s) {
            CardRows {
                if let age = Self.ageWords(year) {
                    CardRow("Earliest age") {
                        Text(age)
                            .monospacedDigit()
                            .privacySensitiveInFeedback()
                    }
                }
                ForEach(lines) { line in
                    TimelineWordsRow(title: line.month, words: line.words, flagged: line.flagged)
                }
                if lines.isEmpty {
                    CardRow {
                        Text(year.isLatest ? "Nothing to note yet" : "Nothing to note")
                            .foregroundStyle(Palette.secondaryInk)
                    } value: {
                        EmptyView()
                    }
                }
                if year.position != nil || year.baseline == nil {
                    Button {
                        showsWhy = true
                    } label: {
                        CardRow(opens: true) {
                            Text(whyTitle)
                        } value: {
                            if let gap = year.position?.gap {
                                AmountText(gap, currency: card.currency, signed: true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            notes
        }
        .sheet(isPresented: $showsWhy) {
            whySheet
        }
        .pastPricesSheet(isPresented: $fillsPastPrices)
    }

    /// Why you're ahead or behind, in full: the four rows that add up to
    /// the gap, and what was planned.
    private var whySheet: some View {
        NavigationStack {
            ScrollView {
                Card {
                    PlanYearWhy(card: card)
                }
                .padding(Metrics.l)
            }
            .background(Palette.page)
            .sheetTitle(LocalizedStringKey(whyTitle)) { showsWhy = false }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    /// Check-ins that stop early, and missing prices or rates.
    @ViewBuilder
    private var notes: some View {
        if let note = PlanProgressText.pricesNote(year, locale: locale) {
            Text(note)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
                .padding(.horizontal, Metrics.l)
        }
        if !year.isComplete || card.actual.contains(where: { !$0.isComplete }) {
            OldPriceNoteView(text: "Some prices or exchange rates were missing: those holdings count as zero, "
                                 + "and the line is dotted there.",
                             systemImage: "exclamationmark.triangle") { fillsPastPrices = true }
                .padding(.horizontal, Metrics.l)
        }
    }

    /// A note's words as a row's value, without the period that ends it:
    /// "Passed 150.000 €".
    static func withoutFinalPeriod(_ sentence: AmountSentence) -> AmountSentence {
        var parts = sentence.parts
        guard case .words(let last) = parts.last, last.hasSuffix(".") else { return sentence }
        parts[parts.count - 1] = .words(String(last.dropLast()))
        return AmountSentence(parts: parts)
    }
}

/// The year's check-ins as a table under its chart on the Mac and iPad,
/// newest first: the month, the money in the plan, what you saved and what
/// markets did since the check-in before, the earliest age it recorded,
/// and how that moved ("1 sooner", "same").
struct PlanYearCheckIns: View {
    let card: PlanProgressTimeline.Card
    let history: PlanAnswerHistory

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    private struct Row: Identifiable {
        var date: CalendarDate
        var money: Decimal
        var saved: Decimal
        var markets: Decimal
        var age: Int?
        var moved: Int?
        var id: CalendarDate { date }
    }

    /// Each check-in of the year against the one before (the year's start for the first), newest first.
    private var rows: [Row] {
        let year = card.year
        let dates = library.valuator.checkInDates(in: .planAssets, through: year.to).filter { $0 > year.from }
        var rows: [Row] = []
        var previous = year.from
        var previousAge = year.answerFrom?.earliestAge
        for date in dates {
            let change = library.valuator.change(from: previous, to: date, in: .planAssets).total
            let age = history.points.first { $0.date == date }?.earliestAge
            var moved: Int?
            if let age, let previousAge { moved = age - previousAge }
            rows.append(Row(date: date, money: change.end, saved: change.saved, markets: change.market, age: age,
                            moved: moved))
            previous = date
            if let age { previousAge = age }
        }
        return rows.reversed()
    }

    var body: some View {
        let rows = self.rows
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text("Check-ins")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if rows.isEmpty {
                Text("No check-ins this year: what you held is valued at its prices.")
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Grid(alignment: .leading, horizontalSpacing: Metrics.l, verticalSpacing: 0) {
                    GridRow {
                        Text("Month")
                        Text("Money").gridColumnAlignment(.trailing)
                        Text("You saved").gridColumnAlignment(.trailing)
                        Text("Markets").gridColumnAlignment(.trailing)
                        Text("Age").gridColumnAlignment(.trailing)
                        Text("Moved").gridColumnAlignment(.trailing)
                    }
                    .font(.subheadline)
                    .foregroundStyle(Palette.mutedInk)
                    .padding(.bottom, Metrics.xs)
                    ForEach(rows) { row in
                        Divider()
                        GridRow {
                            Text(AmountFormat.monthName(row.date, locale: locale))
                                .foregroundStyle(Palette.ink)
                                .privacySensitiveInFeedback()
                            AmountText(row.money, currency: card.currency)
                            AmountText(row.saved, currency: card.currency)
                            AmountText(row.markets, currency: card.currency, signed: true)
                                .foregroundStyle(row.markets < 0 ? Palette.orangeStroke : Palette.ink)
                            Text(row.age.map { "\($0)" } ?? "–")
                                .monospacedDigit()
                                .privacySensitiveInFeedback()
                            Text(Self.moved(row.moved))
                                .foregroundStyle(Self.movedColor(row.moved))
                                .privacySensitiveInFeedback()
                        }
                        .lineLimit(1)
                        .padding(.vertical, 7)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// "1 y sooner", "2 y later", "same"; empty without ages to compare.
    static func moved(_ change: Int?) -> String {
        guard let change else { return "" }
        guard change != 0 else { return "same" }
        return "\(abs(change)) y \(change < 0 ? "sooner" : "later")"
    }

    private static func movedColor(_ change: Int?) -> Color {
        guard let change, change != 0 else { return Palette.mutedInk }
        return change < 0 ? Palette.accent : Palette.orangeStroke
    }
}

/// Why the year is ahead of or behind its baseline (PROGRESS.md, *Why*;
/// UI.md, "Year"), in the same four rows every year, so stepping
/// through the years moves nothing under it: the gap going into the year,
/// saving against the plan, markets against what was expected, and the
/// rest (inflation, values without what was saved, exchange rates). Each with a
/// bar and its amount, in whole units, adding up to the total; then what
/// the baseline expected.
struct PlanYearWhy: View {
    let card: PlanProgressTimeline.Card
    /// *Add What You Planned in 2021…*, for a year without a baseline.
    var onAddPastBaseline: ((Int) -> Void)?

    @Environment(\.locale) private var locale

    private var year: PlanProgressYear { card.year }

    private struct Row: Identifiable {
        var title: String
        var value: Decimal
        var id: String { title }
    }

    private func amount(_ value: Decimal) -> String {
        AmountFormat.amount(abs(value), currency: card.currency, locale: locale)
    }

    private func signed(_ value: Decimal) -> String {
        AmountFormat.signedAmount(value, currency: card.currency, locale: locale)
    }

    /// "Why you're ahead", "Why you ended behind"; "Against January" unmeasured.
    private var title: String {
        guard let explanation = year.explanation else { return "Against \(year.expectation(locale: locale))" }
        let side = explanation.end >= 0 ? "ahead" : "behind"
        return year.isLatest ? "Why you're \(side)" : "Why you ended \(side)"
    }

    private func rows(_ explanation: GapExplanation) -> [Row] {
        [Row(title: "At the start", value: explanation.start),
         Row(title: "Saving", value: explanation.saving),
         Row(title: "Markets", value: explanation.markets),
         Row(title: "Other", value: (explanation.inflation ?? 0) + explanation.other)]
    }

    /// "Ahead", "Behind".
    private func totalTitle(_ explanation: GapExplanation) -> String {
        explanation.end >= 0 ? "Ahead" : "Behind"
    }

    /// "January expected 141.463 € by 31 Dec.", "… by now."
    private var expected: AmountSentence? {
        PlanProgressText.expected(year, amount: { .amount(amount($0)) }, locale: locale).map { $0 + "." }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(title)
                .font(PlanProgressFont.text.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .privacySensitiveInFeedback()
                .accessibilityAddTraits(.isHeader)
            if let explanation = year.explanation?.inWholeUnits {
                let shown = rows(explanation)
                let largest = max(shown.map { abs($0.value) }.max() ?? 0, 1)
                Grid(alignment: .leading, horizontalSpacing: Metrics.s, verticalSpacing: Metrics.s) {
                    ForEach(shown) { row in
                        GridRow {
                            Text(row.title)
                                .foregroundStyle(Palette.ink)
                            PlanWhyBar(share: (abs(row.value) / largest).doubleValue, isPositive: row.value >= 0)
                            amountText(row.value)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Divider()
                        .gridCellColumns(3)
                    GridRow {
                        Text(totalTitle(explanation))
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.ink)
                            .privacySensitiveInFeedback()
                        Color.clear
                            .frame(height: 1)
                        amountText(explanation.end, isTotal: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                .font(PlanProgressFont.text)
                if let expected {
                    AmountSentenceText(expected)
                        .font(PlanProgressFont.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            } else {
                AmountSentenceText(PlanProgressText.january(year, currency: card.currency, locale: locale)
                    ?? AmountSentence(PlanProgressText.unmeasured(year)))
                    .font(PlanProgressFont.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if year.baseline == nil, let onAddPastBaseline {
                    Button("Add What You Planned in \(String(year.year))…") { onAddPastBaseline(year.year) }
                        .buttonStyle(.borderless)
                        .font(PlanProgressFont.text.weight(.semibold))
                        .personalControl()
                }
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    private func amountText(_ value: Decimal, isTotal: Bool = false) -> some View {
        Text(value == 0 ? amount(0) : signed(value))
            .fontWeight(isTotal ? .bold : .semibold)
            .monospacedDigit()
            .foregroundStyle(value == 0 ? Palette.mutedInk : value > 0 ? Palette.positive : Palette.orangeStroke)
            .privacySensitiveAmount()
            .gridColumnAlignment(.trailing)
            .lineLimit(1)
    }
}

/// A row's share of the largest in ``PlanYearWhy``: green for what put you
/// ahead, orange for what put you behind, on a grey track.
struct PlanWhyBar: View {
    let share: Double
    let isPositive: Bool

    var body: some View {
        Capsule()
            .fill(Palette.gridline.opacity(0.6))
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(isPositive ? Palette.green : Palette.orange)
                        .frame(width: max(share > 0 ? 3 : 0, proxy.size.width * CGFloat(min(1, max(0, share)))))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 6, maxHeight: 6)
            .accessibilityHidden(true)
    }
}

