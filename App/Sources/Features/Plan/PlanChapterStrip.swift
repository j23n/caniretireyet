import Model
import Planner
import SwiftUI

/// "Your life in 6 chapters" (UI.md, "Plan"): the chapters side by side on a
/// strip that scrolls sideways, each card as wide as its years (never too
/// narrow to read, and on iPhone never narrower than the screen), on the
/// money scale the cards on screen share, so the graph runs on from card to
/// card. Choosing a card selects its chapter, whose details show below the
/// strip; selecting one elsewhere scrolls it into view. The pointer over a
/// card, or a finger touched and held on it, reads the graph there.
struct PlanChapterStrip: View {
    let timeline: PlanTimeline
    @Binding var selection: Int
    /// Points a year along the time axis.
    var pointsPerYear: CGFloat = 24
    /// The strip's inset at both ends, so its first card lines up with the page.
    var inset: CGFloat = Metrics.l
    /// No card narrower than the strip between its insets (iPhone).
    var fillsWidth = false

    @Environment(\.baseCurrency) private var currency
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var stripWidth: CGFloat = 0

    /// No card narrower: room for its name and the read-out.
    static let minimumWidth: CGFloat = 164
    /// A card's height at the standard text size: its header, the graph,
    /// the ages and the events' labels.
    private static let cardHeight: CGFloat = 294

    var body: some View {
        // The words above and below the graph grow with the text size, up to a point.
        let textScale = typeSize.stripCardScale
        let height = Self.cardHeight + 120 * (textScale - 1)
        PlanCardStrip(
            indices: Array(timeline.cards.indices), selection: $selection, inset: inset,
            identifier: "plan.chapters", scale: timeline.scale(fitting:),
            spokenLabel: { accessibilityLabel(timeline.cards[$0]) }, chart: { chartSummary(timeline.cards[$0]) }
        ) { index, scale, pointerX in
            let card = timeline.cards[index]
            PlanChapterCardView(card: card, scale: scale, width: width(of: card), height: height,
                                isSelected: selection == index, currency: currency, pointerX: pointerX,
                                textScale: textScale)
        }
        .measuringWidth($stripWidth)
    }

    private func width(of card: PlanTimeline.Card) -> CGFloat {
        let filled = fillsWidth ? stripWidth - 2 * inset : 0
        return max(Self.minimumWidth, filled, CGFloat(card.years) * pointsPerYear)
    }

    /// The chapter for VoiceOver's audio graph and chart details: your
    /// money typically, and in a bad and a good future, at its start and
    /// each year-end.
    private func chartSummary(_ card: PlanTimeline.Card) -> ChartSummary {
        let labels = card.fan.enumerated().map { offset, point in
            let age = card.age(on: point.date)
            return offset == 0 ? "Start, \(age)" : "\(age) · \(Calendar.current.component(.year, from: point.date))"
        }
        func series(_ name: String, _ value: (FanPoint) -> Double) -> ChartSummary.Series {
            ChartSummary.Series(name: name, points: zip(labels, card.fan).map { ($0, value($1)) })
        }
        return ChartSummary(
            title: "Chapter \(card.index + 1), \(card.title)", summary: accessibilityLabel(card),
            xTitle: "Age and year", yTitle: "Your money",
            series: [series("Typically", \.p50), series("Bad, 1 in 10", \.p10), series("Good, 1 in 10", \.p90)],
            describeValue: ChartStyle.spokenAmount(currency: currency, hidden: hidesAmounts))
    }

    /// What VoiceOver reads for a chapter's card, and its chart's summary:
    /// the chapter, and where the money typically stands at its end, left
    /// out while amounts are hidden.
    private func accessibilityLabel(_ card: PlanTimeline.Card) -> String {
        var label = "Chapter \(card.index + 1), \(card.title), \(card.span)"
        if let outcome = card.outcome, !hidesAmounts {
            label += ". At \(outcome.age), typically \(AmountFormat.compactAmount(outcome.median, currency: currency))"
        }
        return label
    }
}

