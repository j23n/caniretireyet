import Model
import Planner
import SwiftUI
import Tracker

// The Timeline at a year (UI.md, "Year"): the chosen year's chart on a
// card, your money through the year against what you planned in January,
// with ‹ › to step through the years.

// MARK: - The year's card

/// The chosen year on a card (UI.md, "Year"): its title ("2026 so far")
/// and its verdict in a line ("Ahead of what you planned in January", in
/// orange when behind), ‹ › to step through the years either side of them
/// on iPhone (with *Today* and ⌘[ ⌘] beside them on the Mac and iPad), and
/// the year's chart across the card. The pointer over the chart, or a
/// finger touched and held on it, reads it.
struct PlanYearChartCard: View {
    let timeline: PlanProgressTimeline
    /// The index of the chosen year's card.
    let index: Int
    let select: (Int) -> Void

    @Environment(\.pageLayout) private var layout
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.locale) private var locale
    @State private var width: CGFloat = 0
    @State private var pointer: PlanGraphPointer?

    private var card: PlanProgressTimeline.Card { timeline.cards[index] }
    private var count: Int { timeline.cards.count }

    /// Whether amounts are hidden: VoiceOver doesn't read them.
    private var hidesAmounts: Bool { redactionReasons.hidesAmounts }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            if layout.isWide {
                HStack(alignment: .center, spacing: Metrics.m) {
                    titles(alignment: .leading)
                    Spacer(minLength: Metrics.s)
                    if count > 1 {
                        PlanStepButtons(index: index, count: count, today: count - 1, select: select)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: Metrics.s) {
                    stepButton(later: false)
                    titles(alignment: .center)
                        .frame(maxWidth: .infinity)
                    stepButton(later: true)
                }
            }
            graph
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .onChange(of: index) { _, _ in pointer = nil }
    }

    /// "2026 so far" over its verdict, each on one line.
    private func titles(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(card.year.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
                .privacySensitiveInFeedback()
                .accessibilityAddTraits(.isHeader)
            if let verdict = PlanProgressText.verdict(card.year, locale: locale) {
                Text(verdict)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PlanBaselineComparison.Standing.color(of: card.year.position))
            } else {
                Text(PlanProgressText.unmeasured(card.year))
                    .font(.subheadline)
                    .foregroundStyle(Palette.mutedInk)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// ‹ or › in a round button on iPhone, greyed at either end.
    private func stepButton(later: Bool) -> some View {
        let target = later ? index + 1 : index - 1
        let enabled = target >= 0 && target < count
        return Button {
            select(target)
        } label: {
            Image(systemName: later ? "chevron.right" : "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(enabled ? Palette.accent : Palette.mutedInk.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(Palette.page, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .keyboardShortcut(KeyboardShortcut(later ? "]" : "[", modifiers: .command))
        .accessibilityLabel(later ? "Later" : "Earlier")
    }

    /// The year across the card, on a money scale fitted to it.
    private var graph: some View {
        let pointsPerMonth = max(8, (width - 2 * PlanYearCardView.pad) / 12)
        let scale = timeline.scale(fitting: PlanStripWindow(wholeCards: [index]), inset: Double(PlanYearCardView.pad))
        return Color.clear
            .frame(height: PlanYearCardView.height)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topLeading) {
                if width > 0 {
                    PlanYearCardView(card: card, scale: scale, pointsPerMonth: pointsPerMonth,
                                     pointerX: pointer?.index == index ? pointer?.x : nil)
                }
            }
            .measuringWidth($width)
            .contentShape(Rectangle())
            .planGraphPointer($pointer, index: index)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityChartDescriptor(chartSummary)
    }

    /// The year for VoiceOver's audio graph and chart details: your money at
    /// each check-in and month end, and what its baseline expected.
    private var chartSummary: ChartSummary {
        let day = { (date: Date) in AmountFormat.mediumDate(CalendarDate(date, in: .current), locale: self.locale) }
        var series = [ChartSummary.Series(name: "Your money", points: card.actual.map { (day($0.date), $0.value) })]
        let expected = card.actual.compactMap { point in card.expected(on: point.date).map { (day(point.date), $0) } }
        if !expected.isEmpty {
            series.append(ChartSummary.Series(name: "What you planned", points: expected))
        }
        return ChartSummary(
            title: card.year.title,
            summary: PlanProgressText.story(card.year, currency: card.currency, locale: locale)
                .spoken(hidesAmounts: hidesAmounts),
            xTitle: "Date", yTitle: "Your money", series: series,
            describeValue: ChartStyle.spokenAmount(currency: card.currency, hidden: hidesAmounts))
    }

    private var accessibilityLabel: String {
        var label = card.year.title
        if !card.year.isLatest {
            label += ", " + PlanProgressText.change(card.year, currency: card.currency, locale: locale)
                .spoken(hidesAmounts: hidesAmounts)
        }
        if let against = PlanProgressText.againstJanuary(card.year, currency: card.currency, locale: locale) {
            label += ", " + against.spoken(hidesAmounts: hidesAmounts)
        }
        if let summary = card.summary {
            label += ". " + summary.spoken(hidesAmounts: hidesAmounts)
        }
        return label
    }
}

// MARK: - The year's chart

/// One year's chart (UI.md, "Year"): your money through it (the ink line,
/// a dot at each check-in, a blue one at the last) against what you planned
/// in January (dashed, in blue, labelled "planned in January" where it
/// starts), the space between them washed in blue where you're ahead and
/// orange where behind, a flag where you passed a milestone, the gridlines'
/// amounts at the edge and the months' initials along the bottom.
struct PlanYearCardView: View {
    let card: PlanProgressTimeline.Card
    let scale: PlanStripScale?
    var pointsPerMonth: CGFloat = 21
    /// Where the pointer is over the chart.
    var pointerX: CGFloat?

    @Environment(\.locale) private var locale

    /// The room either side of the plot, where it starts and ends across.
    static let pad: CGFloat = 12
    /// The chart's height: the top amount's room, the plot and the months.
    static let height: CGFloat = 22 + PlanStripPlot.height + 24

    private var width: CGFloat { Self.width(pointsPerMonth: pointsPerMonth) }

    private var plot: PlanStripPlot {
        PlanStripPlot(start: card.start, end: card.end, left: Self.pad, right: width - Self.pad, top: 22)
    }

    /// The chart's width: its twelve months and the room either side.
    static func width(pointsPerMonth: CGFloat) -> CGFloat {
        12 * pointsPerMonth + 2 * pad
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                draw(in: &context, size: size)
            }
            .frame(width: width, height: Self.height)
            // A new year fades the lines to their new places.
            .id(scale)
            .transition(.opacity)
            .accessibilityHidden(true)
            if let scale {
                PlanStripAmountLabels(scale: scale, plot: plot, width: width,
                                      line: card.actual.map { position(of: $0, scale) }, currency: card.currency)
                expectedLabel(scale)
            }
            months
            if let pointerX {
                readout(at: pointerX)
            }
        }
        .frame(width: width, height: Self.height, alignment: .topLeading)
        .privacySensitiveInFeedback()
    }

    /// "planned in January" by the dashed line, under it when you're ahead
    /// of it, above it when behind, so it stays off your line.
    @ViewBuilder
    private func expectedLabel(_ scale: PlanStripScale) -> some View {
        if card.expected.count >= 2 {
            let middle = card.expected[card.expected.count / 2]
            let at = position(of: middle, scale)
            let actual = card.actual.first { $0.date >= middle.date }?.value ?? middle.value
            let fitsBelow = at.y + 22 <= plot.bottom
            let fitsAbove = at.y - 22 >= plot.top
            let below = actual >= middle.value ? fitsBelow || !fitsAbove : !fitsAbove
            Text("planned in \(card.year.plannedIn(locale: locale))")
                .font(.caption)
                .foregroundStyle(Palette.accent)
                .planGraphLabel()
                .offset(x: max(Self.pad, min(at.x - 40, width - 150)), y: below ? at.y + 6 : at.y - 22)
        }
    }

    /// The months' initials along the bottom.
    private var months: some View {
        ForEach(1...12, id: \.self) { month in
            Text(Self.initial(month, locale: locale))
                .font(.caption2)
                .foregroundStyle(Palette.mutedInk)
                .frame(width: pointsPerMonth)
                .offset(x: Self.pad + CGFloat(month - 1) * pointsPerMonth, y: plot.bottom + 6)
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

    /// The year at the pointer (UI.md, "Year"): a rule at the nearest
    /// value, and a callout like the net-worth chart's over its history.
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
                ChartCallout(maxWidth: PlanGraphCallout.width(in: width)) {
                    callout(for: found)
                }
                .offset(x: PlanGraphCallout.leading(at: at, in: width), y: plot.top + 4)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The day and where its value comes from ("31 Mar 2026 · check-in"),
    /// then as the net-worth chart reads its history, the money, and what
    /// was planned and the gap in rows, all short, then a milestone reached
    /// there and what changed that day.
    @ViewBuilder
    private func callout(for found: Reading) -> some View {
        let source = card.checkIns.contains(found.point.date) ? "check-in" : "from prices"
        ChartCalloutDate(found.point.date, precision: .day, detail: source)
        ChartCalloutTotal(found.point.value, currency: card.currency)
        if !found.point.isComplete {
            Text("Not every price is known")
                .font(.caption2)
                .foregroundStyle(Palette.secondaryInk)
        }
        if let expected = found.expected {
            let gap = found.point.value - expected
            ChartCalloutRow("Planned in \(card.year.plannedIn(locale: locale))", amount: expected,
                            currency: card.currency)
            ChartCalloutRow(gap >= 0 ? "Ahead" : "Behind", amount: abs(gap), currency: card.currency)
        }
        let text = PlanMilestoneText(currency: card.currency, locale: locale)
        ForEach(found.milestones) { reached in
            ChartCalloutMarker(text.reachedInRow(reached.milestone)) {
                PlanGraphFlag()
            }
        }
        ForEach(Array(found.notes.prefix(2))) { note in
            AmountSentenceText(note.text)
                .font(.caption2)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
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

    /// Your money (UI.md, "Year"): solid into each check-in, lighter
    /// where it's valued from what you held and its prices, dotted where a
    /// price or a rate is missing (those holdings count as zero); a dot at
    /// each check-in and a larger blue one at the last point.
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
        let solid = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
        for run in runs {
            switch run.kind {
            case .checkIn:
                context.stroke(run.path, with: .color(Palette.ink), style: solid)
            case .prices:
                context.stroke(run.path, with: .color(Palette.ink.opacity(0.4)), style: solid)
            case .missing:
                context.stroke(run.path, with: .color(Palette.ink),
                               style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [0.5, 4]))
            }
        }
        for point in card.actual.dropLast() where card.checkIns.contains(point.date) {
            let center = position(of: point, scale)
            context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                         with: .color(Palette.ink))
        }
        if let last = card.actual.last {
            let center = position(of: last, scale)
            let dot = Path(ellipseIn: CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9))
            context.fill(dot, with: .color(Palette.accent))
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
            context.fill(area, with: .color(gap.ahead ? Palette.accent.opacity(0.12) : Palette.orange.opacity(0.22)))
        }
        if card.expected.count >= 2 {
            context.stroke(line(card.expected, scale), with: .color(Palette.accent.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        var axis = Path()
        axis.move(to: CGPoint(x: 0, y: plot.bottom + 1))
        axis.addLine(to: CGPoint(x: size.width, y: plot.bottom + 1))
        context.stroke(axis, with: .color(Palette.border), lineWidth: 1)
        drawMoney(in: &context, scale)
        for reached in card.milestones {
            guard let point = flagPoint(for: reached) else { continue }
            let flag = PlanMilestoneFlag.path(at: position(of: point, scale))
            context.fill(flag, with: .color(Palette.accent))
            context.stroke(flag, with: .color(Palette.card), lineWidth: 1)
        }
    }
}

#Preview("A year") {
    // The example library's latest year, read at the pointer, and its first
    // year with amounts hidden.
    let library = PreviewLibrary.library
    let asOf = PreviewLibrary.latestCheckIn
    let progress = PlanProgress(plan: "base", document: library.plans["base"], library: library,
                                valuator: PreviewLibrary.valuator, asOf: asOf)
    let timeline = PlanProgressTimeline(progress, text: PlanMilestoneText(currency: library.settings.baseCurrency))
    let cards = timeline.cards
    ScrollView {
        VStack(alignment: .leading, spacing: Metrics.l) {
            if let latest = cards.indices.last {
                PlanYearChartCard(timeline: timeline, index: latest, select: { _ in })
                let scale = timeline.scale(fitting: PlanStripWindow(wholeCards: [latest]),
                                           inset: Double(PlanYearCardView.pad))
                PlanYearCardView(card: cards[latest], scale: scale, pointsPerMonth: 26,
                                 pointerX: PlanYearCardView.width(pointsPerMonth: 26) * 0.55)
                    .background(Palette.card)
            }
            if !cards.isEmpty {
                PlanYearChartCard(timeline: timeline, index: 0, select: { _ in })
                    .redacted(reason: .privacy)
            }
        }
        .padding()
    }
    .background(Palette.page)
}
