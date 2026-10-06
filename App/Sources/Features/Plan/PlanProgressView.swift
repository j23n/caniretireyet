import Model
import Planner
import SwiftUI
import Tracker

/// Progress (UI.md, "Progress"; PROGRESS.md): whether you're on track, then
/// year by year on a strip that opens at today, each year's card with your
/// money against what January expected and where the answer moved; the
/// chosen year's story below; what's next in the plan; and, folded away,
/// the answer over time and your money against any baseline.
struct PlanProgressView: View {
    let session: PlanSession
    var isWide = false
    /// Asks for a label and saves a baseline (the screen owns the alert).
    let onSaveBaseline: () -> Void
    /// Shows the plan.
    var onShowPlan: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale
    @State private var selectedBaseline: BaselineID?
    /// The year chosen on the strip; the latest when `nil`.
    @State private var selectedYear: Int?
    @State private var showsMoreCharts = false
    @State private var showsPastBaseline = false
    /// The day *Add Past Baseline…* starts on, when a year asked for it.
    @State private var pastBaselineDay: CalendarDate?
    @State private var cache = PlanProgressCache()

    private var gutter: CGFloat { isWide ? Metrics.xl : Metrics.l }

    private var answerHistory: PlanAnswerHistory {
        PlanAnswerHistory(library.library.headlines(for: session.planID))
    }

    private var baselines: [PlanBaselineEntry] {
        PlanBaselineComparison.baselines(for: session.planID, in: library.library)
    }

    private var milestoneText: PlanMilestoneText {
        PlanMilestoneText(currency: library.baseCurrency, hidesAmounts: hidesAmounts, locale: locale)
    }

