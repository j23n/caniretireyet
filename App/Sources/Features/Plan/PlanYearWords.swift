import Glance
import Model
import Planner
import SwiftUI
import Tracker

// The chosen year under its chart (UI.md, "So far"): its tiles, then the
// year month by month, on a line.

/// The year as tiles: what you saved and what markets did, half tiles
/// ("💰 You saved", "15.890 €", "planned 13.463 € by now"; "📈 Markets
/// added", "8.940 €", "expected 1.982 €"); your money now or at the year's
/// end, small; then, when money in and out was recorded in it, the year's
/// pay, wide (``SoFarPayTile``), its spending a month against the plan's
/// and its tax as a share of what came in; and the earliest age at its end
/// and its check-ins, half tiles, the check-ins opening their table.
struct PlanYearTiles: View {
    let card: PlanProgressTimeline.Card
    let history: PlanAnswerHistory
    /// The year's money in and out (a calendar year's period); `nil`
    /// without money in and out, or with typed accounts.
    var money: MoneyInOutPeriod?
    /// The plan's own savings rate.
    var planRate: Decimal?
    /// The plan's spending while working, a year.
    var plannedSpending: Decimal?

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @State private var showsCheckIns = false

    private var year: PlanProgressYear { card.year }

    var body: some View {
        let saved = year.change.saved
        let market = year.change.market
        TileGrid {
            figureTile(saved >= 0 ? "You saved" : "You took out", emoji: "💰", tint: .mint, value: saved,
                       detail: savedDetail)
                .tileSize(.half)
            figureTile(market >= 0 ? "Markets added" : "Markets took", emoji: market >= 0 ? "📈" : "📉",
                       tint: market >= 0 ? .sky : .peach, value: market, detail: marketsDetail)
                .tileSize(.half)
            moneyTile
                .tileSize(.small)
            if let money, let pay = money.pay {
                SoFarPayTile(title: payTitle, pay: pay, oneOffs: money.oneOffs, planRate: planRate)
                    .tileSize(.wide)
                HalfTile(tint: .peach, title: "Spent", emoji: "🛒") {
                    AmountText(spentAMonth(money), currency: card.currency, tabular: false)
                } caption: {
                    AmountSentenceText(spentDetail)
                }
                .tileSize(.half)
                if let taxShare = Self.taxShare(money) {
                    HalfTile(tint: .peach, title: "Tax", emoji: "🧾") {
                        Text(verbatim: AmountFormat.percent(taxShare, digits: 0, locale: locale))
                            .monospacedDigit()
                            .privacySensitiveInFeedback()
                    } caption: {
                        Text("of what came in")
                    }
                    .tileSize(.half)
                }
            }
            if let to = year.answerTo?.earliestAge {
                HalfTile(tint: .lilac, title: "Earliest age to stop", emoji: "🧭") {
                    Text(verbatim: "\(to)")
                        .monospacedDigit()
                        .privacySensitiveInFeedback()
                } caption: {
                    Text(verbatim: ageCaption(to: to))
                        .privacySensitiveInFeedback()
                }
                .tileSize(.half)
            }
            Button {
                showsCheckIns = true
            } label: {
                HalfTile(tint: .sky, title: year.isLatest ? "Check-ins this year" : "Check-ins that year",
                         emoji: "✅") {
                    Text(verbatim: "\(PlanYearCheckIn.rows(of: year, valuator: library.valuator).count)")
                        .monospacedDigit()
                } caption: {
                    Text("each one's figures ›")
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the year's check-ins")
            .tileSize(.half)
        }
        .sheet(isPresented: $showsCheckIns) {
            NavigationStack {
                ScrollView {
                    PlanYearCheckIns(card: card, history: history)
                        .padding(Metrics.l)
                }
                .background(Palette.page)
                .sheetTitle("Check-ins") { showsCheckIns = false }
            }
            .presentationDetents([.medium, .large])
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 360)
            #endif
        }
    }

    /// "📊 Your money now" (or "Your money at the year's end"), your money
    /// in the plan, and where the year started.
    private var moneyTile: some View {
        ColorTile {
            TileLabel(year.isLatest ? "Your money now" : "Your money at the year's end", emoji: "📊")
            Spacer(minLength: Metrics.s)
            AmountText(year.change.end, currency: card.currency, tabular: false)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            TileCaption {
                AmountSentenceText("started the year at \(amount: amount(year.change.start))")
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "was 56 at the year's start", "same as at the year's start"; "the
    /// plan's answer" without one from the year's start.
    private func ageCaption(to: Int) -> String {
        guard let from = year.answerFrom?.earliestAge else { return "the plan's answer" }
        return from == to ? "same as at the year's start" : "was \(from) at the year's start"
    }

    /// A half tile's figure, what it was, and a few words.
    private func figureTile(_ title: String, emoji: String, tint: TileTint, value: Decimal,
                            detail: AmountSentence?) -> some View {
        HalfTile(tint: tint, title: title, emoji: emoji) {
            AmountText(abs(value), currency: card.currency, tabular: false)
        } caption: {
            if let detail {
                AmountSentenceText(detail)
            }
        }
    }

    private func amount(_ value: Decimal) -> String {
        AmountFormat.amount(abs(value), currency: card.currency, locale: locale)
    }

    /// "Your pay in 2026 so far", "Your pay in 2025".
    private var payTitle: String {
        "Your pay in \(String(year.year))" + (year.isSoFar ? " so far" : "")
    }

    /// The tax as a share of what came in before tax, e.g. 0.17; `nil`
    /// without tax or without anything coming in.
    static func taxShare(_ money: MoneyInOutPeriod) -> Decimal? {
        guard money.tax > 0, money.beforeTax > 0 else { return nil }
        return money.tax / money.beforeTax
    }

    /// What the year spent a month: what it spent scaled to a year, over 12.
    private func spentAMonth(_ money: MoneyInOutPeriod) -> Decimal {
        ((money.savings?.spentPerYear ?? 0) / 12).rounded(scale: 0)
    }

    /// "a month, plan 2.700 €", or "a month" without the plan's spending.
    private var spentDetail: AmountSentence {
        guard let plannedSpending, plannedSpending > 0 else { return "a month" }
        return "a month, plan \(amount: amount((plannedSpending / 12).rounded(scale: 0)))"
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

/// The year month by month (UI.md, "So far"), on a line like *Your life
/// ahead*'s: where the year started, the milestones it reached and what
/// happened at its check-ins in the order they came, each with its month,
/// and where it stands now or where it ended. Under it, check-ins that stop
/// early, and missing prices or rates.
struct PlanYearLine: View {
    let card: PlanProgressTimeline.Card
    let text: PlanMilestoneText

    @Environment(\.locale) private var locale
    @State private var fillsPastPrices = false

    private var year: PlanProgressYear { card.year }

    /// Good news, bad news, or neither.
    enum Tone {
        case good, bad, neutral

        var ink: Color {
            switch self {
            case .good: Palette.positive
            case .bad: Palette.orangeStroke
            case .neutral: Palette.ink
            }
        }

        var surface: Color {
            switch self {
            case .good: Palette.positive.opacity(0.12)
            case .bad: Palette.orange.opacity(0.16)
            case .neutral: Palette.page
            }
        }

        /// Its dot on the line.
        var dot: Color {
            switch self {
            case .good: Palette.positive
            case .bad: Palette.orangeStroke
            case .neutral: Palette.mutedInk
            }
        }
    }

    /// One stop on the line.
    struct Entry: Identifiable {
        enum Kind {
            /// Where the year started.
            case start
            /// Something that happened at a check-in.
            case event
            /// A milestone reached.
            case milestone
            /// Now, or the year's end.
            case end
        }

        var id: Int
        var kind: Kind
        var date: CalendarDate
        /// "Mar".
        var month: String
        var emoji: String?
        /// What it was: "Markets fell 4%", "10 years of spending"; an amount
        /// in it hides with the eye.
        var title: AmountSentence
        /// Whether the title is the person's data (a share of their money),
        /// hidden in a feedback screenshot.
        var personalTitle = false
        /// Its figure; an amount in it hides with the eye.
        var figure: AmountSentence?
        /// Whether the figure is the person's data other than an amount
        /// (an age), hidden in a feedback screenshot.
        var personalFigure = false
        var tone: Tone = .neutral
    }

    /// The year's stops in order: its start, its events and milestones by
    /// date, then now or its end.
    static func entries(_ card: PlanProgressTimeline.Card, text: PlanMilestoneText) -> [Entry] {
        let year = card.year
        let locale = text.locale
        let money = PlanWords(currency: card.currency, locale: locale)
        func month(_ date: CalendarDate) -> String { GlanceText.shortMonth(date, locale: locale) }
        var middle: [(date: CalendarDate, entry: Entry)] = []
        func add(_ kind: Entry.Kind, _ date: CalendarDate, _ emoji: String, _ title: AmountSentence,
                 personalTitle: Bool = false, figure: AmountSentence? = nil, personalFigure: Bool = false,
                 tone: Tone = .neutral) {
            middle.append((date, Entry(id: 0, kind: kind, date: date, month: month(date), emoji: emoji, title: title,
                                       personalTitle: personalTitle, figure: figure, personalFigure: personalFigure,
                                       tone: tone)))
        }
        for event in card.events {
            switch event.kind {
            case let .answerMoved(age, years, again, planChanged):
                let figure = again ? "\(age) again" : "\(age - years) → \(age)"
                add(.event, event.date, planChanged ? "✏️" : years < 0 ? "⏪" : "⏩",
                    planChanged ? "Plan changed" : "Earliest age moved", figure: AmountSentence(figure),
                    personalFigure: true, tone: years < 0 ? .good : years > 0 ? .bad : .neutral)
            case .changed(let changes):
                add(.event, event.date, changes.contains(.plan) ? "✏️" : "⚙️",
                    AmountSentence(changes.map(\.label).joined(separator: " · ")))
            case .noAge:
                add(.event, event.date, "⚠️", "No age worked out", tone: .bad)
            case .savedMore(let saved):
                add(.event, event.date, "💪", "Saved more than usual", figure: "\(money.unsigned(saved))",
                    tone: .good)
            case let .markets(markets, share):
                let percent = AmountFormat.percent(abs(share.doubleValue), digits: 0, locale: locale)
                add(.event, event.date, markets < 0 ? "📉" : "📈",
                    AmountSentence(markets < 0 ? "Markets fell \(percent)" : "Markets rose \(percent)"),
                    personalTitle: true,
                    figure: .amount(AmountFormat.signedAmount(markets, currency: card.currency, locale: locale)),
                    tone: markets < 0 ? .bad : .good)
            }
        }
        for reached in card.milestones {
            add(.milestone, reached.date, "🏁", text.name(reached.milestone), tone: .good)
        }
        // By date; on the same day, events before milestones, as they were added.
        let sorted = middle.enumerated().sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element.entry)
        let opened = year.from.year < year.year ? CalendarDate(year: year.year, month: 1, day: 1) ?? year.from
            : year.from
        var entries = [Entry(id: 0, kind: .start, date: opened, month: month(opened),
                             title: year.from.year < year.year ? "Started the year" : "First values",
                             figure: money.amount(year.change.start))]
        entries += sorted
        entries.append(Entry(id: 0, kind: .end, date: year.to, month: month(year.to),
                             title: year.isLatest ? "Now" : "The year's end",
                             figure: money.amount(year.change.end)))
        for index in entries.indices {
            entries[index].id = index
        }
        return entries
    }

    var body: some View {
        let entries = Self.entries(card, text: text)
        VStack(alignment: .leading, spacing: Metrics.s) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    HStack(alignment: .top, spacing: Metrics.m) {
                        rail(entry, isLast: entry.id == entries.count - 1)
                        row(entry)
                            .padding(.bottom, Metrics.s)
                    }
                    // As tall as the row, so the line reaches the next dot.
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            notes
        }
        .pastPricesSheet(isPresented: $fillsPastPrices)
    }

    /// The line down the left: a ring where the year started and, in the
    /// entry's tone, at each event; filled for a milestone, and in ink for
    /// now or the year's end.
    private func rail(_ entry: Entry, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            Group {
                switch entry.kind {
                case .start:
                    Circle()
                        .strokeBorder(Palette.mutedInk, lineWidth: 2)
                case .event:
                    Circle()
                        .strokeBorder(entry.tone.dot, lineWidth: 2)
                case .milestone:
                    Circle()
                        .fill(TileTint.butter.accent)
                case .end:
                    Circle()
                        .fill(Palette.ink)
                }
            }
            .frame(width: 12, height: 12)
            .padding(.top, 14)
            if !isLast {
                Rectangle()
                    .fill(Palette.border)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 12)
        .accessibilityHidden(true)
    }

    /// The month, what it was and its figure, on a card; a milestone on
    /// butter, now or the year's end in ink.
    private func row(_ entry: Entry) -> some View {
        let isEnd = entry.kind == .end
        let ink: Color = isEnd ? Palette.card : entry.kind == .milestone ? TileTint.butter.ink : Palette.ink
        return HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(verbatim: entry.month)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(isEnd ? Palette.card.opacity(0.75) : Palette.secondaryInk)
                .frame(minWidth: 34, alignment: .leading)
                .fixedSize()
                .privacySensitiveInFeedback()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let emoji = entry.emoji {
                    Text(verbatim: emoji)
                        .accessibilityHidden(true)
                }
                AmountSentenceText(entry.title)
                    .fontWeight(entry.kind == .event ? .regular : .semibold)
                    .lineLimit(2)
                    .privacySensitiveInFeedback(entry.personalTitle)
            }
            .font(PlanProgressFont.text)
            .foregroundStyle(ink)
            Spacer(minLength: Metrics.s)
            figure(entry, ink: ink)
        }
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            switch entry.kind {
            case .end: shape.fill(Palette.ink)
            case .milestone: shape.fill(TileTint.butter.surface)
            case .start, .event: Color.clear.cardSurface()
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func figure(_ entry: Entry, ink: Color) -> some View {
        switch entry.kind {
        case .milestone:
            Text("reached")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ink)
        case .start, .end:
            if let figure = entry.figure {
                AmountSentenceText(figure)
                    .font(PlanProgressFont.text.weight(entry.kind == .end ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(entry.kind == .end ? ink : Palette.secondaryInk)
                    .lineLimit(1)
                    .fixedSize()
            }
        case .event:
            if let figure = entry.figure {
                AmountSentenceText(figure)
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(entry.tone.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(entry.tone.surface, in: Capsule())
                    .privacySensitiveInFeedback(entry.personalFigure)
            }
        }
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
}

/// A check-in of a year against the one before it (the year's start for
/// the first): your money then, what you saved and what markets did since.
struct PlanYearCheckIn: Identifiable {
    var date: CalendarDate
    var money: Decimal
    var saved: Decimal
    var markets: Decimal
    var id: CalendarDate { date }

    /// The check-ins of plan assets in `year`, oldest first.
    static func rows(of year: PlanProgressYear, valuator: Valuator) -> [PlanYearCheckIn] {
        let dates = valuator.checkInDates(in: .planAssets, through: year.to).filter { $0 > year.from }
        var rows: [PlanYearCheckIn] = []
        var previous = year.from
        for date in dates {
            let change = valuator.change(from: previous, to: date, in: .planAssets).total
            rows.append(PlanYearCheckIn(date: date, money: change.end, saved: change.saved, markets: change.market))
            previous = date
        }
        return rows
    }
}

/// The year's check-ins as a table, in the sheet the *Check-ins* tile
/// opens, newest first: the month, the money in the plan, what you saved and what
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
        var rows: [Row] = []
        var previousAge = year.answerFrom?.earliestAge
        for checkIn in PlanYearCheckIn.rows(of: year, valuator: library.valuator) {
            let age = history.points.first { $0.date == checkIn.date }?.earliestAge
            var moved: Int?
            if let age, let previousAge { moved = age - previousAge }
            rows.append(Row(date: checkIn.date, money: checkIn.money, saved: checkIn.saved,
                            markets: checkIn.markets, age: age, moved: moved))
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
                // No modifiers on the rows themselves: they'd turn each into one cell.
                Grid(alignment: .leading, horizontalSpacing: Metrics.l, verticalSpacing: 7) {
                    GridRow {
                        header("Month")
                        header("Money").gridColumnAlignment(.trailing)
                        header("You saved").gridColumnAlignment(.trailing)
                        header("Markets").gridColumnAlignment(.trailing)
                        header("Age").gridColumnAlignment(.trailing)
                        header("Moved").gridColumnAlignment(.trailing)
                    }
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
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// A column's header: small and grey.
    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(Palette.mutedInk)
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

