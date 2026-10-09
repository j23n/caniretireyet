import Model
import Planner
import SwiftUI
import Tracker

// Progress year by year (UI.md, "Progress"): the strip of years, each a
// card with your money through the year against what January expected.

// MARK: - The strip of years

/// The years side by side on a strip that opens at today, on the right, on
/// the money scale the cards on screen share, so December of one year meets
/// January of the next. Choosing a card selects its year, whose words show
/// below the strip; on the Mac and iPad each card also has its figures in a
/// line under its graph. Selecting one elsewhere scrolls it into view.
struct PlanYearStrip: View {
    let timeline: PlanProgressTimeline
    /// The index of the selected card.
    @Binding var selection: Int
    /// Points a month along the time axis.
    var pointsPerMonth: CGFloat = 21
    /// The strip's inset at both ends, so its cards line up with the page.
    var inset: CGFloat = Metrics.l
    /// Whether each card shows its year's figures in a line under its graph
    /// (the Mac and iPad).
    var showsFooter = false
    /// Today, marked on the latest year's card.
    var today: CalendarDate?

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsEarlyYears = false

    /// The oldest years, before the first with a recorded answer: folded
    /// into one card until shown.
    private var earlyCount: Int {
        timeline.cards.firstIndex { $0.year.answerTo != nil } ?? 0
    }

