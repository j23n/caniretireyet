import Model
import Planner
import SwiftUI

/// "Your life in 6 chapters" (UI.md, "Plan"): the chapters side by side on a
/// strip that scrolls sideways, each card as wide as its years (never too
/// narrow to read), on one money scale, so the graph runs on from card to
/// card. Choosing a card selects its chapter, whose details show below the
/// strip; selecting one elsewhere scrolls it into view. The pointer over a
/// card, or a finger touched and held on it, reads the graph there.
struct PlanChapterStrip: View {
    let timeline: PlanTimeline
    @Binding var selection: Int
    /// Points a year along the time axis.
    var pointsPerYear: CGFloat = 24
    var cardHeight: CGFloat = 340
    /// The strip's inset at both ends, so its first card lines up with the page.
    var inset: CGFloat = Metrics.l

    @Environment(\.baseCurrency) private var currency
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Where the pointer is over a card, or where one was tapped.
    @State private var pointer: PlanGraphPointer?

    /// No card narrower: room for its name and where the money stands.
    static let minimumWidth: CGFloat = 164

    var body: some View {
        // The words above and below the graph grow with the text size, up to a point.
        let textScale = typeSize.stripCardScale
        let height = cardHeight + 190 * (textScale - 1)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Metrics.s) {
                    ForEach(timeline.cards) { card in
                        Button {
                            selection = card.index
                        } label: {
                            PlanChapterCardView(card: card, scale: timeline.scale, width: width(of: card),
                                                height: height, isSelected: selection == card.index,
                                                currency: currency,
                                                pointerX: pointer?.index == card.index ? pointer?.x : nil,
                                                textScale: textScale)
                                .planGraphPointer($pointer, index: card.index)
                        }
                        .buttonStyle(.plain)
                        .id(card.index)
                        .accessibilityLabel(Text(accessibilityLabel(card)))
                        .accessibilityAddTraits(selection == card.index ? .isSelected : [])
                        .accessibilityChartDescriptor(chartSummary(card))
                    }
                }
                .padding(.horizontal, inset)
                .padding(.vertical, 2)
                .dynamicTypeSize(...DynamicTypeSize.stripCardLimit)
            }
            .scrollIndicators(.hidden)
            // A finger reading the graph moves the read-out, not the strip.
            .scrollDisabled(pointer?.byTouch == true)
            .accessibilityIdentifier("plan.chapters")
            .onChange(of: selection) { _, index in
                withAnimation(.snappy) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func width(of card: PlanTimeline.Card) -> CGFloat {
        max(Self.minimumWidth, CGFloat(card.years) * pointsPerYear)
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
        let describe: @Sendable (Double) -> String
        if hidesAmounts {
            let hidden = AmountFormat.hidden
            describe = { _ in hidden }
        } else {
            describe = ChartStyle.spokenAmount(currency: currency)
        }
        return ChartSummary(
            title: "Chapter \(card.index + 1), \(card.title)", summary: accessibilityLabel(card),
            xTitle: "Age and year", yTitle: "Your money",
            series: [series("Typically", \.p50), series("Bad, 1 in 10", \.p10), series("Good, 1 in 10", \.p90)],
            describeValue: describe)
    }

    private func accessibilityLabel(_ card: PlanTimeline.Card) -> String {
        var label = "Chapter \(card.index + 1), \(card.title), \(card.span)"
        if let outcome = card.outcome {
            label += ". At \(outcome.age), typically \(AmountFormat.compactAmount(outcome.median, currency: currency))"
        }
        return label
    }
}

/// One chapter on the strip: its number and name, its ages and years, the
/// money through it (the median in the hue, half the futures in the darker
/// band and 8 in 10 in the lighter one, on the scale every card shares),
/// the ages along its bottom, what happens in it, and where the money
/// stands at its end; at the pointer, what the graph shows there.
struct PlanChapterCardView: View {
    let card: PlanTimeline.Card
    let scale: AmountScale?
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

