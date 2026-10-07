import Model
import Planner
import SwiftUI
import Tracker

/// Progress (UI.md, "Progress"; PROGRESS.md): whether you're on track; year
/// by year on a strip that opens at today, each year's card with your money
/// against what January expected, where the answer moved and the
/// milestones reached; the year's words (under the strip on iPhone, in
/// each card on the Mac and iPad); the milestones and what's next in the
/// plan (beside the strip on the Mac and iPad); and, folded away, the
/// answer over time and your money against any baseline.
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

    /// The column beside the strip on the Mac and iPad: the milestones and what's next.
    private static let sideWidth: CGFloat = 300

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
                if isWide {
                    HStack(alignment: .top, spacing: Metrics.l) {
                        VStack(alignment: .leading, spacing: Metrics.m) {
                            yearByYear(timeline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: Metrics.l) {
                            milestonesCard(milestones)
                            footer
                        }
                        .frame(width: Self.sideWidth)
                        .padding(.trailing, gutter)
                    }
                } else {
                    yearByYear(timeline)
                    milestonesCard(milestones)
                        .padding(.horizontal, gutter)
                    footer
                        .padding(.horizontal, gutter)
                }
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
        let tiles = self.tiles
        let month = monthReport
        if isWide {
            HStack(alignment: .top, spacing: Metrics.l) {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text(title)
                        .font(Self.wideTitleFont)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(detail)
                        .font(PlanProgressFont.text)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 460, alignment: .leading)
                Spacer(minLength: Metrics.l)
                HStack(alignment: .top, spacing: Metrics.s) {
                    ForEach(tiles) { tile in
                        PlanStatTile(title: tile.title, value: tile.value)
                    }
                    if let month {
                        PlanStatTile(title: month.title, value: month.figures)
                    }
                }
                // The words beside them give way first.
                .layoutPriority(1)
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
                if !tiles.isEmpty {
                    EqualColumns(spacing: Metrics.s) {
                        ForEach(tiles) { tile in
                            PlanFigureTile(title: tile.title, value: tile.value)
                        }
                    }
                }
                if let month {
                    Divider()
                    Text("\(Text("\(month.title):").foregroundStyle(Palette.secondaryInk)) \(month.sentence)")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The answer's title beside its figures: 22 points on the Mac.
    private static var wideTitleFont: Font {
        #if os(macOS)
        Font.title.weight(.bold)
        #else
        Font.title2.weight(.bold)
        #endif
    }

    /// A figure beside the headline on the Mac, and in its card on iPhone.
    private struct Tile: Hashable, Identifiable {
        var title: String
        var value: String
        var id: String { title }
    }

    /// "To go · 15½ years", "Since Jan 2024 · 3 years sooner".
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
        return tiles
    }

    /// The latest check-in's month: what you saved and what markets did.
    private struct MonthReport {
        /// "September".
        var title: String
        /// "Saved 1.532 € · markets +3.236 €", on the Mac's tile.
        var figures: String
        /// "you saved 1.532 € and markets added 3.236 €.", in the card on iPhone.
        var sentence: String
    }

    private var monthReport: MonthReport? {
        guard let report = library.valuator.changeSinceLastCheckIn(asOf: library.asOfDate, in: .planAssets) else {
            return nil
        }
        let saved = report.total.newMoney
        let markets = report.total.market
        func amount(_ value: Decimal) -> String {
            hidesAmounts ? AmountFormat.hidden
                : AmountFormat.amount(abs(value), currency: report.currency, locale: locale)
        }
        let signedMarkets = hidesAmounts ? AmountFormat.hidden
            : AmountFormat.signedAmount(markets, currency: report.currency, locale: locale)
        let savedWords = saved >= 0 ? "you saved \(amount(saved))" : "you took out \(amount(saved))"
        let marketWords = markets >= 0 ? "markets added \(amount(markets))" : "markets took \(amount(markets))"
        let figures = (saved >= 0 ? "Saved " : "Took out ") + amount(saved) + " · markets " + signedMarkets
        return MonthReport(title: AmountFormat.monthName(report.to, locale: locale), figures: figures,
                           sentence: "\(savedWords) and \(marketWords).")
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
            .padding(.leading, gutter)
            .padding(.trailing, isWide ? 0 : gutter)
        } else {
            let selected = selectedYear.flatMap { year in cards.firstIndex { $0.year.year == year } }
                ?? cards.count - 1
            let selection = Binding<Int>(
                get: { selected },
                set: { index in if cards.indices.contains(index) { selectedYear = cards[index].year.year } })
            yearsHeader(count: cards.count, selection: selection)
                .padding(.leading, gutter)
                .padding(.trailing, isWide ? 0 : gutter)
            PlanYearStrip(timeline: timeline, selection: selection, pointsPerMonth: isWide ? 26 : 21,
                          leadingInset: gutter, trailingInset: isWide ? 0 : gutter, showsWords: isWide,
                          today: library.asOfDate, onAddPastBaseline: addPastBaseline)
            if !isWide {
                PlanYearDetails(card: cards[selected], index: selected, count: cards.count,
                                onSelect: { selection.wrappedValue = $0 }, onAddPastBaseline: addPastBaseline)
                    .padding(.horizontal, gutter)
            }
        }
    }

    /// *Add What You Planned in 2021…*: *Add Past Baseline…* on the year's
    /// first day; `nil` when the library or the plan can't take one.
    private var addPastBaseline: ((Int) -> Void)? {
        guard library.canEdit, session.plan != nil else { return nil }
        return { year in
            pastBaselineDay = CalendarDate(year: year, month: 1, day: 1)
            showsPastBaseline = true
        }
    }

    private func yearsHeader(count: Int, selection: Binding<Int>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Year by year")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                if count > 1 {
                    Text(isWide ? "Scroll back, or use the arrows." : "Scroll back through the years; tap one.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: Metrics.s)
            if isWide && count > 1 {
                PlanStepButtons(index: selection.wrappedValue, count: count, today: count - 1) {
                    selection.wrappedValue = $0
                }
            }
        }
    }

    // MARK: Milestones and what's next

    @ViewBuilder
    private func milestonesCard(_ milestones: PlanMilestones?) -> some View {
        if let milestones {
            PlanProgressMilestones(milestones: milestones, text: milestoneText, asOf: library.asOfDate,
                                   hasResults: session.shownResults != nil)
        }
    }

    /// The next chapter of the plan, and *Save Baseline…*; *Add a Past
    /// Baseline…* quietly under it.
    private var footer: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: Metrics.s) {
            if let model = session.chapters, model.chapters.chapters.count > 1 {
                let next = model.chapters.chapters[1]
                Text("Next in your plan")
                    .font(PlanProgressFont.caption)
                    .foregroundStyle(Palette.secondaryInk)
                HStack(alignment: .center, spacing: Metrics.s) {
                    PlanChapterBadge(number: 2, style: model.style(of: next))
                    Text("\(model.title(of: next)), from \(next.ages.lowerBound) in \(String(next.years.lowerBound))")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Metrics.s)
                    if let onShowPlan {
                        Button("Open", action: onShowPlan)
                            .buttonStyle(.borderless)
                    }
                }
                .font(PlanProgressFont.text)
            }
            Button {
                onSaveBaseline()
            } label: {
                Label("Save Baseline…", systemImage: "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(isWide ? .regular : .large)
            .disabled(!library.canEdit)
            Text("Freeze what you expect now, to measure against it later.")
                .font(PlanProgressFont.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add a Past Baseline…") {
                pastBaselineDay = nil
                showsPastBaseline = true
            }
            .buttonStyle(.borderless)
            .font(PlanProgressFont.caption)
            .disabled(!library.canEdit || session.plan == nil)
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: shape)
        .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
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
        .frame(minWidth: 110, maxWidth: 300, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A figure in Progress's answer card on iPhone: its title, then the figure, large.
struct PlanFigureTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.page, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Text in Progress's cards and the year's words: 15 points on iPhone and
/// iPad, 13 on the Mac; captions 13 and 11.
enum PlanProgressFont {
    static var text: Font {
        #if os(macOS)
        Font.body
        #else
        Font.subheadline
        #endif
    }

    static var caption: Font {
        #if os(macOS)
        Font.subheadline
        #else
        Font.footnote
        #endif
    }

    /// The year in a line, above its words.
    static var summary: Font {
        #if os(macOS)
        Font.title3.weight(.semibold)
        #else
        Font.headline
        #endif
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
