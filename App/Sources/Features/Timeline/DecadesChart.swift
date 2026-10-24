import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The Timeline at *Decades* (UI.md, "Decades"): your records to now, then
/// the main plan's futures to its end, on one chart across your ages
/// (``DecadesPlot``): the typical future as a line, half of the futures in
/// the darker band and 8 in 10 in the lighter one, *Now* and the day you
/// stop marked, and the plan's chapters as a band under the ages. A
/// one-row legend above it, and under it the notes on missing or old
/// prices.
///
/// The past is plan assets through the latest check-in, where the
/// projection starts: the projection is of what the plan counts, so the
/// past meets it there. It reaches back as far as the accounts' time span
/// (`overview.range`). Without a projection yet, it calculates the main
/// plan, with its progress (or why it can't run) above the chart; until
/// then the past is your whole net worth, through today.
struct DecadesChart: View {
    let plan: PlanDocument
    let results: PlanResults?
    let today: CalendarDate
    /// The chart's height, the ages and the chapters under the plot included.
    var chartHeight: CGFloat = 220
    /// Whether the legend sits above the chart; off where the page puts it
    /// in its card's header.
    var showsLegend = true

    @AppStorage("overview.range") private var range: HistoryRange = .threeYears
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @State private var fillsPastPrices = false

    private var valuator: Valuator { library.valuator }

    var body: some View {
        let projection = results?.portfolio ?? []
        let future = !projection.isEmpty
        let history = HistoryChartData(valuator: valuator, through: future ? library.asOfDate : today, range: range,
                                       projection: projection)
        VStack(alignment: .leading, spacing: Metrics.m) {
            if !future {
                futureStatus(plan.id)
            }
            if showsLegend && future {
                DecadesLegend()
            }
            DecadesPlot(data: plotData(history, future: future), height: chartHeight)
            if let missing = history.missing {
                missingNoteView(missing)
            }
            if let summary = history.oldPrices {
                OldPriceNoteView(text: OldPriceNote.text(summary) { valuator.instruments[$0]?.name ?? $0.rawValue }) {
                    fillsPastPrices = true
                }
            }
        }
        .pastPricesSheet(isPresented: $fillsPastPrices)
        .task(id: plan.id) { await calculateForFuture() }
    }

    /// What the plot draws: the past, the futures, *Now*, the day you stop
    /// and the chapters, with the ages they're labelled by.
    private func plotData(_ history: HistoryChartData, future: Bool) -> DecadesPlotData {
        let birthDate = library.settings.person?.birthDate
        let now = future ? library.asOfDate : today
        var nowLabel = "Now"
        if let birthDate {
            nowLabel = "Now, \(DecadesPlotData.age(on: now, born: birthDate))"
        }
        var retirement: Date?
        var retirementLabel: String?
        if future, let results, let day = results.details.focus.retirementDate {
            retirement = day.dateValue
            retirementLabel = "\(AmountFormat.mediumDate(day, locale: locale)), at \(results.details.focus.age)"
        }
        var chapters: [DecadesPlotData.Chapter] = []
        if future, let model = PlanChaptersModel(
            plan: plan, library: library.library, results: results,
            recordedAge: library.library.headlines(for: plan.id).last?.earliestAge, today: library.asOfDate) {
            let all = model.chapters.chapters
            chapters = all.indices.map { index in
                DecadesPlotData.Chapter(id: index, dates: model.dates(ofChapterAt: index),
                                        name: model.title(of: all[index]),
                                        color: PlanChapterColors.color(model.style(of: all[index])))
            }
        }
        return DecadesPlotData(past: history.points, fan: history.projection, now: now.dateValue, nowLabel: nowLabel,
                               retirement: retirement, retirementLabel: retirementLabel, birthDate: birthDate,
                               chapters: chapters, currency: library.baseCurrency,
                               title: history.scope == .planAssets ? "Money in the plan" : "Net worth")
    }

    /// Without results, calculates the main plan for its projection, when
    /// nothing is running. After a failure it waits for *Try Again*, so a
    /// plan that can't run isn't retried on every visit.
    private func calculateForFuture() async {
        guard results == nil, !isCalculating(plan.id), plans.errors[plan.id] == nil else { return }
        await plans.run(plan.id)
    }

