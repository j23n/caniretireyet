import Model
import Planner
import SwiftUI

/// "Your life in 6 chapters" (UI.md, "Plan"): the chapters side by side on a
/// strip that scrolls sideways, each card as wide as its years (never too
/// narrow to read), on one money scale, so the graph runs on from card to
/// card. Choosing a card selects its chapter, whose details show below the
/// strip; selecting one elsewhere scrolls it into view.
struct PlanChapterStrip: View {
    let timeline: PlanTimeline
    @Binding var selection: Int
    /// Points a year along the time axis.
    var pointsPerYear: CGFloat = 24
    var cardHeight: CGFloat = 340
    /// The strip's inset at both ends, so its first card lines up with the page.
    var inset: CGFloat = Metrics.l

    @Environment(\.baseCurrency) private var currency

    /// No card narrower: room for its name and where the money stands.
    static let minimumWidth: CGFloat = 164

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Metrics.s) {
                    ForEach(timeline.cards) { card in
                        Button {
                            selection = card.index
                        } label: {
                            PlanChapterCardView(card: card, scale: timeline.scale, width: width(of: card),
                                                height: cardHeight, isSelected: selection == card.index,
                                                currency: currency)
                        }
                        .buttonStyle(.plain)
                        .id(card.index)
                        .accessibilityLabel(Text(accessibilityLabel(card)))
                        .accessibilityAddTraits(selection == card.index ? .isSelected : [])
                    }
                }
                .padding(.horizontal, inset)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, index in
                withAnimation(.snappy) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func width(of card: PlanTimeline.Card) -> CGFloat {
        max(Self.minimumWidth, CGFloat(card.years) * pointsPerYear)
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
/// stands at its end.
struct PlanChapterCardView: View {
    let card: PlanTimeline.Card
    let scale: AmountScale?
    let width: CGFloat
    let height: CGFloat
    var isSelected = false
    var currency: CurrencyCode

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    private static let graphTop: CGFloat = 64
    private static let graphHeight: CGFloat = 150
    private static let labelWidth: CGFloat = 132
    private var plotBottom: CGFloat { Self.graphTop + Self.graphHeight }

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
            summary
                .frame(width: width, height: height, alignment: .bottomTrailing)
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
                .offset(x: placed.x, y: plotBottom + 26)
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
        // Milestones ahead, outlined: the median reaches them.
        for milestone in card.milestones {
            let day = milestone.date.dateValue
            guard let value = card.median(on: day) else { continue }
            let flag = PlanMilestoneFlag.path(at: point(day, value, scale))
            context.fill(flag, with: .color(Palette.card))
            context.stroke(flag, with: .color(Palette.accent), lineWidth: 1.2)
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
