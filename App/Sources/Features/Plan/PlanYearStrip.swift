import Model
import Planner
import SwiftUI
import Tracker

// Progress year by year (UI.md, "Progress"): the strip of years, each a
// card with your money through the year against what January expected.

/// The answer at a check-in, on a year's card: outlined where the year
/// starts, in the accent when it came sooner, grey when later, violet when
/// the plan changed.
struct PlanAnswerChip: View {
    let age: Int
    let kind: PlanProgressTimeline.Chip.Kind
    /// How much it has grown with the text size, on a card.
    var scale: CGFloat = 1

    static let width: CGFloat = 28

    var body: some View {
        Text(verbatim: "\(age)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .frame(width: Self.width * scale, height: 18 * scale)
            .background(background, in: Capsule())
            .overlay {
                if kind == .start {
                    Capsule().strokeBorder(Palette.border, lineWidth: 1)
                }
            }
    }

    private var foreground: Color {
        switch kind {
        case .start: Palette.ink
        case .sooner: Palette.accent
        case .later: Palette.secondaryInk
        case .planChanged: Palette.violet
        }
    }

    private var background: Color {
        switch kind {
        case .start: Palette.card
        case .sooner: Palette.accent.opacity(0.12)
        case .later: Palette.gridline.opacity(0.6)
        case .planChanged: Palette.violet.opacity(0.15)
        }
    }
}

// MARK: - The strip of years

/// The years side by side on a strip that opens at today, on the right, on
/// one money scale, so December of one year meets January of the next.
/// Choosing a card selects its year; on iPhone its words show below the
/// strip, on the Mac and iPad each card shows its own. Selecting one
/// elsewhere scrolls it into view.
struct PlanYearStrip: View {
    let timeline: PlanProgressTimeline
    /// The index of the selected card.
    @Binding var selection: Int
    /// Points a month along the time axis.
    var pointsPerMonth: CGFloat = 21
    /// The strip's insets at its ends, so its cards line up with the page.
    var leadingInset: CGFloat = Metrics.l
    var trailingInset: CGFloat = Metrics.l
    /// Whether each card shows its year's words under its graph (the Mac and iPad).
    var showsWords = false
    /// Today, marked on the latest year's card.
    var today: CalendarDate?
    /// *Add What You Planned in 2021…*, for a year without a baseline.
    var onAddPastBaseline: ((Int) -> Void)?

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsEarlyYears = false
    /// Where the pointer is over a card, or where one was tapped.
    @State private var pointer: PlanGraphPointer?
    /// The cards the money scale is fitted to: those on screen when the
    /// strip last came to rest; the chosen one and those beside it before.
    @State private var fitted: Set<Int> = []
    @State private var onScreen = PlanCardsOnScreen()

    /// The oldest years, before the first with a recorded answer: folded
    /// into one card until shown.
    private var earlyCount: Int {
        timeline.cards.firstIndex { $0.year.answerTo != nil } ?? 0
    }