/// One chapter on the strip: its number and name, its ages and years, the
/// money through it (the median in the hue, half the futures in the darker
/// band and 8 in 10 in the lighter one, on the scale every card shares),
/// the ages along its bottom, what happens in it, and a mark on the median
/// at its end; at the pointer, what the graph shows there.
struct PlanChapterCardView: View {
    let card: PlanTimeline.Card
    let scale: PlanStripScale?
    let width: CGFloat
    let height: CGFloat
    var isSelected = false
    var currency: CurrencyCode
    /// Where the pointer is over the card, or where it was tapped.
    var pointerX: CGFloat?
    /// How much its words have grown with the text size
    /// (``DynamicTypeSize/stripCardScale``).
    var textScale: CGFloat = 1

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    private static let labelWidth: CGFloat = 132

    /// The chapter across the card, edge to edge, so the graph runs on from
    /// one card into the next, under the header, which grows with the text
    /// size, and room above the graph for the top amount.
    private var plot: PlanStripPlot {
        PlanStripPlot(start: card.start, end: card.end, left: 0, right: width, top: 64 * textScale + 12)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(width: width, height: height)
            // A new fit of the scale fades the graph to its new place.
            .id(scale)
            .transition(.opacity)
            .accessibilityHidden(true)
            header
            if let scale, !card.fan.isEmpty {
                PlanStripAmountLabels(scale: scale, plot: plot, width: width,
                                      line: card.fan.map { plot.point($0.date, $0.p50, scale) }, currency: currency)
            }
            ageLabels
            eventLabels
            if let scale {
                milestoneLabels(scale)
            }
            if card.index == 0, card.outcome == nil, card.fan.isEmpty {
                calculateNote
            }
            if let pointerX {
                readout(at: pointerX)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Words

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PlanChapterBadge(number: card.index + 1, style: card.style, isSelected: isSelected)
                Text(card.title)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(card.span)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: width - 24, alignment: .leading)
        .offset(x: 12, y: 12)
    }