    private static let graphHeight: CGFloat = 150
    private static let labelWidth: CGFloat = 132
    /// The header's height, which grows with the text size.
    private var graphTop: CGFloat { 64 * textScale }
    private var plotBottom: CGFloat { graphTop + Self.graphHeight }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
            header
            amountLabels
            ageLabels
            eventLabels
            if let scale {
                milestoneLabels(scale)
            }
            summary
                .frame(width: width, height: height, alignment: .bottomTrailing)
            if let pointerX {
                readout(at: pointerX)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(Palette.card, in: shape)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(shape)
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

    /// The money scale's gridlines, labelled inside the plot (not while amounts are hidden).
    @ViewBuilder
    private var amountLabels: some View {
        if let scale, !hidesAmounts, !card.fan.isEmpty {
            ForEach(scale.ticks.filter { $0 > scale.domain.lowerBound }, id: \.self) { tick in
                Text(verbatim: AmountFormat.compactAmount(tick, currency: currency, locale: locale))
                    .font(.caption2)
                    .foregroundStyle(Palette.mutedInk)
                    .offset(x: 6, y: y(tick, scale) - 15)
            }
        }
    }

    /// "Now" or the starting age at the left, ages on round numbers, and the
    /// plan's end age under the last card.
    private var ageLabels: some View {
        ZStack(alignment: .topLeading) {
            Text(card.startLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(card.index == 0 ? Palette.accent : Palette.ink)
                .offset(x: 6, y: plotBottom + 6)
            ForEach(card.ticks) { tick in
                Text(verbatim: "\(tick.age)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.mutedInk)
                    .frame(width: 28)
                    .offset(x: x(tick.date) - 14, y: plotBottom + 6)
            }
            if let end = card.endLabel {
                Text(end)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 28, alignment: .trailing)
                    .offset(x: width - 34, y: plotBottom + 6)
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
                .offset(x: placed.x, y: plotBottom + 26 * textScale)
            }
        }
    }

    private var labelWidth: CGFloat { min(Self.labelWidth, width - 16) }

    /// The events whose labels fit, with where each starts.
    private var placedEvents: [(event: PlanTimeline.Event, x: CGFloat)] {
        var placed: [(event: PlanTimeline.Event, x: CGFloat)] = []
        var end: CGFloat = 0
        for event in card.events {
            let start = min(max(8, x(event.date) - 6), width - labelWidth - 8)
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
    private func marks(_ scale: AmountScale) -> [Mark] {
        let text = PlanMilestoneText(currency: currency, hidesAmounts: hidesAmounts, locale: locale)
        var marks: [Mark] = card.milestones.compactMap { milestone in
            let day = milestone.date.dateValue
            return card.median(on: day).map { Mark(milestone: milestone, point: point(day, $0, scale)) }
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
    private func milestoneLabels(_ scale: AmountScale) -> some View {
        let text = PlanMilestoneText(currency: currency, hidesAmounts: hidesAmounts, locale: locale)
        return ForEach(marks(scale).filter(\.isNamed)) { mark in
            let above = mark.point.y - 44 >= graphTop - 6
            VStack(alignment: mark.runsRight ? .leading : .trailing, spacing: 0) {
                Text(text.label(mark.milestone.milestone))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(PlanMilestoneText.when(mark.milestone.date))
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .lineLimit(1)
            .padding(.horizontal, 2)
            .background(Palette.card.opacity(0.85), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .fixedSize()
            .frame(width: mark.runsRight ? nil : max(0, mark.point.x + 10), alignment: .trailing)
            .offset(x: mark.runsRight ? max(4, mark.point.x - 2) : 0,
                    y: above ? mark.point.y - 44 : mark.point.y + 6)
            .accessibilityHidden(true)
        }
    }

    /// "At 67, typically 1,1M €", the range 8 in 10 futures fall in, and how
    /// many run out during the chapter.
    @ViewBuilder
    private var summary: some View {
        if let outcome = card.outcome {
            VStack(alignment: .trailing, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("At \(outcome.age), typically")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                    Text(verbatim: compact(outcome.median))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Palette.ink)
                }
                Text(verbatim: "Bad \(compact(outcome.low)), good \(compact(outcome.high))")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
                if let share = outcome.failureShare {
                    Text(PlanTimelineText.runsOut(share))
                        .font(.caption2.weight(share > 0 ? .semibold : .regular))
                        .foregroundStyle(share > 0 ? Palette.orangeStroke : Palette.secondaryInk)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .privacySensitive()
            .padding(.trailing, 12)
            .padding(.bottom, 10)
        } else if card.index == 0 {
            Text("Calculate to see your money")
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .padding(.trailing, 12)
                .padding(.bottom, 10)
        }
    }

    private func compact(_ value: Double) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.compactAmount(value, currency: currency, locale: locale)
    }

    // MARK: At the pointer

    /// What the graph shows at a point: a milestone or an event the pointer
    /// is on, else the date under it.
    private struct Reading {
        var x: CGFloat
        var date: Date
        var fan: FanPoint?
        var milestone: ProjectedMilestone?
        var event: PlanTimeline.Event?
    }

    /// How near the pointer has to come to a milestone or an event to read it.
    private static let reach: CGFloat = 10

    private func reading(at pointerX: CGFloat) -> Reading {
        let at = min(max(0, pointerX), width)
        func distance(_ date: Date) -> CGFloat { abs(x(date) - at) }
        if let milestone = card.milestones.min(by: { distance($0.date.dateValue) < distance($1.date.dateValue) }),
           distance(milestone.date.dateValue) <= Self.reach {
            let day = milestone.date.dateValue
            return Reading(x: x(day), date: day, fan: card.fan(on: day), milestone: milestone)
        }
        if let event = card.events.min(by: { distance($0.date) < distance($1.date) }),
           distance(event.date) <= Self.reach {
            return Reading(x: x(event.date), date: event.date, fan: card.fan(on: event.date), event: event)
        }
        let share = width > 0 ? Double(at / width) : 0
        let date = card.start.addingTimeInterval(card.end.timeIntervalSince(card.start) * share)
        return Reading(x: at, date: date, fan: card.fan(on: date))
    }

    /// The graph at the pointer (UI.md, "Plan"): a rule, the median's dot,
    /// and a label with the age and the year, a milestone or an event
    /// there, the median and the range 8 in 10 futures fall in.
    private func readout(at pointerX: CGFloat) -> some View {
        let found = reading(at: pointerX)
        return ZStack(alignment: .topLeading) {
            PlanGraphRule(height: Self.graphHeight)
                .offset(x: found.x - 0.5, y: graphTop)
            if let scale, let fan = found.fan {
                PlanGraphDot()
                    .offset(x: found.x - 4.5, y: y(fan.p50, scale) - 4.5)
            }
            PlanGraphCallout(lines: lines(for: found))
                .offset(x: PlanGraphCallout.leading(at: found.x, in: width), y: graphTop + 4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func lines(for found: Reading) -> [PlanGraphCallout.Line] {
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

    private func x(_ date: Date) -> CGFloat {
        let span = card.end.timeIntervalSince(card.start)
        guard span > 0 else { return 0 }
        return CGFloat(date.timeIntervalSince(card.start) / span) * width
    }

    private func y(_ value: Double, _ scale: AmountScale) -> CGFloat {
        let low = scale.domain.lowerBound
        let high = scale.domain.upperBound
        let share = high > low ? (value - low) / (high - low) : 0
        return plotBottom - CGFloat(min(1, max(0, share))) * Self.graphHeight
    }

    private func point(_ date: Date, _ value: Double, _ scale: AmountScale) -> CGPoint {
        CGPoint(x: x(date), y: y(value, scale))
    }

    private func band(_ low: KeyPath<FanPoint, Double>, _ high: KeyPath<FanPoint, Double>,
                      _ scale: AmountScale) -> Path {
        var path = Path()
        guard let first = card.fan.first else { return path }
        path.move(to: point(first.date, first[keyPath: high], scale))
        for fanPoint in card.fan.dropFirst() {
            path.addLine(to: point(fanPoint.date, fanPoint[keyPath: high], scale))
        }
        for fanPoint in card.fan.reversed() {
            path.addLine(to: point(fanPoint.date, fanPoint[keyPath: low], scale))
        }
        path.closeSubpath()
        return path
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        var base = Path()
        base.move(to: CGPoint(x: 0, y: plotBottom + 1))
        base.addLine(to: CGPoint(x: size.width, y: plotBottom + 1))
        context.stroke(base, with: .color(PlanChapterColors.color(card.style)), lineWidth: 2)
        guard let scale, card.fan.count >= 2 else { return }
        for tick in scale.ticks where tick > scale.domain.lowerBound {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y(tick, scale)))
            line.addLine(to: CGPoint(x: size.width, y: y(tick, scale)))
            context.stroke(line, with: .color(Palette.gridline), lineWidth: 0.5)
        }
        context.fill(band(\.p10, \.p90, scale), with: .color(Palette.accent.opacity(ProjectionLegend.outerBand)))
        context.fill(band(\.p25, \.p75, scale), with: .color(Palette.accent.opacity(ProjectionLegend.innerBand)))
        var median = Path()
        for (offset, fanPoint) in card.fan.enumerated() {
            let position = point(fanPoint.date, fanPoint.p50, scale)
            if offset == 0 { median.move(to: position) } else { median.addLine(to: position) }
        }
        context.stroke(median, with: .color(Palette.accent),
                       style: StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
        for event in card.events {
            guard let value = card.median(on: event.date) else { continue }
            let center = point(event.date, value, scale)
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
