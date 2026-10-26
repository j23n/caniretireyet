import Model
import Planner
import SwiftUI
import Tracker

// The chosen year in tiles and rows (UI.md, "Year"), under its chart:
// what you saved and what markets did, why you're ahead or behind, your
// money, the earliest age and the check-ins, month by month, and what
// happened.

/// The year as tiles: what you saved and what markets did, small ("💰 You
/// saved", "15.890 €", "planned 13.463 € by now"; "📈 Markets added",
/// "8.940 €", "expected 1.982 €"); why you're ahead or behind, wide
/// (``PlanYearWhyTile``); your money now or at the year's end, wide; and
/// the earliest age over the year and the year's check-ins, half tiles,
/// the check-ins opening their table.
struct PlanYearTiles: View {
    let card: PlanProgressTimeline.Card
    let history: PlanAnswerHistory

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
                .tileSize(.small)
            figureTile(market >= 0 ? "Markets added" : "Markets took", emoji: market >= 0 ? "📈" : "📉",
                       tint: market >= 0 ? .sky : .peach, value: market, detail: marketsDetail)
                .tileSize(.small)
            if PlanYearWhyTile.shows(year) {
                PlanYearWhyTile(card: card)
                    .tileSize(.wide)
            }
            moneyTile
                .tileSize(.wide)
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

    private func figureTile(_ title: String, emoji: String, tint: TileTint, value: Decimal,
                            detail: AmountSentence?) -> some View {
        ColorTile(tint: tint) {
            TileLabel(title, emoji: emoji)
            Spacer(minLength: Metrics.s)
            AmountText(abs(value), currency: card.currency, tabular: false)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                TileCaption {
                    AmountSentenceText(detail)
                }
            }
        }
        .accessibilityElement(children: .combine)
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

/// Why you're ahead or behind as a wide tile (UI.md, "Year"): "🚀 Why
/// you're ahead" with the gap, then the four rows that add up to it as bars
/// (``PlanYearWhy``'s); a tap opens them in full with what was planned.
/// Without the split, what the year is measured against and why not.
struct PlanYearWhyTile: View {
    let card: PlanProgressTimeline.Card

    @Environment(\.locale) private var locale
    @State private var showsWhy = false

    private var year: PlanProgressYear { card.year }

    /// Whether the year has a why to tell: a position against its baseline,
    /// or no baseline, which it says how to add.
    static func shows(_ year: PlanProgressYear) -> Bool {
        year.position != nil || year.baseline == nil
    }

    var body: some View {
        Button {
            showsWhy = true
        } label: {
            ColorTile {
                HStack(spacing: Metrics.s) {
                    TileLabel(PlanYearWhy.title(year, locale: locale), emoji: emoji)
                        .privacySensitiveInFeedback()
                    Spacer(minLength: Metrics.s)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.mutedInk)
                }
                if let explanation = year.explanation?.inWholeUnits {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                        Text(verbatim: AmountFormat.signedAmount(explanation.end, currency: card.currency,
                                                                 locale: locale))
                            .font(.title2.bold())
                            .monospacedDigit()
                            .foregroundStyle(explanation.end >= 0 ? Palette.positive : Palette.orangeStroke)
                            .privacySensitiveAmount()
                        Text("against \(year.expectation(locale: locale))")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .privacySensitiveInFeedback()
                    }
                    .padding(.top, Metrics.s)
                    PlanYearWhyBars(explanation: explanation, currency: card.currency)
                        .padding(.top, Metrics.m)
                } else {
                    AmountSentenceText(PlanProgressText.january(year, currency: card.currency, locale: locale)
                        ?? AmountSentence(PlanProgressText.unmeasured(year)))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Metrics.s)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows why in full")
        .sheet(isPresented: $showsWhy) {
            NavigationStack {
                ScrollView {
                    Card {
                        PlanYearWhy(card: card)
                    }
                    .padding(Metrics.l)
                }
                .background(Palette.page)
                .sheetTitle(LocalizedStringKey(PlanYearWhy.title(year, locale: locale))) { showsWhy = false }
            }
            .presentationDetents([.medium, .large])
            #if os(macOS)
            .frame(minWidth: 420, minHeight: 360)
            #endif
        }
    }