    /// "Now" or the starting age at the left, ages on round numbers, and the
    /// plan's end age under the last card.
    private var ageLabels: some View {
        ZStack(alignment: .topLeading) {
            Text(card.startLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(card.index == 0 ? Palette.accent : Palette.ink)
                .offset(x: 6, y: plot.bottom + 6)
            ForEach(card.ticks) { tick in
                Text(verbatim: "\(tick.age)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.mutedInk)
                    .frame(width: 28)
                    .offset(x: plot.x(tick.date) - 14, y: plot.bottom + 6)
            }
            if let end = card.endLabel {
                Text(end)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 28, alignment: .trailing)
                    .offset(x: width - 34, y: plot.bottom + 6)
            }
        }
    }

    /// What happens, under the ages: each label starts at its date, and one
    /// that would run into the one before shows only its dot.
    private var eventLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(placedEvents, id: \.event.id) { placed in
                VStack(alignment: .leading, spacing: 0) {
                    Text(placed.event.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(placed.event.detail)
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .lineLimit(1)
                .privacySensitive()
                .frame(width: labelWidth, alignment: .leading)
                .offset(x: placed.x, y: plot.bottom + 26 * textScale)
            }
        }
    }

    private var labelWidth: CGFloat { min(Self.labelWidth, width - 16) }

    /// The events whose labels fit, with where each starts.
    private var placedEvents: [(event: PlanTimeline.Event, x: CGFloat)] {
        var placed: [(event: PlanTimeline.Event, x: CGFloat)] = []
        var end: CGFloat = 0
        for event in card.events {
            let start = min(max(8, plot.x(event.date) - 6), width - labelWidth - 8)
            guard start >= end else { continue }
            placed.append((event: event, x: start))
            end = start + labelWidth + 8
        }
        return placed
    }

    /// A milestone ahead on the median, and its name and when, if it's one
    /// of the two named.
    private struct Mark: Identifiable {
        var milestone: ProjectedMilestone
        var point: CGPoint
        var isNamed = false
        /// Whether its name runs right from its flag (else it ends there).
        var runsRight = true
        var id: ProjectedMilestone.ID { milestone.id }
    }

    /// The milestones ahead in the chapter: the first and the last named,
    /// when their names don't run into each other; the rest small dots.
    private func marks(_ scale: PlanStripScale) -> [Mark] {
        let text = PlanMilestoneText(currency: currency, hidesAmounts: hidesAmounts, locale: locale)
        var marks: [Mark] = card.milestones.compactMap { milestone in
            let day = milestone.date.dateValue
            return card.fan(on: day).map { Mark(milestone: milestone, point: plot.point(day, $0.p50, scale)) }
        }
        guard !marks.isEmpty else { return [] }
        /// Where a name and its flag reach, about: 6 points a letter.
        func reach(_ mark: Mark) -> ClosedRange<CGFloat> {
            let width = CGFloat(max(text.label(mark.milestone.milestone).count, 10)) * 6
            let x = mark.point.x
            return mark.runsRight ? (x - 2)...(x + width) : (x - width)...(x + 10)
        }
        for index in [0, marks.count - 1] {
            marks[index].isNamed = true
            marks[index].runsRight = marks[index].point.x <= width * 0.6
        }
        if marks.count > 1, reach(marks[0]).overlaps(reach(marks[marks.count - 1])),
           abs(marks[0].point.y - marks[marks.count - 1].point.y) < 36 {
            marks[marks.count - 1].isNamed = false
        }
        return marks
    }

    /// The named milestones' names and when, above their flags (below
    /// when there's no room above), on the card's colour.
    private func milestoneLabels(_ scale: PlanStripScale) -> some View {
        let text = PlanMilestoneText(currency: currency, hidesAmounts: hidesAmounts, locale: locale)
        return ForEach(marks(scale).filter(\.isNamed)) { mark in
            let above = mark.point.y - 44 >= plot.top - 6
            VStack(alignment: mark.runsRight ? .leading : .trailing, spacing: 0) {
                Text(text.label(mark.milestone.milestone))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(PlanMilestoneText.when(mark.milestone.date))
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .planGraphLabel()
            .frame(width: mark.runsRight ? nil : max(0, mark.point.x + 10), alignment: .trailing)
            .offset(x: mark.runsRight ? max(4, mark.point.x - 2) : 0,
                    y: above ? mark.point.y - 44 : mark.point.y + 6)
            .accessibilityHidden(true)
        }
    }

    /// Before calculating, in the first card's empty graph.
    private var calculateNote: some View {
        Text("Calculate to see your money")
            .font(.caption)
            .foregroundStyle(Palette.mutedInk)
            .multilineTextAlignment(.center)
            .frame(width: max(0, width - 24), height: PlanStripPlot.height)
            .offset(x: 12, y: plot.top)
    }

    /// Where the chapter's end is marked on the median, once the plan is
    /// calculated: just inside the card's right edge, so the mark shows whole.
    private func endPoint(_ scale: PlanStripScale) -> CGPoint? {
        let x = max(0, width - 7)
        guard card.outcome != nil, let fan = card.fan(on: plot.date(at: x)) else { return nil }
        return CGPoint(x: x, y: plot.y(fan.p50, scale))
    }

    private func compact(_ value: Double) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.compactAmount(value, currency: currency, locale: locale)
    }

    // MARK: At the pointer

    /// What the graph shows at a point: a milestone, an event or the
    /// chapter's end the pointer is on, else the date under it.
    private struct Reading {
        var x: CGFloat
        var date: Date
        var fan: FanPoint?
        var milestone: ProjectedMilestone?
        var event: PlanTimeline.Event?
        var outcome: PlanChaptersModel.Outcome?
    }

    /// How near the pointer has to come to a milestone, an event or the
    /// chapter's end to read it.
    private static let reach: CGFloat = 10

    /// The nearest milestone, event or end within reach, the first of them
    /// when two are as near; else the date under the pointer.
    private func reading(at pointerX: CGFloat) -> Reading {
        let at = min(max(0, pointerX), width)
        var marked: [Reading] = card.milestones.map { milestone in
            let day = milestone.date.dateValue
            return Reading(x: plot.x(day), date: day, fan: card.fan(on: day), milestone: milestone)
        }
        marked += card.events.map { event in
            Reading(x: plot.x(event.date), date: event.date, fan: card.fan(on: event.date), event: event)
        }
        if let scale, let outcome = card.outcome, let end = endPoint(scale) {
            marked.append(Reading(x: end.x, date: card.end, fan: card.fan(on: plot.date(at: end.x)),
                                  outcome: outcome))
        }
        if let nearest = marked.filter({ abs($0.x - at) <= Self.reach })
            .min(by: { abs($0.x - at) < abs($1.x - at) }) {
            return nearest
        }
        let date = plot.date(at: at)
        return Reading(x: at, date: date, fan: card.fan(on: date))
    }

    /// The graph at the pointer (UI.md, "Plan"): a rule, the median's dot,
    /// and a label with the age and the year, a milestone or an event
    /// there, the median and the range 8 in 10 futures fall in; at the
    /// chapter's end, those at its last year's end and how many futures
    /// run out during it.
    private func readout(at pointerX: CGFloat) -> some View {
        let found = reading(at: pointerX)
        return ZStack(alignment: .topLeading) {
            PlanGraphRule(height: PlanStripPlot.height)
                .offset(x: found.x - 0.5, y: plot.top)
            if let scale, let fan = found.fan {
                PlanGraphDot()
                    .offset(x: found.x - 4.5, y: plot.y(fan.p50, scale) - 4.5)
            }
            PlanGraphCallout(lines: lines(for: found))
                .offset(x: PlanGraphCallout.leading(at: found.x, in: width), y: plot.top + 4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func lines(for found: Reading) -> [PlanGraphCallout.Line] {
        if let outcome = found.outcome {
            // The chapter's last year: the one it reaches that age in.
            let year = card.birthDate.year + outcome.age
            let runsOut = outcome.failureShare > 0
            return [
                PlanGraphCallout.Line(text: "\(outcome.age) · \(String(year))", style: .context),
                PlanGraphCallout.Line(text: "Typically \(rounded(outcome.median))", style: .value),
                PlanGraphCallout.Line(text: "Bad \(compact(outcome.low)), good \(compact(outcome.high))",
                                      style: .detail),
                PlanGraphCallout.Line(text: PlanTimelineText.runsOut(outcome.failureShare),
                                      style: runsOut ? .warning : .detail)
            ]
        }
        let year = Calendar.current.component(.year, from: found.date)
        var lines = [PlanGraphCallout.Line(text: "\(card.age(on: found.date)) · \(String(year))", style: .context)]
        if let milestone = found.milestone {
            let text = PlanMilestoneText(currency: currency, hidesAmounts: hidesAmounts, locale: locale)
            lines.append(PlanGraphCallout.Line(text: text.name(milestone.milestone), style: .milestone))
            lines.append(PlanGraphCallout.Line(text: "Typically by \(PlanMilestoneText.when(milestone.date))",
                                               style: .detail))
        } else if let event = found.event {
            lines.append(PlanGraphCallout.Line(text: event.title, style: .title))
            lines.append(PlanGraphCallout.Line(text: event.detail, style: .detail))
        }
        if let fan = found.fan {
            lines.append(PlanGraphCallout.Line(text: "Typically \(rounded(fan.p50))", style: .value))
            lines.append(PlanGraphCallout.Line(text: "Bad \(compact(fan.p10)), good \(compact(fan.p90))",
                                               style: .detail))
        }
        return lines
    }

    /// A projected amount to the nearest thousand: "640.000 €".
    private func rounded(_ value: Double) -> String {
        guard !hidesAmounts else { return AmountFormat.hidden }
        let thousands = abs(value) >= 10_000 ? (value / 1_000).rounded() * 1_000 : value.rounded()
        return AmountFormat.amount(Decimal(wholeNumber: thousands), currency: currency, locale: locale)
    }

    // MARK: Drawing

    private func band(_ low: KeyPath<FanPoint, Double>, _ high: KeyPath<FanPoint, Double>,
                      _ scale: PlanStripScale) -> Path {
        var path = Path()
        guard let first = card.fan.first else { return path }
        path.move(to: plot.point(first.date, first[keyPath: high], scale))
        for fanPoint in card.fan.dropFirst() {
            path.addLine(to: plot.point(fanPoint.date, fanPoint[keyPath: high], scale))
        }
        for fanPoint in card.fan.reversed() {
            path.addLine(to: plot.point(fanPoint.date, fanPoint[keyPath: low], scale))
        }
        path.closeSubpath()
        return path
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        var base = Path()
        base.move(to: CGPoint(x: 0, y: plot.bottom + 1))
        base.addLine(to: CGPoint(x: size.width, y: plot.bottom + 1))
        context.stroke(base, with: .color(PlanChapterColors.color(card.style)), lineWidth: 2)
        guard let scale, card.fan.count >= 2 else { return }
        plot.drawGridlines(scale, width: size.width, in: &context)
        context.fill(band(\.p10, \.p90, scale), with: .color(Palette.accent.opacity(ProjectionLegend.outerBand)))
        context.fill(band(\.p25, \.p75, scale), with: .color(Palette.accent.opacity(ProjectionLegend.innerBand)))
        var median = Path()
        for (offset, fanPoint) in card.fan.enumerated() {
            let position = plot.point(fanPoint.date, fanPoint.p50, scale)
            if offset == 0 { median.move(to: position) } else { median.addLine(to: position) }
        }
        context.stroke(median, with: .color(Palette.accent),
                       style: StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
        for event in card.events {
            guard let value = card.fan(on: event.date)?.p50 else { continue }
            let center = plot.point(event.date, value, scale)
            let dot = Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            context.fill(dot, with: .color(Self.color(of: event.kind)))
            context.stroke(dot, with: .color(Palette.card), lineWidth: 1.5)
        }
        // Milestones ahead, outlined: the median reaches them. The two named
        // are flagged, the rest small dots.
        for mark in marks(scale) {
            if mark.isNamed {
                let flag = PlanMilestoneFlag.path(at: mark.point)
                context.fill(flag, with: .color(Palette.card))
                context.stroke(flag, with: .color(Palette.accent), lineWidth: 1.2)
            } else {
                let dot = Path(ellipseIn: CGRect(x: mark.point.x - 3, y: mark.point.y - 3, width: 6, height: 6))
                context.fill(dot, with: .color(Palette.accent))
                context.stroke(dot, with: .color(Palette.card), lineWidth: 1)
            }
        }
        // The chapter's end, once calculated: a ring on the median, orange
        // when any futures run out during the chapter.
        if let outcome = card.outcome, let end = endPoint(scale) {
            let runsOut = outcome.failureShare > 0
            let ring = Path(ellipseIn: CGRect(x: end.x - 5, y: end.y - 5, width: 10, height: 10))
            context.fill(ring, with: .color(runsOut ? Palette.orange : Palette.card))
            context.stroke(ring, with: .color(runsOut ? Palette.orangeStroke : Palette.accent), lineWidth: 2)
        }
    }

    static func color(of kind: PlanTimeline.Event.Kind) -> Color {
        switch kind {
        case .expense: Palette.mutedInk
        case .windfall: Palette.green
        case .pension: Palette.violet
        case .spending: Palette.violet.opacity(0.6)
        case .saving: Palette.accent
        }
    }
}