    private func isCalculating(_ plan: PlanID) -> Bool {
        plans.isRunning(plan, .base) || plans.isRunning(plan, .checkIn)
    }

    /// Above the chart without a projection: the main plan's calculation
    /// with its bar, why it can't run (with *Try Again* and *Open Plan*),
    /// or *Calculate*.
    @ViewBuilder
    private func futureStatus(_ plan: PlanID) -> some View {
        if let progress = plans.progress(of: plan, .base) ?? plans.progress(of: plan, .checkIn) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                HStack {
                    Text("Calculating \(planTitle)'s projection…")
                        .lineLimit(1)
                        .privacySensitiveInFeedback()
                    Spacer(minLength: Metrics.s)
                    Text(PlanRunText.overall(progress, locale: locale))
                        .monospacedDigit()
                }
                ProgressView(value: min(1, max(0, progress.fraction)), total: 1)
                    .tint(Palette.accent)
            }
            .font(.subheadline)
            .foregroundStyle(Palette.secondaryInk)
            .accessibilityElement(children: .combine)
        } else if let error = plans.errors[plan] {
            VStack(alignment: .leading, spacing: Metrics.s) {
                Label("\(planTitle) can't be calculated: \(error)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
                HStack(spacing: Metrics.s) {
                    Button("Try Again") { Task { await plans.run(plan) } }
                    Button("Open Plan") { navigation.showPlan(plan) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .font(.subheadline)
        } else {
            HStack(spacing: Metrics.s) {
                Text("Calculate \(planTitle) to see its futures.")
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
                Spacer(minLength: Metrics.s)
                Button("Calculate") { Task { await plans.run(plan) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .font(.subheadline)
        }
    }

    /// Partial totals are drawn dashed: what they're missing, with *Fill In
    /// Past Prices…* when some of it is prices or rates.
    private func missingNoteView(_ missing: MissingValues) -> some View {
        let text = MissingValueNote.overview(missing, accountName: { valuator.accounts[$0]?.name ?? $0.rawValue },
                                             instrumentName: { valuator.instruments[$0]?.name ?? $0.rawValue })
        let canFill = missing.gaps.contains(where: { $0.item.isPriceOrRate })
        let fill: (() -> Void)? = canFill ? { fillsPastPrices = true } : nil
        return OldPriceNoteView(text: text, systemImage: "exclamationmark.triangle", fill: fill)
    }

    private var planTitle: String {
        plan.name ?? "your plan"
    }
}

/// The decades chart's legend, in one row: the typical future, half of the
/// futures and 8 in 10 of them.
struct DecadesLegend: View {
    var body: some View {
        ChartLegendRow(items: [
            ChartLegendItem(name: "Typical", swatch: .line(.accent, dashed: false)),
            ChartLegendItem(name: "Half of futures", swatch: .band(opacity: ProjectionLegend.innerBand)),
            ChartLegendItem(name: "8 in 10", swatch: .band(opacity: ProjectionLegend.outerBand)),
        ])
    }
}

/// What ``DecadesPlot`` draws.
struct DecadesPlotData {
    /// One of the plan's chapters, as a band under the ages.
    struct Chapter: Identifiable {
        var id: Int
        var dates: ClosedRange<Date>
        var name: String
        var color: Color
    }

    /// Your money to now: plan assets with a projection, else net worth.
    var past: [ChartPoint]
    /// The plan's futures from now.
    var fan: [FanPoint]
    var now: Date
    /// "Now, 38".
    var nowLabel: String
    /// The day the plan's futures stop work; `nil` without one.
    var retirement: Date?
    /// "27 Mar 2051, at 63".
    var retirementLabel: String?
    /// Labels the time axis by age; by year without it.
    var birthDate: CalendarDate?
    var chapters: [Chapter]
    var currency: CurrencyCode
    /// What the past is, for VoiceOver: "Money in the plan", "Net worth".
    var title: String

    /// Your age on `date`, born on `birthDate`.
    static func age(on date: CalendarDate, born birthDate: CalendarDate) -> Int {
        let years = date.year - birthDate.year
        return (date.month, date.day) < (birthDate.month, birthDate.day) ? years - 1 : years
    }
}

/// Where everything on the decades plot goes for its size: dates across
/// from the first record to the plan's end, money up on a scale that fits
/// the past, the typical future and half of the futures (the lighter band
/// may run off the top, cut at the edge), the amounts in a column at the
/// right, the ages under the plot and the chapters under them.
struct DecadesGeometry {
    let data: DecadesPlotData
    let width: CGFloat
    let height: CGFloat
    let start: Date
    let end: Date
    let scale: AmountScale
    /// The futures with their bands cut at the plot's edges.
    let fan: [FanPoint]

    /// The amounts' column at the right.
    static let labelColumn: CGFloat = 40
    /// Above the plot: *Now* and the day you stop.
    static let topStrip: CGFloat = 26
    /// The ages under the plot.
    static let axisHeight: CGFloat = 18
    /// The chapters under the ages.
    static let bandHeight: CGFloat = 18

    init(data: DecadesPlotData, width: CGFloat, height: CGFloat) {
        self.data = data
        self.width = width
        self.height = height
        let first = data.past.first?.date ?? data.fan.first?.date ?? data.now
        let last = data.fan.last?.date ?? data.past.last?.date ?? data.now
        start = first
        end = max(last, first.addingTimeInterval(86_400 * 31))
        let chapterRoom = data.chapters.isEmpty ? 0 : Self.bandHeight + 4
        let plotHeight = Double(max(1, height - Self.topStrip - Self.axisHeight - chapterRoom))
        let projection = ProjectionScale(history: data.past.filter(\.isComplete).map(\.value), fan: data.fan,
                                         markerHeadroom: 0, plotHeight: plotHeight)
        scale = projection.scale
        fan = data.fan.map(projection.clamped)
    }

    var left: CGFloat { 4 }
    var right: CGFloat { max(left + 1, width - Self.labelColumn) }
    var top: CGFloat { Self.topStrip }
    var bottom: CGFloat {
        max(top + 1, height - Self.axisHeight - (data.chapters.isEmpty ? 0 : Self.bandHeight + 4))
    }
    /// Where the chapters' band starts down the chart.
    var bandTop: CGFloat { bottom + Self.axisHeight }

    func x(_ date: Date) -> CGFloat {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return left }
        let share = min(1, max(0, date.timeIntervalSince(start) / span))
        return left + CGFloat(share) * (right - left)
    }

    func y(_ value: Double) -> CGFloat {
        let low = scale.domain.lowerBound
        let high = scale.domain.upperBound
        let share = high > low ? (value - low) / (high - low) : 0
        return bottom - CGFloat(min(1, max(0, share))) * (bottom - top)
    }

    func date(at x: CGFloat) -> Date {
        let share = right > left ? Double(min(1, max(0, (x - left) / (right - left)))) : 0
        return start.addingTimeInterval(end.timeIntervalSince(start) * share)
    }

    /// A tick on the time axis: an age (or a year without a birth date) on its day.
    struct TimeTick: Identifiable {
        var date: Date
        var label: String
        var id: Date { date }
    }

    /// Ages every 1, 2, 5, 10 or 20 years, as many as fit; years without a
    /// birth date.
    var timeTicks: [TimeTick] {
        let calendar = Calendar.current
        let firstYear = calendar.component(.year, from: start)
        let lastYear = max(firstYear, calendar.component(.year, from: end))
        let room = max(1, Int((right - left) / 34))
        let years = lastYear - firstYear + 1
        let step = [1, 2, 5, 10, 20, 50].first { years / $0 <= room } ?? 50
        var ticks: [TimeTick] = []
        if let birth = data.birthDate {
            let lowest = max(0, firstYear - birth.year)
            let highest = max(lowest, lastYear - birth.year)
            for age in lowest...highest where age % step == 0 {
                let day = birth.adding(years: age).dateValue
                if day >= start && day <= end { ticks.append(TimeTick(date: day, label: "\(age)")) }
            }
        } else {
            for year in firstYear...lastYear where year % step == 0 {
                if let day = CalendarDate(year: year, month: 1, day: 1)?.dateValue, day >= start, day <= end {
                    ticks.append(TimeTick(date: day, label: String(year)))
                }
            }
        }
        return ticks
    }

    /// A chapter's band across, inside the plot; `nil` when it's off it.
    func band(of chapter: DecadesPlotData.Chapter) -> CGRect? {
        let from = x(max(chapter.dates.lowerBound, start)) + 1
        let to = x(min(chapter.dates.upperBound, end)) - 1
        guard to - from >= 2 else { return nil }
        return CGRect(x: from, y: bandTop, width: to - from, height: Self.bandHeight)
    }

    // MARK: Drawing

    func draw(in context: inout GraphicsContext) {
        for tick in scale.ticks where tick > scale.domain.lowerBound {
            var gridline = Path()
            gridline.move(to: CGPoint(x: left, y: y(tick)))
            gridline.addLine(to: CGPoint(x: right, y: y(tick)))
            context.stroke(gridline, with: .color(Palette.gridline), lineWidth: 0.5)
        }
        var axis = Path()
        axis.move(to: CGPoint(x: left, y: bottom))
        axis.addLine(to: CGPoint(x: right, y: bottom))
        context.stroke(axis, with: .color(Palette.border), lineWidth: 1)

        if fan.count >= 2 {
            context.fill(band(\.p10, \.p90), with: .color(Palette.accent.opacity(ProjectionLegend.outerBand)))
            context.fill(band(\.p25, \.p75), with: .color(Palette.accent.opacity(ProjectionLegend.innerBand)))
            var median = Path()
            for (offset, point) in fan.enumerated() {
                let at = CGPoint(x: x(point.date), y: y(point.p50))
                if offset == 0 { median.move(to: at) } else { median.addLine(to: at) }
            }
            context.stroke(median, with: .color(Palette.accent),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
        drawPast(in: &context)

        if !fan.isEmpty || data.retirement != nil {
            var now = Path()
            now.move(to: CGPoint(x: x(data.now), y: top - 10))
            now.addLine(to: CGPoint(x: x(data.now), y: bottom))
            context.stroke(now, with: .color(Palette.ink), lineWidth: 1)
        }
        if let retirement = data.retirement, retirement > start, retirement < end {
            var rule = Path()
            rule.move(to: CGPoint(x: x(retirement), y: top - 4))
            rule.addLine(to: CGPoint(x: x(retirement), y: bottom))
            context.stroke(rule, with: .color(Palette.accent), lineWidth: 1.2)
        }
        for chapter in data.chapters {
            if let rect = band(of: chapter) {
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(chapter.color.opacity(0.35)))
            }
        }
    }

    /// Your money to now in ink: solid, dashed and grey where a total is
    /// partial (a price or a rate missing).
    private func drawPast(in context: inout GraphicsContext) {
        var complete = Path()
        var partial = Path()
        for (from, to) in zip(data.past, data.past.dropFirst()) {
            let a = CGPoint(x: x(from.date), y: y(from.value))
            let b = CGPoint(x: x(to.date), y: y(to.value))
            if from.isComplete && to.isComplete {
                complete.move(to: a)
                complete.addLine(to: b)
            } else {
                partial.move(to: a)
                partial.addLine(to: b)
            }
        }
        context.stroke(complete, with: .color(Palette.ink),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        context.stroke(partial, with: .color(Palette.secondaryInk),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round, dash: [3, 4]))
    }

    /// The area between two percentiles of the futures.
    private func band(_ low: KeyPath<FanPoint, Double>, _ high: KeyPath<FanPoint, Double>) -> Path {
        var path = Path()
        for (offset, point) in fan.enumerated() {
            let at = CGPoint(x: x(point.date), y: y(point[keyPath: high]))
            if offset == 0 { path.move(to: at) } else { path.addLine(to: at) }
        }
        for point in fan.reversed() {
            path.addLine(to: CGPoint(x: x(point.date), y: y(point[keyPath: low])))
        }
        path.closeSubpath()
        return path
    }

    // MARK: At the pointer

    /// What the pointer reads: a value of the past, or the futures beyond it.
    struct Reading {
        var date: Date
        /// Where the dot goes: the value, or the typical future cut at the plot's edge.
        var value: Double
        var point: ChartPoint?
        /// The futures there, uncut.
        var fan: FanPoint?
    }

    func reading(at pointerX: CGFloat) -> Reading? {
        let at = date(at: pointerX)
        let lastPast = data.past.last?.date ?? .distantPast
        if at > lastPast || data.past.isEmpty,
           let index = fan.indices.min(by: {
               abs(fan[$0].date.timeIntervalSince(at)) < abs(fan[$1].date.timeIntervalSince(at))
           }), data.fan.indices.contains(index) {
            return Reading(date: fan[index].date, value: fan[index].p50, point: nil, fan: data.fan[index])
        }
        guard let point = data.past.nearest(to: at) else { return nil }
        return Reading(date: point.date, value: point.value, point: point, fan: nil)
    }
}

/// The decades chart's plot (UI.md, "Decades"), drawn for its width: the
/// gridlines with their amounts at the right, your money to now in ink,
/// the futures from now (the typical one as a blue line, half of them in
/// the darker band, 8 in 10 in the lighter one), a rule at *Now* ("Now,
/// 38") and one at the day you stop in a blue label ("27 Mar 2051, at
/// 63"), the ages along the bottom, and the plan's chapters as a band under
/// them, each named where its name fits. The pointer, or a finger touched
/// and held, reads the money there in a callout: your value, or the
/// typical future with the top and bottom 10%.
struct DecadesPlot: View {
    let data: DecadesPlotData
    var height: CGFloat = 220

    @State private var width: CGFloat = ChartStyle.defaultWidth
    @State private var pointer: PlanGraphPointer?
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.locale) private var locale

    private var hidesAmounts: Bool { redactionReasons.hidesAmounts }

    var body: some View {
        if data.past.isEmpty && data.fan.isEmpty {
            ChartPlaceholder(text: "Your money appears here after the first check-in.", height: height)
        } else {
            let geometry = DecadesGeometry(data: data, width: width, height: height)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    geometry.draw(in: &context)
                }
                .accessibilityHidden(true)
                amountLabels(geometry)
                timeLabels(geometry)
                chapterLabels(geometry)
                markerLabels(geometry)
                if let pointerX = pointer?.x {
                    readout(at: pointerX, geometry)
                }
            }
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .measuringWidth($width)
            .contentShape(Rectangle())
            .planGraphPointer($pointer, index: 0)
            .privacySensitiveInFeedback()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spokenSummary))
            .accessibilityChartDescriptor(summary)
        }
    }

    /// The gridlines' amounts in the column at the right; multiples of
    /// today's value while amounts are hidden.
    private func amountLabels(_ geometry: DecadesGeometry) -> some View {
        let axis = AmountAxisTicks(scale: geometry.scale, hidesAmounts: hidesAmounts,
                                   relativeTo: data.past.last(where: \.isComplete)?.value ?? data.fan.first?.p50,
                                   locale: locale)
        let column = DecadesGeometry.labelColumn - 4
        return ForEach(axis.ticks, id: \.self) { tick in
            AmountAxisLabel(text: tick.label, isRelative: axis.isRelative)
                .lineLimit(1)
                .frame(width: column, alignment: .trailing)
                .position(x: width - column / 2, y: geometry.y(tick.value))
        }
    }

    private func timeLabels(_ geometry: DecadesGeometry) -> some View {
        ForEach(geometry.timeTicks) { tick in
            Text(verbatim: tick.label)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Palette.mutedInk)
                .fixedSize()
                .position(x: geometry.x(tick.date), y: geometry.bottom + DecadesGeometry.axisHeight / 2 + 1)
        }
    }

    /// Each chapter's name in its band, where it fits.
    private func chapterLabels(_ geometry: DecadesGeometry) -> some View {
        ForEach(data.chapters) { chapter in
            if let rect = geometry.band(of: chapter), rect.width >= CGFloat(chapter.name.count) * 6 + 12 {
                Text(chapter.name)
                    .font(.caption2)
                    .foregroundStyle(Palette.ink.opacity(0.75))
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: rect.minX + 6, y: rect.minY + 3)
            }
        }
    }

    /// "Now, 38" beside its rule, and the day you stop in its blue label,
    /// kept clear of it and inside the plot.
    @ViewBuilder
    private func markerLabels(_ geometry: DecadesGeometry) -> some View {
        let nowX = geometry.x(data.now)
        let flipsNow = nowX > width * 0.7
        let nowEnd = nowX + 6 + CGFloat(data.nowLabel.count) * 6.5
        if !data.fan.isEmpty || data.retirement != nil {
            Text(data.nowLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 120, alignment: flipsNow ? .trailing : .leading)
                .offset(x: flipsNow ? nowX - 124 : nowX + 4, y: 2)
        }
        if let retirement = data.retirement, let label = data.retirementLabel, retirement > geometry.start,
           retirement < geometry.end {
            let pill = CGFloat(label.count) * 6.2 + 18
            let at = geometry.x(retirement)
            let clear = retirement > data.now && !flipsNow ? max(at, nowEnd + 6 + pill / 2) : at
            let centre = min(max(clear, pill / 2), max(pill / 2, geometry.right - pill / 2))
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Palette.accent, in: Capsule())
                .position(x: centre, y: 11)
        }
    }

    /// A rule and a dot at the value nearest the pointer, and a callout.
    @ViewBuilder
    private func readout(at pointerX: CGFloat, _ geometry: DecadesGeometry) -> some View {
        if let reading = geometry.reading(at: pointerX) {
            let at = geometry.x(reading.date)
            ZStack(alignment: .topLeading) {
                PlanGraphRule(height: geometry.bottom - geometry.top)
                    .offset(x: at - 0.5, y: geometry.top)
                PlanGraphDot(color: reading.fan == nil ? Palette.ink : Palette.accent)
                    .offset(x: at - 4.5, y: geometry.y(reading.value) - 4.5)
                ChartCallout(maxWidth: PlanGraphCallout.width(in: width)) {
                    callout(for: reading)
                }
                .offset(x: PlanGraphCallout.leading(at: at, in: width), y: geometry.top + 4)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The date and your age, then your value, or the typical future with
    /// the top and bottom 10%.
    @ViewBuilder
    private func callout(for reading: DecadesGeometry.Reading) -> some View {
        if let fan = reading.fan {
            ChartCalloutDate(fan.date, precision: .month, detail: ageWords(fan.date))
            ChartCalloutProjection(fan: fan, currency: data.currency)
        } else if let point = reading.point {
            ChartCalloutDate(point.date, detail: ageWords(point.date))
            ChartCalloutTotal(point.value, currency: data.currency)
            if !point.isComplete {
                Text("Partial: some values are missing")
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    /// "at 46"; `nil` without a birth date.
    private func ageWords(_ date: Date) -> String? {
        data.birthDate.map { "at \(DecadesPlotData.age(on: CalendarDate(date, in: .current), born: $0))" }
    }

    private var spokenSummary: String {
        var text = "\(data.title) to now"
        if !data.fan.isEmpty {
            text += ", then the plan's futures to its end: the typical future, with half of them in a darker band "
                + "and 8 in 10 in a lighter one"
        }
        if let label = data.retirementLabel {
            text += ". You stop on \(label)"
        }
        if !data.chapters.isEmpty {
            text += ". Chapters: \(Wording.list(data.chapters.map(\.name)))"
        }
        return text + "."
    }

    private var summary: ChartSummary {
        let day = { (date: Date) in AmountFormat.mediumDate(CalendarDate(date, in: .current), locale: self.locale) }
        var series: [ChartSummary.Series] = []
        if !data.past.isEmpty {
            series.append(ChartSummary.Series(name: data.title, points: data.past.map { (day($0.date), $0.value) }))
        }
        if !data.fan.isEmpty {
            series.append(ChartSummary.Series(name: "Typical future", points: data.fan.map { (day($0.date), $0.p50) }))
        }
        return ChartSummary(
            title: "Your money over the decades", summary: spokenSummary, xTitle: "Date", yTitle: data.title,
            series: series, describeValue: ChartStyle.spokenAmount(currency: data.currency, hidden: hidesAmounts))
    }
}