    var body: some View {
        let early = earlyCount
        let folds = early > 0 && !showsEarlyYears && selection >= early
        let scale = timeline.scale(fitting: fitted.isEmpty ? [selection - 1, selection, selection + 1] : fitted)
        // The words above and below the graph grow with the text size, up to a point.
        let textScale = typeSize.stripCardScale
        let height = PlanYearCardView.height(textScale: textScale)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Metrics.s) {
                    if folds {
                        PlanEarlyYearsCard(cards: Array(timeline.cards.prefix(early)), height: height,
                                           isCompact: !showsWords) {
                            withAnimation(.snappy) { showsEarlyYears = true }
                        }
                    }
                    ForEach(Array(timeline.cards.enumerated()), id: \.element.id) { index, card in
                        if !folds || index >= early {
                            yearCard(card, index: index, scale: scale, height: height, textScale: textScale)
                                .id(index)
                                .onScrollVisibilityChange(threshold: 0.1) { isVisible in
                                    onScreen.set(index, isVisible)
                                    if !onScreen.isScrolling { fitScale() }
                                }
                        }
                    }
                }
                .padding(.leading, leadingInset)
                .padding(.trailing, trailingInset)
                .padding(.vertical, 2)
                .dynamicTypeSize(...DynamicTypeSize.stripCardLimit)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.trailing)
            // A finger reading a line moves the read-out, not the strip.
            .scrollDisabled(pointer?.byTouch == true)
            .onScrollPhaseChange { _, phase in
                onScreen.isScrolling = phase != .idle
                if phase == .idle { fitScale() }
            }
            .accessibilityIdentifier("progress.years")
            .onChange(of: selection) { _, index in
                // Once an early year is chosen, the early years stay laid out.
                if index < early { showsEarlyYears = true }
                withAnimation(.snappy) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    /// A year's card: its graph, which chooses it, and on the Mac and iPad
    /// its words under it.
    private func yearCard(_ card: PlanProgressTimeline.Card, index: Int, scale: PlanProgressTimeline.Scale?,
                          height: CGFloat, textScale: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let isSelected = selection == index
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                selection = index
            } label: {
                PlanYearCardView(card: card, scale: scale, pointsPerMonth: pointsPerMonth, height: height,
                                 pointerX: pointer?.index == index ? pointer?.x : nil, textScale: textScale,
                                 today: card.year.isLatest ? today : nil)
                    .planGraphPointer($pointer, index: index)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(accessibilityLabel(card)))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityChartDescriptor(chartSummary(card))
            if showsWords {
                PlanYearWords(card: card, onAddPastBaseline: onAddPastBaseline)
                    .padding(.horizontal, 14)
                    .padding(.top, Metrics.xs)
                    .padding(.bottom, 14)
                    .frame(width: PlanYearCardView.width(pointsPerMonth: pointsPerMonth), alignment: .leading)
            }
        }
        .background(Palette.card, in: shape)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: isSelected ? 2 : 1)
        }
    }

    /// Fits the money scale to the cards on screen (UI.md, "Progress"): at
    /// once the first time, then, once the strip comes to rest, with the
    /// lines fading to their new places.
    private func fitScale() {
        let shown = onScreen.cards
        guard !shown.isEmpty, shown != fitted else { return }
        if fitted.isEmpty {
            fitted = shown
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { fitted = shown }
        }
    }

    /// The year for VoiceOver's audio graph and chart details: your money at
    /// each check-in and month end, and what its baseline expected.
    private func chartSummary(_ card: PlanProgressTimeline.Card) -> ChartSummary {
        let day = { (date: Date) in AmountFormat.mediumDate(CalendarDate(date, in: .current), locale: self.locale) }
        var series = [ChartSummary.Series(name: "Your money", points: card.actual.map { (day($0.date), $0.value) })]
        let expected = card.actual.compactMap { point in card.expected(on: point.date).map { (day(point.date), $0) } }
        if !expected.isEmpty {
            series.append(ChartSummary.Series(name: "What you expected", points: expected))
        }
        let describe: @Sendable (Double) -> String
        if hidesAmounts {
            let hidden = AmountFormat.hidden
            describe = { _ in hidden }
        } else {
            describe = ChartStyle.spokenAmount(currency: card.currency)
        }
        return ChartSummary(
            title: card.year.title,
            summary: PlanProgressText.story(card.year, currency: card.currency, hidesAmounts: hidesAmounts,
                                            locale: locale),
            xTitle: "Date", yTitle: "Your money", series: series, describeValue: describe)
    }

    private func accessibilityLabel(_ card: PlanProgressTimeline.Card) -> String {
        var label = card.year.title
        if !card.year.isLatest {
            label += ", " + PlanProgressText.change(card.year, currency: card.currency, hidesAmounts: hidesAmounts,
                                                    locale: locale)
        }
        if let against = PlanProgressText.againstJanuary(card.year, hidesAmounts: hidesAmounts, locale: locale) {
            label += ", \(against)"
        }
        if let summary = card.summary {
            label += ". \(summary)"
        }
        return label
    }
}

/// The cards of a strip on screen, as it reports them while it scrolls,
/// and whether it's scrolling. Nothing observes it: following them doesn't
/// draw the strip again.
@MainActor
final class PlanCardsOnScreen {
    private(set) var cards: Set<Int> = []
    var isScrolling = false

    func set(_ index: Int, _ isVisible: Bool) {
        if isVisible { cards.insert(index) } else { cards.remove(index) }
    }
}