    /// 🚀 ahead, 🧭 behind, 📏 unmeasured.
    private var emoji: String {
        guard let explanation = year.explanation else { return "📏" }
        return explanation.end >= 0 ? "🚀" : "🧭"
    }
}

/// What happened in the year (UI.md, "Year"), a row each on a card,
/// newest first: an emoji on a tinted square, what it was ("Markets fell"),
/// its month and a few words ("June, 4%"), and its figure in a capsule,
/// green when it's good news and orange when not ("−3.100 €", "56 → 55").
/// How the earliest age moved over the year comes first. Milestones aren't
/// here: they have their own tiles. Under the card, check-ins that stop
/// early, and missing prices or rates.
struct PlanYearHappenings: View {
    let card: PlanProgressTimeline.Card

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
    }

    struct Row: Identifiable {
        var id: Int
        var emoji: String
        var tint: TileTint
        var title: String
        /// Its month and a few words: "June, 4%".
        var detail: String
        /// Its figure; an amount in it hides with the eye.
        var figure: AmountSentence?
        /// Whether the figure is the person's data other than an amount
        /// (an age), hidden in a feedback screenshot.
        var personalFigure = false
        var tone: Tone = .neutral
    }

    /// "56 → 55", "55, no change"; `nil` without an age at the year's end.
    static func ageWords(_ year: PlanProgressYear) -> String? {
        guard let to = year.answerTo?.earliestAge else { return nil }
        guard let from = year.answerFrom?.earliestAge, from != to else { return "\(to), no change" }
        return "\(from) → \(to)"
    }

    /// The earliest age over the year, then each event, newest first.
    static func rows(_ card: PlanProgressTimeline.Card, locale: Locale = .current) -> [Row] {
        let year = card.year
        let money = PlanWords(currency: card.currency, locale: locale)
        var rows: [Row] = []
        func add(_ emoji: String, _ tint: TileTint, _ title: String, _ detail: String, _ figure: AmountSentence?,
                 personal: Bool = false, tone: Tone = .neutral) {
            rows.append(Row(id: rows.count, emoji: emoji, tint: tint, title: title, detail: detail, figure: figure,
                            personalFigure: personal, tone: tone))
        }
        if let age = ageWords(year) {
            let moved = year.answerFrom?.earliestAge.flatMap { from in
                year.answerTo?.earliestAge.map { $0 - from }
            } ?? 0
            let detail = moved == 0 ? (year.isLatest ? "No change so far" : "No change")
                : PlanProgressText.move(years: moved).capitalizedFirst + (year.isLatest ? " so far" : "")
            add("🗓️", .sky, "Earliest age", detail, AmountSentence(age), personal: true,
                tone: moved < 0 ? .good : moved > 0 ? .bad : .neutral)
        }
        for event in card.events.reversed() {
            let month = AmountFormat.monthName(event.date, locale: locale)
            switch event.kind {
            case let .answerMoved(age, years, again, planChanged):
                let move = again ? "\(age) again" : PlanProgressText.move(years: years)
                add(planChanged ? "✏️" : years < 0 ? "⏪" : "⏩", planChanged ? .lilac : years < 0 ? .mint : .peach,
                    planChanged ? "Plan changed" : "Earliest age moved", "\(month), \(move)",
                    AmountSentence("\(age)"), personal: true, tone: years < 0 ? .good : years > 0 ? .bad : .neutral)
            case .changed(let changes):
                let title = changes.first?.label ?? "Plan changed"
                let more = changes.dropFirst().map(\.label.localizedLowercase)
                add(changes.contains(.plan) ? "✏️" : "⚙️", .lilac, title, ([month] + more).joined(separator: ", "),
                    nil)
            case .noAge:
                add("⚠️", .peach, "No age worked out", month, nil, tone: .bad)
            case .savedMore(let saved):
                add("💪", .mint, "Saved more than usual", month, "\(money.unsigned(saved))", tone: .good)
            case let .markets(markets, share):
                let percent = AmountFormat.percent(abs(share.doubleValue), digits: 0, locale: locale)
                add(markets < 0 ? "📉" : "📈", markets < 0 ? .peach : .sky, markets < 0 ? "Markets fell" : "Markets rose",
                    "\(month), \(percent)",
                    .amount(AmountFormat.signedAmount(markets, currency: card.currency, locale: locale)),
                    tone: markets < 0 ? .bad : .good)
            }
        }
        return rows
    }