    var body: some View {
        let early = earlyCount
        let folds = early > 0 && !showsEarlyYears && selection >= early
        // The words above and below the graph grow with the text size, up to a point.
        let textScale = typeSize.stripCardScale
        let height = PlanYearCardView.height(textScale: textScale)
        PlanCardStrip(
            indices: Array(timeline.cards.indices.dropFirst(folds ? early : 0)), selection: $selection,
            inset: inset, opensAtEnd: true, identifier: "progress.years", scale: timeline.scale(fitting:),
            spokenLabel: { accessibilityLabel(timeline.cards[$0]) }, chart: { chartSummary(timeline.cards[$0]) }
        ) {
            if folds {
                PlanEarlyYearsCard(cards: Array(timeline.cards.prefix(early)), height: height,
                                   isCompact: !showsFooter) {
                    withAnimation(.snappy) { showsEarlyYears = true }
                }
            }
        } graph: { index, scale, pointerX in
            let card = timeline.cards[index]
            PlanYearCardView(card: card, scale: scale, pointsPerMonth: pointsPerMonth, height: height,
                             pointerX: pointerX, textScale: textScale, today: card.year.isLatest ? today : nil)
        } footer: { index in
            if showsFooter {
                PlanYearCardFooter(card: timeline.cards[index])
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .frame(width: PlanYearCardView.width(pointsPerMonth: pointsPerMonth), alignment: .leading)
            }
        }
        .onChange(of: selection) { _, index in
            // Once an early year is chosen, the early years stay laid out.
            if index < early { showsEarlyYears = true }
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
        return ChartSummary(
            title: card.year.title,
            summary: PlanProgressText.story(card.year, currency: card.currency, hidesAmounts: hidesAmounts,
                                            locale: locale),
            xTitle: "Date", yTitle: "Your money", series: series,
            describeValue: ChartStyle.spokenAmount(currency: card.currency, hidden: hidesAmounts))
    }

    private func accessibilityLabel(_ card: PlanProgressTimeline.Card) -> String {
        var label = card.year.title
        if !card.year.isLatest {
            label += ", " + PlanProgressText.change(card.year, currency: card.currency, hidesAmounts: hidesAmounts,
                                                    locale: locale)
        }
        if let against = PlanProgressText.againstJanuary(card.year, currency: card.currency, hidesAmounts: hidesAmounts,
                                                         locale: locale) {
            label += ", \(against)"
        }
        if let summary = card.summary {
            label += ". \(summary)"
        }
        return label
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
/// green where you're ahead and orange where behind, a flag where you
/// passed a milestone, and the months along its bottom; the rest of the
/// year still to come shaded. The card names its own lines (*Today*,
/// *January expected*), so it needs no key; the milestones' names and how
/// the answer moved are in the year's words.
struct PlanYearCardView: View {
    let card: PlanProgressTimeline.Card
    let scale: PlanStripScale?
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
    private var width: CGFloat { Self.width(pointsPerMonth: pointsPerMonth) }

    /// The year across, inside the card's padding, under the header, which
    /// grows with the text size, and room above the graph for the top amount.
    private var plot: PlanStripPlot {
        PlanStripPlot(start: card.start, end: card.end, left: Self.pad, right: width - Self.pad,
                      top: 54 * textScale + 20)
    }

    /// A card's width: its twelve months and its padding.
    static func width(pointsPerMonth: CGFloat) -> CGFloat {
        12 * pointsPerMonth + 2 * pad
    }

    /// A card's height: its header, the graph, and the months under it,
    /// growing with the text size.
    static func height(textScale: CGFloat) -> CGFloat {
        187 + 67 * textScale
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
                PlanStripAmountLabels(scale: scale, plot: plot, width: width,
                                      line: card.actual.map { position(of: $0, scale) }, currency: card.currency)
                expectedLabel(scale)
            }
            todayLabel
            months
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
            if let against = PlanProgressText.againstJanuary(card.year, currency: card.currency,
                                                             hidesAmounts: hidesAmounts, locale: locale) {
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

    /// *January expected* where the dashed line starts: under it when you
    /// start ahead of it, above it when behind, so it stays off your line.
    @ViewBuilder
    private func expectedLabel(_ scale: PlanStripScale) -> some View {
        if let first = card.expected.first {
            let start = position(of: first, scale)
            let actual = card.actual.first { $0.date >= first.date }?.value ?? first.value
            let fitsBelow = start.y + 20 <= plot.bottom
            let fitsAbove = start.y - 20 >= plot.top
            let below = actual >= first.value ? fitsBelow || !fitsAbove : !fitsAbove
            Text("\(card.year.expectationTitle(locale: locale)) expected")
                .font(.caption2)
                .foregroundStyle(Palette.secondaryInk)
                .planGraphLabel()
                .offset(x: max(Self.pad, start.x) + 2, y: below ? start.y + 3 : start.y - 18)
        }
    }

    /// Where today falls on the card, when it's in the year and its label fits beside it.
    private var todayX: CGFloat? {
        guard let today, today.year == card.year.year else { return nil }
        let at = plot.x(today.dateValue)
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
                .offset(x: todayX + 3, y: plot.top + 2)
        }
    }

    /// Where the milestones reached in the year stand on the line, each
    /// flagged at the value nearest the day it was reached.
    private func flagPoints(_ scale: PlanStripScale) -> [CGPoint] {
        card.milestones.compactMap { reached in flagPoint(for: reached).map { position(of: $0, scale) } }
    }

    /// The months' initials along the bottom.
    private var months: some View {
        ForEach(1...12, id: \.self) { month in
            Text(Self.initial(month, locale: locale))
                .font(.caption2)
                .foregroundStyle(Palette.mutedInk)
                .frame(width: pointsPerMonth)
                .offset(x: Self.pad + CGFloat(month - 1) * pointsPerMonth, y: plot.bottom + 5)
        }
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
        let plot = plot
        func distance(_ point: ChartPoint) -> CGFloat { abs(plot.x(point.date) - pointerX) }
        guard let point = card.actual.min(by: { distance($0) < distance($1) }) else { return nil }
        let day = CalendarDate(point.date, in: .current)
        return Reading(point: point, expected: card.expected(on: point.date),
                       milestones: card.milestones.filter { flagPoint(for: $0)?.date == point.date },
                       notes: card.notes.filter { $0.date == day && !$0.isMilestone })
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
            let at = plot.x(found.point.date)
            ZStack(alignment: .topLeading) {
                PlanGraphRule(height: PlanStripPlot.height)
                    .offset(x: at - 0.5, y: plot.top)
                if let scale {
                    PlanGraphDot(color: Palette.ink)
                        .offset(x: at - 4.5, y: plot.y(found.point.value, scale) - 4.5)
                }
                PlanGraphCallout(lines: lines(for: found))
                    .offset(x: PlanGraphCallout.leading(at: at, in: width), y: plot.top + 4)
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
            lines.append(PlanGraphCallout.Line(text: text.reachedInRow(reached.milestone), style: .milestone))
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

    private func position(of point: ChartPoint, _ scale: PlanStripScale) -> CGPoint {
        plot.point(point.date, point.value, scale)
    }

    /// Your money (UI.md, "Progress"): solid into each check-in, lighter
    /// where it's valued from what you held and its prices, dotted where a
    /// price or a rate is missing (those holdings count as zero); a small
    /// dot at each check-in and a larger one at the last point.
    private func drawMoney(in context: inout GraphicsContext, _ scale: PlanStripScale) {
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

    private func line(_ points: [ChartPoint], _ scale: PlanStripScale) -> Path {
        var path = Path()
        for (offset, point) in points.enumerated() {
            let at = position(of: point, scale)
            if offset == 0 { path.move(to: at) } else { path.addLine(to: at) }
        }
        return path
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard let scale else { return }
        plot.drawGridlines(scale, width: size.width, in: &context)
        // The rest of the year, still to come.
        if card.year.isLatest, let last = card.actual.last {
            let from = max(plot.x(last.date), todayX ?? 0)
            context.fill(Path(CGRect(x: from, y: plot.top, width: max(0, size.width - from),
                                     height: PlanStripPlot.height)),
                         with: .color(Palette.gridline.opacity(0.35)))
        }
        for gap in card.gaps {
            var area = Path()
            for (offset, point) in gap.points.enumerated() {
                let position = CGPoint(x: plot.x(point.date), y: plot.y(point.actual, scale))
                if offset == 0 { area.move(to: position) } else { area.addLine(to: position) }
            }
            for point in gap.points.reversed() {
                area.addLine(to: CGPoint(x: plot.x(point.date), y: plot.y(point.expected, scale)))
            }
            area.closeSubpath()
            context.fill(area, with: .color((gap.ahead ? Palette.green : Palette.orange).opacity(0.25)))
        }
        if card.expected.count >= 2 {
            context.stroke(line(card.expected, scale), with: .color(Palette.secondaryInk),
                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        var axis = Path()
        axis.move(to: CGPoint(x: 0, y: plot.bottom + 1))
        axis.addLine(to: CGPoint(x: size.width, y: plot.bottom + 1))
        context.stroke(axis, with: .color(Palette.border), lineWidth: 1)
        if let todayX {
            var today = Path()
            today.move(to: CGPoint(x: todayX, y: plot.top))
            today.addLine(to: CGPoint(x: todayX, y: plot.bottom))
            context.stroke(today, with: .color(Palette.accent), lineWidth: 1)
        }
        drawMoney(in: &context, scale)
        for point in flagPoints(scale) {
            let flag = PlanMilestoneFlag.path(at: point)
            context.fill(flag, with: .color(Palette.accent))
            context.stroke(flag, with: .color(Palette.card), lineWidth: 1)
        }
    }
}