/// The years before your first recorded answer, folded into one card: their
/// span, how plan assets moved over them, the milestones they passed, and
/// *Show* to lay them out. Narrow beside today's card on iPhone.
struct PlanEarlyYearsCard: View {
    let cards: [PlanProgressTimeline.Card]
    var height: CGFloat = PlanYearCardView.height(textScale: 1)
    /// Narrow, with the amounts in short, beside today's card on iPhone.
    var isCompact = false
    let onShow: () -> Void

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    private var span: String {
        guard let first = cards.first?.year.year, let last = cards.last?.year.year else { return "" }
        return first == last ? String(first) : "\(first)–\(last)"
    }

    private var moved: String? {
        guard let start = cards.first?.year.change.start, let end = cards.last?.year.change.end,
              let currency = cards.last?.currency else { return nil }
        guard !hidesAmounts else { return AmountFormat.hidden }
        if isCompact {
            return AmountFormat.compactAmount(start.doubleValue, currency: currency, locale: locale) + " → "
                + AmountFormat.compactAmount(end.doubleValue, currency: currency, locale: locale)
        }
        return AmountFormat.amount(start, currency: currency, locale: locale) + " → "
            + AmountFormat.amount(end, currency: currency, locale: locale)
    }

    /// "3 milestones" passed in them; `nil` without one.
    private var milestones: String? {
        let count = cards.reduce(0) { $0 + $1.milestones.count }
        guard count > 0 else { return nil }
        return count == 1 ? "A milestone" : "\(count) milestones"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(span)
                .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.7)
            if let moved {
                Text(moved)
                    .font(isCompact ? .caption : .subheadline)
                    .monospacedDigit()
                    .foregroundStyle(isCompact ? Palette.secondaryInk : Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isCompact {
                Text("Before your first answer.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                if let milestones {
                    Label(milestones, systemImage: "flag.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }
            }
            Spacer(minLength: 0)
            if isCompact {
                Button("Show", action: onShow)
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .accessibilityLabel("Show \(span)")
            } else {
                Button("Show", action: onShow)
                    .buttonStyle(.bordered)
            }
        }
        .padding(isCompact ? Metrics.s : 12)
        .frame(width: isCompact ? 72 : 150, height: height, alignment: .topLeading)
        .background(Palette.card, in: shape)
        .overlay { shape.strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
    }
}

/// One year on the strip: its change, where it ended against January, your
/// money through it (the line) against what January expected (dashed),
/// green where you're ahead and orange where behind, the months along its
/// bottom and the answer where it moved; the rest of the year still to
/// come shaded. The card names its own lines (*Today*, *January
/// expected*) and up to two of the milestones on them, so it needs no key.
struct PlanYearCardView: View {
    let card: PlanProgressTimeline.Card
    let scale: PlanProgressTimeline.Scale?
    var pointsPerMonth: CGFloat = 21
    var height: CGFloat = PlanYearCardView.height(textScale: 1)
    /// Where the pointer is over the card, or where it was tapped.
    var pointerX: CGFloat?
    /// How much its words have grown with the text size
    /// (``DynamicTypeSize/stripCardScale``).
    var textScale: CGFloat = 1
    /// Today, marked when it falls in the year (on the latest year's card).
    var today: CalendarDate?

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    private static let pad: CGFloat = 12
    private static let graphHeight: CGFloat = 150
    /// The header, which grows with the text size, and room above the
    /// graph for the top amount.
    private var graphTop: CGFloat { 54 * textScale + 20 }
    private var plotBottom: CGFloat { graphTop + Self.graphHeight }
    private var width: CGFloat { Self.width(pointsPerMonth: pointsPerMonth) }

    /// A card's width: its twelve months and its padding.
    static func width(pointsPerMonth: CGFloat) -> CGFloat {
        12 * pointsPerMonth + 2 * pad
    }

    /// A card's height: its header, the graph, and the months and answers
    /// under it, growing with the text size.
    static func height(textScale: CGFloat) -> CGFloat {
        186 + 98 * textScale
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(width: width, height: height)
            // A new fit of the scale fades the lines to their new places.
            .id(scale)
            .transition(.opacity)
            .accessibilityHidden(true)
            header
            if let scale {
                amountLabels(scale)
                expectedLabel(scale)
                milestoneLabels(scale)
            }
            todayLabel
            months
            chips
            if let pointerX {
                readout(at: pointerX)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private var aheadColor: Color {
        (card.year.position?.gap ?? 0) >= 0 ? Palette.positive : Palette.orangeStroke
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(verbatim: String(card.year.year))
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(PlanProgressText.change(card.year, currency: card.currency, hidesAmounts: hidesAmounts,
                                             locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(card.year.isLatest ? Palette.accent : Palette.ink)
            }
            if let against = PlanProgressText.againstJanuary(card.year, hidesAmounts: hidesAmounts, locale: locale) {
                Text(against)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(aheadColor)
            } else {
                Text(PlanProgressText.unmeasured(card.year))
                    .font(.caption)
                    .foregroundStyle(Palette.mutedInk)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: width - 2 * Self.pad, alignment: .leading)
        .offset(x: Self.pad, y: Self.pad)
    }

    /// A label on the graph: small, on the card's colour so a line under it doesn't cross it.
    private func graphLabel(_ text: String, weight: Font.Weight = .regular, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(weight))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 2)
            .background(Palette.card.opacity(0.85), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .fixedSize()
    }

    /// The amounts of the gridlines, above them at the card's edge where
    /// nothing is drawn: the right, where the rest of the year is still to
    /// come, unless the line ends there.
    private func amountLabels(_ scale: PlanProgressTimeline.Scale) -> some View {
        ForEach(hidesAmounts ? [] : scale.ticks.filter { $0 > scale.domain.lowerBound }, id: \.self) { tick in
            graphLabel(AmountFormat.compactAmount(tick, currency: card.currency, locale: locale),
                       color: Palette.mutedInk)
                .frame(width: width - 8, alignment: labelOnRight(tick, scale) ? .trailing : .leading)
                .offset(x: 4, y: y(tick, scale) - 16)
        }
    }

    /// Whether a gridline's amount goes at the right edge: where the line
    /// doesn't pass under it, else at the left when it's clear there.
    private func labelOnRight(_ tick: Double, _ scale: PlanProgressTimeline.Scale) -> Bool {
        let band = (y(tick, scale) - 17)...(y(tick, scale) + 1)
        let reach: CGFloat = 52
        func isClear(_ zone: ClosedRange<CGFloat>) -> Bool {
            !zip(card.actual, card.actual.dropFirst()).contains { from, to in
                let xs = min(x(from.date), x(to.date))...max(x(from.date), x(to.date))
                let ys = min(y(from.value, scale), y(to.value, scale))...max(y(from.value, scale), y(to.value, scale))
                return xs.overlaps(zone) && ys.overlaps(band)
            }
        }
        return isClear((width - reach)...width) || !isClear(0...reach)
    }

    /// *January expected* where the dashed line starts: under it when you
    /// start ahead of it, above it when behind, so it stays off your line.
    @ViewBuilder
    private func expectedLabel(_ scale: PlanProgressTimeline.Scale) -> some View {
        if let first = card.expected.first {
            let start = position(of: first, scale)
            let actual = card.actual.first { $0.date >= first.date }?.value ?? first.value
            let fitsBelow = start.y + 20 <= plotBottom
            let fitsAbove = start.y - 20 >= graphTop
            let below = actual >= first.value ? fitsBelow || !fitsAbove : !fitsAbove
            graphLabel("\(card.year.expectationTitle(locale: locale)) expected", color: Palette.secondaryInk)
                .offset(x: max(Self.pad, start.x) + 2, y: below ? start.y + 3 : start.y - 18)
        }
    }

    /// Where today falls on the card, when it's in the year and its label fits beside it.
    private var todayX: CGFloat? {
        guard let today, today.year == card.year.year else { return nil }
        let at = x(today.dateValue)
        return at + 38 <= width - 4 ? at : nil
    }

    /// *Today* at the top of the graph, beside its line.
    @ViewBuilder
    private var todayLabel: some View {
        if let todayX {
            Text("Today")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.accent)
                .fixedSize()
                .offset(x: todayX + 3, y: graphTop + 2)
        }
    }

    /// A milestone on the line, and its name when it's one of the two named.
    private struct Mark: Identifiable {
        var reached: ReachedMilestone
        var point: CGPoint
        var label: String?
        /// Whether its name goes left of its flag (else right).
        var labelOnLeft = true
        var id: ReachedMilestone.ID { reached.id }
    }

    /// The milestones on the line: the first and the last named, with a
    /// flag, when there's room for both; the rest small dots.
    private func marks(_ scale: PlanProgressTimeline.Scale) -> [Mark] {
        let text = PlanMilestoneText(currency: card.currency, hidesAmounts: hidesAmounts, locale: locale)
        var marks: [Mark] = card.milestones.compactMap { reached in
            flagPoint(for: reached).map { Mark(reached: reached, point: position(of: $0, scale)) }
        }
        guard !marks.isEmpty else { return [] }
        /// The span a name and its flag take, about: 6 points a letter.
        func span(of mark: Mark) -> ClosedRange<CGFloat> {
            let x = mark.point.x
            let label = CGFloat(mark.label?.count ?? 0) * 6 + 4
            return mark.labelOnLeft ? (x - 3 - label)...(x + 10) : (x - 1)...(x + 11 + label)
        }
        func name(_ index: Int) {
            let label = text.label(marks[index].reached.milestone)
            marks[index].label = label
            marks[index].labelOnLeft = marks[index].point.x - 3 - CGFloat(label.count) * 6 - 4 >= 2
        }
        let last = marks.count - 1
        name(last)
        if last > 0 {
            name(0)
            let first = span(of: marks[0])
            let latest = span(of: marks[last])
            let apart = abs(marks[0].point.y - marks[last].point.y) > 18
            if first.overlaps(latest) && !apart { marks[0].label = nil }
        }
        return marks
    }

    private func milestoneLabels(_ scale: PlanProgressTimeline.Scale) -> some View {
        ForEach(marks(scale).filter { $0.label != nil }) { mark in
            graphLabel(mark.label ?? "", weight: .semibold, color: Palette.ink)
                .frame(width: mark.labelOnLeft ? max(0, mark.point.x - 3) : nil, alignment: .trailing)
                .offset(x: mark.labelOnLeft ? 0 : mark.point.x + 11, y: max(graphTop - 14, mark.point.y - 19))
        }
    }

    /// The months' initials along the bottom.
    private var months: some View {
        ForEach(1...12, id: \.self) { month in
            Text(Self.initial(month, locale: locale))
                .font(.caption2)
                .foregroundStyle(Palette.mutedInk)
                .frame(width: pointsPerMonth)
                .offset(x: Self.pad + CGFloat(month - 1) * pointsPerMonth, y: plotBottom + 5)
        }
    }

    /// The answer where the year starts and where it moved, under the months.
    private var chips: some View {
        ForEach(placedChips, id: \.chip.id) { placed in
            PlanAnswerChip(age: placed.chip.age, kind: placed.chip.kind, scale: textScale)
                .offset(x: placed.x, y: plotBottom + 26 * textScale)
        }
    }

    /// The chips that fit without overlapping, each centred on its date.
    private var placedChips: [(chip: PlanProgressTimeline.Chip, x: CGFloat)] {
        let chipWidth = PlanAnswerChip.width * textScale
        var placed: [(chip: PlanProgressTimeline.Chip, x: CGFloat)] = []
        var end: CGFloat = 0
        for chip in card.chips {
            let start = min(max(4, x(chip.date) - chipWidth / 2), width - chipWidth - 4)
            guard start >= end else { continue }
            placed.append((chip: chip, x: start))
            end = start + chipWidth + 2
        }
        return placed
    }

    // MARK: At the pointer

    /// The value nearest a point along the line (a check-in or a month end),
    /// the milestones flagged there, and the notes of its day.
    private struct Reading {
        var point: ChartPoint
        var expected: Double?
        var milestones: [ReachedMilestone]
        var notes: [PlanProgressTimeline.Note]
    }

    private func reading(at pointerX: CGFloat) -> Reading? {
        guard let point = card.actual.min(by: { abs(x($0.date) - pointerX) < abs(x($1.date) - pointerX) }) else {
            return nil
        }
        let day = CalendarDate(point.date, in: .current)
        return Reading(point: point, expected: card.expected(on: point.date),
                       milestones: card.milestones.filter { flagPoint(for: $0)?.date == point.date },
                       notes: card.notes.filter { $0.date == day && $0.kind != .milestone })
    }

    /// The point on the line a milestone's flag stands on: the one nearest the day it was reached.
    private func flagPoint(for reached: ReachedMilestone) -> ChartPoint? {
        let day = reached.date.dateValue
        return card.actual.min { abs($0.date.timeIntervalSince(day)) < abs($1.date.timeIntervalSince(day)) }
    }

    /// The year at the pointer (UI.md, "Progress"): a rule at the nearest
    /// value, and a label with its date, a milestone reached there, the
    /// money, what January expected and the gap, and what changed that day.
    @ViewBuilder
    private func readout(at pointerX: CGFloat) -> some View {
        if let found = reading(at: pointerX) {
            let at = x(found.point.date)
            ZStack(alignment: .topLeading) {
                PlanGraphRule(height: Self.graphHeight)
                    .offset(x: at - 0.5, y: graphTop)
                if let scale {
                    PlanGraphDot(color: Palette.ink)
                        .offset(x: at - 4.5, y: y(found.point.value, scale) - 4.5)
                }
                PlanGraphCallout(lines: lines(for: found))
                    .offset(x: PlanGraphCallout.leading(at: at, in: width), y: graphTop + 4)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func lines(for found: Reading) -> [PlanGraphCallout.Line] {
        let day = CalendarDate(found.point.date, in: .current)
        let source = card.checkIns.contains(found.point.date) ? "check-in" : "from prices"
        var lines = [PlanGraphCallout.Line(text: "\(AmountFormat.mediumDate(day, locale: locale)) · \(source)",
                                           style: .context)]
        let text = PlanMilestoneText(currency: card.currency, hidesAmounts: hidesAmounts, locale: locale)
        for reached in found.milestones {
            lines.append(PlanGraphCallout.Line(text: text.reached(reached.milestone), style: .milestone))
        }
        lines.append(PlanGraphCallout.Line(text: amount(found.point.value), style: .value))
        if let expected = found.expected {
            let gap = found.point.value - expected
            let expectation = card.year.expectationTitle(locale: locale)
            lines.append(PlanGraphCallout.Line(text: "\(expectation) expected \(amount(expected))", style: .detail))
            lines.append(PlanGraphCallout.Line(text: "\(amount(abs(gap))) \(gap >= 0 ? "ahead" : "behind")",
                                               style: .detail))
        }
        if !found.point.isComplete {
            lines.append(PlanGraphCallout.Line(text: "Not every price is known", style: .detail))
        }
        for note in found.notes.prefix(2) {
            lines.append(PlanGraphCallout.Line(text: note.text, style: .title))
        }
        return lines
    }

    private func amount(_ value: Double) -> String {
        hidesAmounts ? AmountFormat.hidden
            : AmountFormat.amount(Decimal(wholeNumber: value), currency: card.currency, locale: locale)
    }

    /// "J", "F", … in the locale.
    static func initial(_ month: Int, locale: Locale) -> String {
        guard let date = CalendarDate(year: 2001, month: month, day: 15)?.dateValue else { return "" }
        return date.formatted(.dateTime.month(.narrow).locale(locale))
    }

    // MARK: Drawing

    private func x(_ date: Date) -> CGFloat {
        let span = card.end.timeIntervalSince(card.start)
        guard span > 0 else { return Self.pad }
        let share = min(1, max(0, date.timeIntervalSince(card.start) / span))
        return Self.pad + CGFloat(share) * (width - 2 * Self.pad)
    }

    private func y(_ value: Double, _ scale: PlanProgressTimeline.Scale) -> CGFloat {
        let low = scale.domain.lowerBound
        let high = scale.domain.upperBound
        let share = high > low ? (value - low) / (high - low) : 0
        return plotBottom - CGFloat(min(1, max(0, share))) * Self.graphHeight
    }

    private func position(of point: ChartPoint, _ scale: PlanProgressTimeline.Scale) -> CGPoint {
        CGPoint(x: x(point.date), y: y(point.value, scale))
    }

    /// Your money (UI.md, "Progress"): solid into each check-in, lighter
    /// where it's valued from what you held and its prices, dotted where a
    /// price or a rate is missing (those holdings count as zero); a small
    /// dot at each check-in and a larger one at the last point.
    private func drawMoney(in context: inout GraphicsContext, _ scale: PlanProgressTimeline.Scale) {
        enum Kind { case checkIn, prices, missing }
        // Each run of segments drawn alike is one path: the lighter line,
        // drawn a segment at a time, darkened where the segments' ends overlap.
        var runs: [(kind: Kind, path: Path)] = []
        for (from, to) in zip(card.actual, card.actual.dropFirst()) {
            let kind: Kind = if !from.isComplete || !to.isComplete {
                .missing
            } else if card.checkIns.contains(to.date) {
                .checkIn
            } else {
                .prices
            }
            if runs.last?.kind != kind {
                var path = Path()
                path.move(to: position(of: from, scale))
                runs.append((kind: kind, path: path))
            }
            runs[runs.count - 1].path.addLine(to: position(of: to, scale))
        }
        let solid = StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round)
        for run in runs {
            switch run.kind {
            case .checkIn:
                context.stroke(run.path, with: .color(Palette.ink), style: solid)
            case .prices:
                context.stroke(run.path, with: .color(Palette.ink.opacity(0.4)), style: solid)
            case .missing:
                context.stroke(run.path, with: .color(Palette.ink),
                               style: StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, dash: [0.5, 4]))
            }
        }
        for point in card.actual.dropLast() where card.checkIns.contains(point.date) {
            let center = position(of: point, scale)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)),
                         with: .color(Palette.ink))
        }
        if let last = card.actual.last {
            let center = position(of: last, scale)
            let dot = Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            context.fill(dot, with: .color(Palette.ink))
            context.stroke(dot, with: .color(Palette.card), lineWidth: 1.5)
        }
    }

    private func line(_ points: [ChartPoint], _ scale: PlanProgressTimeline.Scale) -> Path {
        var path = Path()
        for (offset, point) in points.enumerated() {
            let position = CGPoint(x: x(point.date), y: y(point.value, scale))
            if offset == 0 { path.move(to: position) } else { path.addLine(to: position) }
        }
        return path
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard let scale else { return }
        for tick in scale.ticks where tick > scale.domain.lowerBound {
            var gridline = Path()
            gridline.move(to: CGPoint(x: 0, y: y(tick, scale)))
            gridline.addLine(to: CGPoint(x: size.width, y: y(tick, scale)))
            context.stroke(gridline, with: .color(Palette.gridline), lineWidth: 0.5)
        }
        // The rest of the year, still to come.
        if card.year.isLatest, let last = card.actual.last {
            let from = max(x(last.date), todayX ?? 0)
            context.fill(Path(CGRect(x: from, y: graphTop, width: max(0, size.width - from),
                                     height: Self.graphHeight)),
                         with: .color(Palette.gridline.opacity(0.35)))
        }
        for gap in card.gaps {
            var area = Path()
            for (offset, point) in gap.points.enumerated() {
                let position = CGPoint(x: x(point.date), y: y(point.actual, scale))
                if offset == 0 { area.move(to: position) } else { area.addLine(to: position) }
            }
            for point in gap.points.reversed() {
                area.addLine(to: CGPoint(x: x(point.date), y: y(point.expected, scale)))
            }
            area.closeSubpath()
            context.fill(area, with: .color((gap.ahead ? Palette.green : Palette.orange).opacity(0.25)))
        }
        if card.expected.count >= 2 {
            context.stroke(line(card.expected, scale), with: .color(Palette.secondaryInk),
                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        var axis = Path()
        axis.move(to: CGPoint(x: 0, y: plotBottom + 1))
        axis.addLine(to: CGPoint(x: size.width, y: plotBottom + 1))
        context.stroke(axis, with: .color(Palette.border), lineWidth: 1)
        if let todayX {
            var today = Path()
            today.move(to: CGPoint(x: todayX, y: graphTop))
            today.addLine(to: CGPoint(x: todayX, y: plotBottom))
            context.stroke(today, with: .color(Palette.accent), lineWidth: 1)
        }
        drawMoney(in: &context, scale)
        for mark in marks(scale) {
            if mark.label != nil {
                let flag = PlanMilestoneFlag.path(at: mark.point)
                context.fill(flag, with: .color(Palette.accent))
                context.stroke(flag, with: .color(Palette.card), lineWidth: 1)
            } else {
                let dot = Path(ellipseIn: CGRect(x: mark.point.x - 3.5, y: mark.point.y - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(Palette.accent))
                context.stroke(dot, with: .color(Palette.card), lineWidth: 1.5)
            }
        }
    }
}