    var body: some View {
        let rows = Self.rows(card, locale: locale)
        VStack(alignment: .leading, spacing: Metrics.s) {
            CardRows {
                ForEach(rows) { row in
                    PlanYearHappeningRow(row: row)
                }
                if rows.isEmpty {
                    CardRow {
                        Text(year.isLatest ? "Nothing to note yet" : "Nothing to note")
                            .foregroundStyle(Palette.secondaryInk)
                    } value: {
                        EmptyView()
                    }
                }
            }
            notes
        }
        .pastPricesSheet(isPresented: $fillsPastPrices)
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

/// One thing that happened in the year (``PlanYearHappenings``).
private struct PlanYearHappeningRow: View {
    let row: PlanYearHappenings.Row

    var body: some View {
        HStack(spacing: Metrics.m) {
            Text(verbatim: row.emoji)
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(row.tint.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(PlanProgressFont.text.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(row.detail)
                    .font(PlanProgressFont.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .privacySensitiveInFeedback()
            }
            Spacer(minLength: Metrics.s)
            if let figure = row.figure {
                AmountSentenceText(figure)
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(row.tone.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(row.tone.surface, in: Capsule())
                    .privacySensitiveInFeedback(row.personalFigure)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// What you saved and what markets did at each check-in of the year, a
/// pair of bars a month on one scale, up from a line for what was added
/// and down for what was taken (UI.md, "Year"), the months' initials under
/// them, months to come a grey dash and a skipped month empty. iPhone; the Mac and iPad have the table
/// (``PlanYearCheckIns``).
struct PlanYearMonthsCard: View {
    let card: PlanProgressTimeline.Card

    @Environment(LibraryStore.self) private var library
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.locale) private var locale

    private static let height: CGFloat = 120

    /// What was saved and what markets did, by month of the year.
    private var months: [Int: (saved: Decimal, markets: Decimal)] {
        var months: [Int: (saved: Decimal, markets: Decimal)] = [:]
        for row in PlanYearCheckIn.rows(of: card.year, valuator: library.valuator) {
            let month = months[row.date.month] ?? (0, 0)
            months[row.date.month] = (month.saved + row.saved, month.markets + row.markets)
        }
        return months
    }

    var body: some View {
        let months = self.months
        Card {
            HStack(spacing: Metrics.m) {
                legend("💰 You saved", color: TileTint.mint.accent)
                legend("📈 Markets", color: TileTint.sky.accent)
            }
            .font(.caption)
            .foregroundStyle(Palette.secondaryInk)
            if months.isEmpty {
                Text("No check-ins this year: what you held is valued at its prices.")
                    .font(PlanProgressFont.text)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: Metrics.xs) {
                    bars(months)
                        .frame(height: Self.height)
                    HStack(spacing: 0) {
                        ForEach(1...12, id: \.self) { month in
                            Text(PlanYearCardView.initial(month, locale: locale))
                                .font(.caption2)
                                .foregroundStyle(Palette.mutedInk)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityLabel(months)))
            }
        } header: {
            SectionHeader("Month by month")
        }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: Metrics.xs) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 9, height: 9)
            Text(title)
        }
    }

    /// Two bars a month from the line, to the largest up and down.
    private func bars(_ months: [Int: (saved: Decimal, markets: Decimal)]) -> some View {
        let values = months.values.flatMap { [$0.saved.doubleValue, $0.markets.doubleValue] }
        let up = max(values.max() ?? 0, 0)
        let down = max(-(values.min() ?? 0), 0)
        let saved = TileTint.mint.accent
        let markets = TileTint.sky.accent
        // Months to come are a grey dash; a skipped month draws nothing, its
        // money counted at the next check-in.
        let lastMonth = card.year.isLatest ? months.keys.max() ?? 0 : 12
        return Canvas { context, size in
            let span = max(up + down, 1)
            let zero = size.height * up / span
            let slot = size.width / 12
            let bar = max(3, slot * 0.3)
            func draw(_ value: Double, x: CGFloat, color: Color) {
                let length = max(abs(value) / span * size.height, value == 0 ? 0 : 2)
                let rect = CGRect(x: x, y: value >= 0 ? zero - length : zero, width: bar, height: length)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
            }
            for month in 1...12 {
                let x = CGFloat(month - 1) * slot + slot / 2
                if let value = months[month] {
                    draw(value.saved.doubleValue, x: x - bar - 1, color: saved)
                    draw(value.markets.doubleValue, x: x + 1, color: markets)
                } else if month > lastMonth {
                    let rect = CGRect(x: x - bar - 1, y: zero - 1.5, width: 2 * bar + 2, height: 3)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Palette.gridline))
                }
            }
            var line = Path()
            line.move(to: CGPoint(x: 0, y: zero))
            line.addLine(to: CGPoint(x: size.width, y: zero))
            context.stroke(line, with: .color(Palette.border), lineWidth: 1)
        }
        .privacySensitiveInFeedback()
    }

    /// Each month with a check-in: "September: saved 1.500 €, markets
    /// +2.950 €"; the months alone while amounts are hidden.
    private func accessibilityLabel(_ months: [Int: (saved: Decimal, markets: Decimal)]) -> String {
        let hidden = redactionReasons.hidesAmounts
        let lines = months.keys.sorted().compactMap { month -> String? in
            guard let value = months[month],
                  let date = CalendarDate(year: card.year.year, month: month, day: 1) else { return nil }
            let name = AmountFormat.monthName(date, locale: locale)
            guard !hidden else { return name }
            let saved = AmountFormat.amount(value.saved, currency: card.currency, locale: locale)
            let markets = AmountFormat.signedAmount(value.markets, currency: card.currency, locale: locale)
            return "\(name): saved \(saved), markets \(markets)"
        }
        return "What you saved and what markets did, month by month. " + lines.joined(separator: "; ")
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

    private func amount(_ value: Decimal) -> String {
        AmountFormat.amount(abs(value), currency: card.currency, locale: locale)
    }

    /// "Why you're ahead", "Why you ended behind"; "Against your January
    /// plan" unmeasured.
    static func title(_ year: PlanProgressYear, locale: Locale = .current) -> String {
        guard let explanation = year.explanation else { return "Against \(year.expectation(locale: locale))" }
        let side = explanation.end >= 0 ? "ahead" : "behind"
        return year.isLatest ? "Why you're \(side)" : "Why you ended \(side)"
    }

    /// "January expected 141.463 € by 31 Dec.", "… by now."
    private var expected: AmountSentence? {
        PlanProgressText.expected(year, amount: { .amount(amount($0)) }, locale: locale).map { $0 + "." }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(Self.title(year, locale: locale))
                .font(PlanProgressFont.text.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .privacySensitiveInFeedback()
                .accessibilityAddTraits(.isHeader)
            if let explanation = year.explanation?.inWholeUnits {
                PlanYearWhyBars(explanation: explanation, currency: card.currency, showsTotal: true)
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
}

/// The four rows that add up to a year's gap (``PlanYearWhy``): the gap
/// going into the year, saving against the plan, markets against what was
/// expected, and the rest, each with a bar against the largest and its
/// amount; with `showsTotal`, the gap under a hairline.
struct PlanYearWhyBars: View {
    /// In whole units.
    let explanation: GapExplanation
    let currency: CurrencyCode
    var showsTotal = false

    @Environment(\.locale) private var locale

    private struct Row: Identifiable {
        var title: String
        var value: Decimal
        var id: String { title }
    }

    private var rows: [Row] {
        [Row(title: "At the start", value: explanation.start),
         Row(title: "Saving", value: explanation.saving),
         Row(title: "Markets", value: explanation.markets),
         Row(title: "Other", value: (explanation.inflation ?? 0) + explanation.other)]
    }

    var body: some View {
        let shown = rows
        let largest = max(shown.map { abs($0.value) }.max() ?? 0, 1)
        Grid(alignment: .leading, horizontalSpacing: Metrics.s, verticalSpacing: Metrics.s) {
            ForEach(shown) { row in
                GridRow {
                    Text(row.title)
                        .foregroundStyle(Palette.ink)
                    PlanWhyBar(share: (abs(row.value) / largest).doubleValue, isPositive: row.value >= 0)
                    amountText(row.value)
                }
            }
            if showsTotal {
                Divider()
                    .gridCellColumns(3)
                GridRow {
                    Text(explanation.end >= 0 ? "Ahead" : "Behind")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                        .privacySensitiveInFeedback()
                    Color.clear
                        .frame(height: 1)
                    amountText(explanation.end, isTotal: true)
                }
            }
        }
    }

    private func amountText(_ value: Decimal, isTotal: Bool = false) -> some View {
        Text(value == 0 ? AmountFormat.amount(0, currency: currency, locale: locale)
            : AmountFormat.signedAmount(value, currency: currency, locale: locale))
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