    var body: some View {
        let progress = progressModel
        let years = progress.years
        let timeline = progress.timeline
        let milestones = session.plan.map {
            PlanMilestones(plan: $0, library: library.library, valuator: library.valuator, asOf: library.asOfDate,
                           results: session.shownResults, reached: progress.reached)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                headline(years.first)
                    .padding(.horizontal, gutter)
                yearByYear(timeline)
                if let milestones {
                    PlanMilestonesCard(milestones: milestones, text: milestoneText, isWide: isWide,
                                       hasResults: session.shownResults != nil)
                        .padding(.horizontal, gutter)
                }
                footer
                    .padding(.horizontal, gutter)
                moreCharts
                    .padding(.horizontal, gutter)
            }
            .padding(.vertical, gutter)
        }
        .background(Palette.page)
        .onAppear {
            if selectedBaseline == nil { selectedBaseline = baselines.first?.id }
        }
        .sheet(isPresented: $showsPastBaseline) {
            if let plan = session.plan {
                PlanPastBaselineSheet(session: session, plan: plan, startingOn: pastBaselineDay)
            }
        }
    }

    /// The years, the milestones reached and the strip, worked out once for
    /// each state of the library and the plan (``PlanProgressModel``).
    private var progressModel: PlanProgressModel {
        let asOf = library.asOfDate
        let key = PlanProgressModel.Key(revision: library.revision, plan: session.planID,
                                        document: session.plan?.hashValue ?? 0, asOf: asOf,
                                        hidesAmounts: hidesAmounts, locale: locale.identifier)
        return cache.model(for: key) {
            PlanProgressModel(plan: session.planID, document: session.plan, library: library.library,
                              valuator: library.valuator, asOf: asOf, text: milestoneText)
        }
    }

    // MARK: Are you on track?

    @ViewBuilder
    private func headline(_ latest: PlanProgressYear?) -> some View {
        let position = latest?.position
        let title = PlanProgressText.headline(position)
        let detail = PlanProgressText.headlineDetail(latest, currency: latest?.positionCurrency ?? library.baseCurrency,
                                                     hidesAmounts: hidesAmounts, locale: locale)
        if isWide {
            HStack(alignment: .top, spacing: Metrics.l) {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 460, alignment: .leading)
                Spacer(minLength: Metrics.l)
                HStack(alignment: .top, spacing: Metrics.s) {
                    ForEach(tiles) { tile in
                        PlanStatTile(title: tile.title, value: tile.value)
                    }
                }
            }
        } else {
            Card {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Are you on track?")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                    Text(title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                let tiles = self.tiles
                if !tiles.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: Metrics.m, verticalSpacing: Metrics.xs) {
                        ForEach(tiles) { tile in
                            GridRow {
                                Text(tile.title)
                                    .foregroundStyle(Palette.secondaryInk)
                                Text(tile.value)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .font(.footnote)
                }
            }
        }
    }

    /// A figure beside the headline on the Mac.
    private struct Tile: Hashable, Identifiable {
        var title: String
        var value: String
        var id: String { title }
    }

    /// "To go · 15½ years", "Since Jan 2024 · 3 years sooner", "September ·
    /// Saved 1.400 € · +2.800 €".
    private var tiles: [Tile] {
        var tiles: [Tile] = []
        if let headline = session.shownResults?.headline {
            if headline.canRetireNow {
                tiles.append(Tile(title: "To go", value: "None: you could stop"))
            } else if let date = headline.earliestDate {
                let months = library.asOfDate.yearMonth.months(to: date.yearMonth)
                if months > 0 { tiles.append(Tile(title: "To go", value: Self.duration(months: months))) }
            }
        }
        if let change = answerHistory.change {
            let count = abs(change.years)
            let value = change.years == 0 ? "No change"
                : "\(count == 1 ? "A year" : "\(count) years") \(change.years < 0 ? "sooner" : "later")"
            tiles.append(Tile(title: "Since \(PlanResultsText.shortMonthYear(change.since, locale: locale))",
                              value: value))
        }
        if let coast = session.shownResults?.details?.coast, let age = coast.earliestAge {
            tiles.append(Tile(title: "Saving nothing more", value: "Retire at \(age)"))
        }
        if let report = library.valuator.changeSinceLastCheckIn(asOf: library.asOfDate, in: .planAssets) {
            let saved = hidesAmounts ? AmountFormat.hidden
                : AmountFormat.signedAmount(report.total.newMoney, currency: report.currency, locale: locale)
            let markets = hidesAmounts ? AmountFormat.hidden
                : AmountFormat.signedAmount(report.total.market, currency: report.currency, locale: locale)
            tiles.append(Tile(title: AmountFormat.monthName(report.to, locale: locale),
                              value: "Saved \(saved) · markets \(markets)"))
        }
        return tiles
    }

    /// "15½ years", "8 months".
    static func duration(months: Int) -> String {
        guard months >= 12 else { return months == 1 ? "1 month" : "\(months) months" }
        let years = months / 12
        let half = months % 12 >= 6 ? "½" : ""
        return "\(years)\(half) " + (years == 1 && half.isEmpty ? "year" : "years")
    }

    // MARK: Year by year

    @ViewBuilder
    private func yearByYear(_ timeline: PlanProgressTimeline) -> some View {
        let cards = timeline.cards
        if cards.isEmpty {
            Card {
                Text("Your progress shows here, year by year, from your first check-in.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, gutter)
        } else {
            let selected = selectedYear.flatMap { year in cards.firstIndex { $0.year.year == year } }
                ?? cards.count - 1
            let selection = Binding<Int>(
                get: { selected },
                set: { index in if cards.indices.contains(index) { selectedYear = cards[index].year.year } })
            yearsHeader(count: cards.count, selection: selection)
                .padding(.horizontal, gutter)
            PlanYearStrip(timeline: timeline, selection: selection, pointsPerMonth: isWide ? 26 : 20,
                          inset: gutter)
            PlanYearDetails(card: cards[selected], index: selected, count: cards.count, isWide: isWide,
                            onSelect: { selection.wrappedValue = $0 },
                            onAddPastBaseline: library.canEdit && session.plan != nil ? { year in
                                pastBaselineDay = CalendarDate(year: year, month: 1, day: 1)
                                showsPastBaseline = true
                            } : nil)
                .padding(.horizontal, gutter)
        }
    }

    private func yearsHeader(count: Int, selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Year by year")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text((count > 1 ? "Opens at today. Scroll back for earlier years." : "Opens at today.")
                        + (isWide ? "" : " Touch and hold a line to read it."))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Spacer(minLength: Metrics.s)
                if isWide && count > 1 {
                    PlanStepButtons(index: selection.wrappedValue, count: count, today: count - 1) {
                        selection.wrappedValue = $0
                    }
                }
            }
            PlanYearLegend(isWide: isWide)
        }
    }

    // MARK: What's next

    private var footer: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: Metrics.m) {
            if let model = session.chapters, model.chapters.chapters.count > 1 {
                let next = model.chapters.chapters[1]
                HStack(alignment: .center, spacing: Metrics.s) {
                    Text("Next in your plan")
                        .foregroundStyle(Palette.secondaryInk)
                    PlanChapterBadge(number: 2, style: model.style(of: next))
                    Text("\(model.title(of: next)), from \(next.ages.lowerBound) in \(String(next.years.lowerBound))")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
            }
            // On one row on the Mac and iPad, two on iPhone: chosen by the
            // layout, not measured, so the page's size never depends on it.
            if isWide {
                HStack(spacing: Metrics.m) {
                    openAndSave
                    addPast
                }
            } else {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    HStack(spacing: Metrics.m) {
                        openAndSave
                    }
                    addPast
                }
            }
            Text("A baseline remembers what you expect today, so you can measure against it later. "
                + "One is saved at the first check-in of each year. A past baseline is what you planned before: "
                + "the years without their own are measured against it.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: shape)
        .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
    }

    @ViewBuilder
    private var openAndSave: some View {
        if let onShowPlan {
            Button("Open Plan", action: onShowPlan)
                .buttonStyle(.bordered)
        }
        Button {
            onSaveBaseline()
        } label: {
            Label("Save Baseline…", systemImage: "bookmark")
        }
        .buttonStyle(.bordered)
        .disabled(!library.canEdit)
    }

    private var addPast: some View {
        Button {
            pastBaselineDay = nil
            showsPastBaseline = true
        } label: {
            Label("Add Past Baseline…", systemImage: "clock.arrow.circlepath")
        }
        .buttonStyle(.bordered)
        .disabled(!library.canEdit || session.plan == nil)
    }

    // MARK: More charts

    private var moreCharts: some View {
        DisclosureGroup(isExpanded: $showsMoreCharts) {
            Group {
                if isWide {
                    EqualColumns(spacing: Metrics.l) {
                        answerCard
                        baselineCard
                    }
                } else {
                    VStack(alignment: .leading, spacing: Metrics.l) {
                        answerCard
                        baselineCard
                    }
                }
            }
            .padding(.top, Metrics.s)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("More charts")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text("Your answer at each check-in, and your money against any baseline.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    private var answerCard: some View {
        let history = answerHistory
        return Card {
            Text("Earliest retirement age at each check-in")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            PlanAnswerHistoryChart(history: history)
            if let latest = history.latestAge {
                HStack(spacing: Metrics.s) {
                    Text("\(latest) now")
                        .font(.subheadline.weight(.semibold))
                    if let change = history.change, change.years != 0 {
                        Text(changeText(change.years))
                            .font(.subheadline)
                            .monospacedDigit()
                            // An earlier age is good news.
                            .foregroundStyle(change.years < 0 ? Palette.positive : Palette.negative)
                        Text("since \(PlanResultsText.monthYear(change.since, locale: locale))")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
            if !history.markers.isEmpty {
                HStack(spacing: Metrics.m) {
                    ForEach(PlanAnswerHistory.Change.allCases, id: \.self) { change in
                        if history.markers.contains(where: { $0.changes.contains(change) }) {
                            Label(change.label, systemImage: change.systemImage)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            }
        } header: {
            SectionHeader("Your answer over time")
        }
    }

    /// "ahead of the median" or "behind the median".
    private static func side(of gap: Decimal) -> String {
        gap >= 0 ? "ahead of the median" : "behind the median"
    }

    /// "The same accounts as the baseline, in EUR of 31 Dec 2025."
    private func unitsNote(_ comparison: PlanBaselineComparison) -> String {
        comparison.unitsNote(baseCurrency: library.baseCurrency, locale: locale)
    }

    /// "▼ −3 years".
    private func changeText(_ years: Int) -> String {
        let arrow = years < 0 ? "▼" : "▲"
        let sign = years < 0 ? AmountFormat.minus : "+"
        let count = abs(years)
        return "\(arrow) \(sign)\(count) \(count == 1 ? "year" : "years")"
    }

    private var shownBaseline: PlanBaselineEntry? {
        baselines.first { $0.id == selectedBaseline } ?? baselines.first
    }

    private var baselineCard: some View {
        Card {
            if let shown = shownBaseline {
                let comparison = PlanBaselineComparison(baseline: shown.baseline, library: library.library,
                                                        valuator: library.valuator, asOf: library.asOfDate)
                PlanFanLegend(showsActual: true)
                FanChart(fan: comparison.fan, actual: comparison.actual, currency: comparison.currency)
                if let position = comparison.position {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Metrics.xs) {
                            DeltaText(position.gap, currency: comparison.currency)
                                .font(.subheadline.weight(.semibold))
                            Text(Self.side(of: position.gap))
                                .font(.subheadline)
                        }
                        Text(PlanBaselineComparison.percentileText(position))
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                } else {
                    Text("Your actual numbers appear here after the next check-in.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Text(unitsNote(comparison))
                    .font(.caption)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("A baseline remembers what you expected. Save one now, and later see how reality compares. "
                    + "One is also saved at the first check-in of each year.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeader("Actual vs baseline") {
                if !baselines.isEmpty {
                    // Never nil while there are baselines: a nil selection has no tag.
                    Picker("Baseline", selection: Binding(get: { selectedBaseline ?? baselines.first?.id },
                                                          set: { selectedBaseline = $0 })) {
                        ForEach(baselines) { entry in
                            Text(PlanBaselineComparison.label(for: entry.baseline, locale: locale))
                                .tag(Optional(entry.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }
}

/// A figure with its title above it, beside Progress's headline on the Mac.
struct PlanStatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, Metrics.s)
        .frame(minWidth: 120, maxWidth: 220, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The year cards' key: your money (solid into a check-in, with a dot
/// there), valued from prices (lighter), what you expected (the year's
/// baseline) and your answer. One row on the Mac and iPad, two on iPhone.
struct PlanYearLegend: View {
    var isWide = false

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: Metrics.m) {
                    money
                    prices
                    expected
                    answer
                }
            } else {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    HStack(spacing: Metrics.m) {
                        money
                        prices
                    }
                    HStack(spacing: Metrics.m) {
                        expected
                        answer
                    }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.secondaryInk)
        .accessibilityHidden(true)
    }

    private var money: some View {
        HStack(spacing: 5) {
            ZStack {
                Capsule()
                    .fill(Palette.ink)
                    .frame(width: 16, height: 2)
                Circle()
                    .fill(Palette.ink)
                    .frame(width: 5, height: 5)
            }
            Text("Your money")
        }
    }

    private var prices: some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(Palette.ink.opacity(0.4))
                .frame(width: 16, height: 2)
            Text("Valued from prices")
        }
    }

    private var expected: some View {
        HStack(spacing: 5) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: 16, y: 1))
            }
            .stroke(Palette.secondaryInk, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(width: 16, height: 2)
            Text("What you expected")
        }
    }

    private var answer: some View {
        HStack(spacing: 5) {
            PlanAnswerChip(age: 55, kind: .sooner)
            Text("Your answer")
        }
    }
}

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
/// Choosing a card selects its year, whose story shows below; selecting one
/// elsewhere scrolls it into view.
struct PlanYearStrip: View {
    let timeline: PlanProgressTimeline
    /// The index of the selected card.
    @Binding var selection: Int
    /// Points a month along the time axis.
    var pointsPerMonth: CGFloat = 20
    var cardHeight: CGFloat = 304
    /// The strip's inset at both ends, so its cards line up with the page.
    var inset: CGFloat = Metrics.l

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
        let height = cardHeight + 154 * (textScale - 1)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Metrics.s) {
                    if folds {
                        PlanEarlyYearsCard(cards: Array(timeline.cards.prefix(early)), height: height) {
                            withAnimation(.snappy) { showsEarlyYears = true }
                        }
                    }
                    ForEach(Array(timeline.cards.enumerated()), id: \.element.id) { index, card in
                        if !folds || index >= early {
                            Button {
                                selection = index
                            } label: {
                                PlanYearCardView(card: card, scale: scale, pointsPerMonth: pointsPerMonth,
                                                 height: height, isSelected: selection == index,
                                                 pointerX: pointer?.index == index ? pointer?.x : nil,
                                                 textScale: textScale)
                                    .planGraphPointer($pointer, index: index)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                            .onScrollVisibilityChange(threshold: 0.1) { isVisible in
                                onScreen.set(index, isVisible)
                                if !onScreen.isScrolling { fitScale() }
                            }
                            .accessibilityLabel(Text(accessibilityLabel(card)))
                            .accessibilityAddTraits(selection == index ? .isSelected : [])
                            .accessibilityChartDescriptor(chartSummary(card))
                        }
                    }
                }
                .padding(.horizontal, inset)
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
/// *Show* to lay them out.
struct PlanEarlyYearsCard: View {
    let cards: [PlanProgressTimeline.Card]
    var height: CGFloat = 304
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
                .font(.headline)
                .foregroundStyle(Palette.ink)
            if let moved {
                Text(moved)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
            }
            Text("Before your first answer.")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            if let milestones {
                Label(milestones, systemImage: "flag.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
            Spacer(minLength: 0)
            Button("Show", action: onShow)
                .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(width: 180, height: height, alignment: .topLeading)
        .background(Palette.card, in: shape)
        .overlay { shape.strokeBorder(Palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
    }
}

/// One year on the strip: its change, where it ended against January, your
/// money through it (the line) against what January expected (dashed),
/// green where you're ahead and orange where behind, the months along its
/// bottom and the answer where it moved; the rest of the year still to
/// come shaded.
struct PlanYearCardView: View {
    let card: PlanProgressTimeline.Card
    let scale: PlanProgressTimeline.Scale?
    var pointsPerMonth: CGFloat = 20
    var height: CGFloat = 304
    var isSelected = false
    /// Where the pointer is over the card, or where it was tapped.
    var pointerX: CGFloat?
    /// How much its words have grown with the text size
    /// (``DynamicTypeSize/stripCardScale``).
    var textScale: CGFloat = 1

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    private static let pad: CGFloat = 12
    private static let graphHeight: CGFloat = 150
    /// The header's height, which grows with the text size.
    private var graphTop: CGFloat { 84 * textScale }
    private var plotBottom: CGFloat { graphTop + Self.graphHeight }
    private var width: CGFloat { 12 * pointsPerMonth + 2 * Self.pad }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            amountLabels
            months
            chips
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
                    .font(.subheadline.weight(card.year.isLatest ? .regular : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(card.year.isLatest ? Palette.secondaryInk : Palette.ink)
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
            if let summary = card.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: width - 2 * Self.pad, alignment: .leading)
        .offset(x: Self.pad, y: Self.pad)
    }

    @ViewBuilder
    private var amountLabels: some View {
        if let scale, !hidesAmounts {
            ForEach(scale.ticks.filter { $0 > scale.domain.lowerBound }, id: \.self) { tick in
                Text(verbatim: AmountFormat.compactAmount(tick, currency: card.currency, locale: locale))
                    .font(.caption2)
                    .foregroundStyle(Palette.mutedInk)
                    .offset(x: 6, y: y(tick, scale) - 15)
            }
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
        let solid = StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round)
        for (from, to) in zip(card.actual, card.actual.dropFirst()) {
            var segment = Path()
            segment.move(to: position(of: from, scale))
            segment.addLine(to: position(of: to, scale))
            if !from.isComplete || !to.isComplete {
                context.stroke(segment, with: .color(Palette.ink),
                               style: StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, dash: [0.5, 4]))
            } else if card.checkIns.contains(to.date) {
                context.stroke(segment, with: .color(Palette.ink), style: solid)
            } else {
                context.stroke(segment, with: .color(Palette.ink.opacity(0.4)), style: solid)
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
            let today = x(last.date)
            context.fill(Path(CGRect(x: today, y: graphTop, width: max(0, size.width - today),
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
        drawMoney(in: &context, scale)
        for reached in card.milestones {
            let day = reached.date.dateValue
            guard let point = card.actual.min(by: {
                abs($0.date.timeIntervalSince(day)) < abs($1.date.timeIntervalSince(day))
            }) else { continue }
            let flag = PlanMilestoneFlag.path(at: CGPoint(x: x(point.date), y: y(point.value, scale)))
            context.fill(flag, with: .color(Palette.accent))
            context.stroke(flag, with: .color(Palette.card), lineWidth: 1)
        }
    }
}

// MARK: - A year in words

/// The chosen year (UI.md, "Progress"): its change, where it stands against
/// January, its story, what you saved against what markets did, what
/// happened month by month, and January's note.
struct PlanYearDetails: View {
    let card: PlanProgressTimeline.Card
    let index: Int
    let count: Int
    var isWide = false
    var onSelect: (Int) -> Void = { _ in }
    /// *Add What You Planned in 2021…*, for a year without a baseline: opens
    /// *Add Past Baseline…* at its start.
    var onAddPastBaseline: ((Int) -> Void)?

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale
    @State private var fillsPastPrices = false

    private var year: PlanProgressYear { card.year }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(year.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                if !year.isLatest {
                    Text(PlanProgressText.change(year, currency: card.currency, hidesAmounts: hidesAmounts,
                                                 locale: locale))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                }
                Spacer(minLength: Metrics.s)
                if !isWide && count > 1 {
                    PlanStepButtons(index: index, count: count, select: onSelect)
                }
            }
            if let against = PlanProgressText.againstJanuary(year, hidesAmounts: hidesAmounts, locale: locale) {
                Text(against)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle((year.position?.gap ?? 0) >= 0 ? Palette.positive : Palette.orangeStroke)
            }
            if let summary = card.summary {
                Text(summary)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let story = PlanProgressText.story(year, currency: card.currency, hidesAmounts: hidesAmounts,
                                               locale: locale)
            if !story.isEmpty {
                Text(story)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if year.from != year.to {
                savedAndMarkets
            }
            if !card.notes.isEmpty {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    ForEach(card.notes) { note in
                        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                            Text(note.month)
                                .foregroundStyle(Palette.secondaryInk)
                                .frame(width: 44, alignment: .leading)
                            if note.kind == .milestone {
                                Image(systemName: "flag.fill")
                                    .font(.caption)
                                    .foregroundStyle(Palette.accent)
                                    .accessibilityLabel("Milestone")
                            }
                            Text(note.text)
                                .fontWeight(note.kind == .milestone ? .semibold : .regular)
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.subheadline)
            }
            if year.baseline == nil, let onAddPastBaseline {
                Button("Add What You Planned in \(String(year.year))…") { onAddPastBaseline(year.year) }
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))
            }
            if let january = PlanProgressText.january(year, hidesAmounts: hidesAmounts, locale: locale) {
                Text(january)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let explanation = year.explanation, year.position != nil {
                PlanGapExplanationView(explanation: explanation, year: year,
                                       currency: year.positionCurrency ?? card.currency)
            }
            if !year.isComplete || card.actual.contains(where: { !$0.isComplete }) {
                OldPriceNoteView(text: "Some prices or exchange rates were missing: those holdings count as zero, "
                                     + "and the line is dotted there.",
                                 systemImage: "exclamationmark.triangle") { fillsPastPrices = true }
            }
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: shape)
        .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
        .pastPricesSheet(isPresented: $fillsPastPrices)
    }

    /// What you saved and what markets did: as one bar when both added, and
    /// in figures, with what January planned to save.
    private var savedAndMarkets: some View {
        let saved = max(0, year.change.newMoney.doubleValue)
        let markets = max(0, year.change.market.doubleValue)
        let total = saved + markets
        return VStack(alignment: .leading, spacing: Metrics.xs) {
            if total > 0 {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        Rectangle()
                            .fill(Palette.secondaryInk.opacity(0.45))
                            .frame(width: max(0, proxy.size.width - 2) * CGFloat(saved / total))
                        Rectangle()
                            .fill(Palette.accent)
                            .frame(width: max(0, proxy.size.width - 2) * CGFloat(markets / total))
                    }
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .accessibilityHidden(true)
            }
            HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                Text("Saved")
                    .foregroundStyle(Palette.secondaryInk)
                DeltaText(year.change.newMoney, currency: card.currency, showsArrow: false)
                if let planned = year.expectedSavings {
                    let amount = hidesAmounts ? AmountFormat.hidden
                        : AmountFormat.amount(planned, currency: card.currency, locale: locale)
                    Text("of \(amount) planned")
                        .foregroundStyle(Palette.mutedInk)
                }
                Text("·")
                    .foregroundStyle(Palette.mutedInk)
                Text("Markets")
                    .foregroundStyle(Palette.secondaryInk)
                DeltaText(year.change.market, currency: card.currency, showsArrow: false)
            }
            .font(.subheadline)
        }
    }
}

/// Why the year is ahead of or behind its baseline (PROGRESS.md, *Why*;
/// UI.md, "Progress"): the gap going into the year, against a baseline from
/// before it; what you saved against what it planned; what markets did
/// against what it expected; what inflation took; and the rest. Each in
/// the baseline's money, adding up to the gap.
struct PlanGapExplanationView: View {
    let explanation: GapExplanation
    let year: PlanProgressYear
    let currency: CurrencyCode

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    private struct Row: Identifiable {
        var title: String
        var value: Decimal
        var detail: String?
        var id: String { title }
    }

    private func amount(_ value: Decimal) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(abs(value), currency: currency, locale: locale)
    }

    private func signed(_ value: Decimal) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.signedAmount(value, currency: currency, locale: locale)
    }

    /// "Why you're 3.000 € behind January", "Why you ended 2.100 € ahead of October".
    private var title: String {
        let gap = explanation.end
        let side = gap >= 0 ? "ahead of" : "behind"
        let verb = year.isLatest ? "you're" : "you ended"
        return "Why \(verb) \(amount(gap)) \(side) \(year.expectation(locale: locale))"
    }

    private var rows: [Row] {
        let expectation = year.expectationTitle(locale: locale)
        var rows: [Row] = []
        if abs(explanation.start) >= 1 {
            rows.append(Row(title: "Going into \(year.year)", value: explanation.start))
        }
        let saved = explanation.newMoney >= 0 ? "You saved \(amount(explanation.newMoney))"
            : "You took out \(amount(explanation.newMoney))"
        rows.append(Row(title: "Saving", value: explanation.saving,
                        detail: "\(saved); \(expectation) planned \(amount(explanation.plannedSaving))."))
        let market = explanation.market >= 0 ? "Markets added \(amount(explanation.market))"
            : "Markets took \(amount(explanation.market))"
        let expected = explanation.expectedMarket >= 0 ? "expected them to add \(amount(explanation.expectedMarket))"
            : "expected them to take \(amount(explanation.expectedMarket))"
        rows.append(Row(title: "Markets", value: explanation.markets, detail: "\(market); \(expectation) \(expected)."))
        if let inflation = explanation.inflation {
            rows.append(Row(title: "Inflation", value: inflation,
                            detail: "What rising prices took from what your money is worth."))
        }
        if abs(explanation.other) >= 1 {
            rows.append(Row(title: "Other", value: explanation.other,
                            detail: "Balances that changed without a recorded flow, and exchange rates."))
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                        Text(row.title)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: Metrics.s)
                        Text(signed(row.value))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                            .foregroundStyle(row.value >= 0 ? Palette.positive : Palette.orangeStroke)
                    }
                    .font(.subheadline)
                    if let detail = row.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
    }
}

#Preview("Progress") {
    PlanPreviewHost(model: AppModel.preview(planEngine: PlanPreviewEngine())) { session in
        PlanProgressView(session: session, onSaveBaseline: {}, onShowPlan: {})
    }
}

#Preview("Progress · Mac") {
    PlanPreviewHost(model: AppModel.preview(planEngine: PlanPreviewEngine())) { session in
        PlanProgressView(session: session, isWide: true, onSaveBaseline: {}, onShowPlan: {})
            .frame(width: 1_100, height: 1_000)
    }
}
