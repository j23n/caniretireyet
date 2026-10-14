import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// Progress (UI.md, "Progress"; PROGRESS.md): whether you're on track; year
/// by year on a strip that opens at today, each year's card with your money
/// against what January expected, where the answer moved and the
/// milestones reached; the year's words (under the strip on iPhone, in
/// each card on the Mac and iPad); the milestones and what's next in the
/// plan (beside the strip on the Mac and iPad); and, folded away, your
/// money against any baseline. The answer at each check-in is on Trends.
struct PlanProgressView: View {
    let session: PlanSession
    var isWide = false
    /// Asks for a label and saves a baseline (the screen owns the alert).
    let onSaveBaseline: () -> Void
    /// Shows the plan.
    let onShowPlan: () -> Void
    /// A year to open on the strip, asked for elsewhere (a row of Trends'
    /// *Year by year*); taken once, then cleared.
    var openingYear: Binding<Int?> = .constant(nil)

    @Environment(LibraryStore.self) private var library
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.hidesPersonalData) private var hidesPersonalData
    @Environment(\.locale) private var locale
    @State private var selectedBaseline: BaselineID?
    /// The year chosen on the strip; the latest when `nil`.
    @State private var selectedYear: Int?
    @State private var showsMoreCharts = false
    @State private var showsPastBaseline = false
    /// The day *Add Past Baseline…* starts on, when a year asked for it.
    @State private var pastBaselineDay: CalendarDate?
    /// The baseline *Delete Baseline…* asks about.
    @State private var deletingBaseline: PlanBaselineEntry?
    @State private var confirmsBaselineDelete = false

    private var gutter: CGFloat { isWide ? Metrics.xl : Metrics.l }

    /// The column beside the strip on the Mac and iPad: the milestones and what's next.
    private static let sideWidth: CGFloat = 300

    private var baselines: [PlanBaselineEntry] {
        PlanBaselineComparison.baselines(for: session.planID, in: library.library)
    }

    private var milestoneText: PlanMilestoneText {
        PlanMilestoneText(currency: library.baseCurrency, locale: locale)
    }

    var body: some View {
        let progress = session.progress
        let timeline = PlanProgressTimeline(progress, text: milestoneText)
        let milestones = session.plan.map {
            PlanMilestones(plan: $0, library: library.library, valuator: library.valuator, asOf: library.asOfDate,
                           results: session.shownResults, reached: progress.reached)
        }
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                headline(progress.latestYear, history: progress.history)
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
            if let year = openingYear.wrappedValue {
                selectedYear = year
                openingYear.wrappedValue = nil
            }
        }
        .sheet(isPresented: $showsPastBaseline) {
            if let plan = session.plan {
                PlanPastBaselineSheet(session: session, plan: plan, startingOn: pastBaselineDay)
            }
        }
        .confirmationDialog(deletionTitle, isPresented: $confirmsBaselineDelete, titleVisibility: .visible,
                            presenting: deletingBaseline) { entry in
            Button("Delete Baseline", role: .destructive) { delete(entry) }
        } message: { entry in
            Text(verbatim: PlanProgressYear.deletionNote(
                of: entry, years: timeline.cards.map(\.year.year), baselines: baselines,
                savingYear: library.settings.mainPlan == session.planID
                    ? CheckInDraft.suggestedDate(today: .today(), lastCheckIn: library.latestCheckIn).year : nil,
                locale: locale))
        }
    }

    /// "Delete “Start of 2026 (automatic)”?"
    private var deletionTitle: String {
        guard let entry = deletingBaseline else { return "Delete this baseline?" }
        return "Delete “\(PlanBaselineComparison.label(for: entry.baseline, locale: locale))”?"
    }

    /// Deletes a baseline; the picker then shows the newest left.
    private func delete(_ entry: PlanBaselineEntry) {
        Task {
            do {
                try await library.deleteBaseline(entry.id, of: session.planID)
                if selectedBaseline == entry.id { selectedBaseline = nil }
            } catch {
                library.reportError("The baseline couldn't be deleted. \(LibraryStore.describe(error))")
            }
        }
    }

    // MARK: Are you on track?

    @ViewBuilder
    private func headline(_ latest: PlanProgressYear?, history: PlanAnswerHistory) -> some View {
        let position = latest?.position
        let title = PlanProgressText.headline(position)
        let detail = PlanProgressText.headlineDetail(latest, currency: library.baseCurrency, locale: locale)
        let tiles = self.tiles(history)
        let month = monthReport
        if isWide {
            // The tiles beside the words when there's room for both, else under them.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: Metrics.l) {
                    wideWords(title: title, detail: detail)
                        .frame(width: 380, alignment: .leading)
                    Spacer(minLength: 0)
                    tileRow(tiles, month: month)
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: Metrics.m) {
                    wideWords(title: title, detail: detail)
                        .frame(maxWidth: 560, alignment: .leading)
                    tileRow(tiles, month: month)
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
                        .privacySensitiveInFeedback()
                        .accessibilityAddTraits(.isHeader)
                }
                AmountSentenceText(detail)
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
                    let hides = redactionReasons.hidesAmounts
                    let title = Text(sentence: "\(month.title):", hidesWords: hidesPersonalData)
                        .foregroundStyle(Palette.secondaryInk)
                    let sentence = Text(sentence: month.sentence, hidesAmounts: hides, hidesWords: hidesPersonalData)
                    Divider()
                    Text("\(title) \(sentence)")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .textRenderer(AmountPlaceholderRenderer(hidesAmounts: hides, hidesWords: hidesPersonalData))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(Text(verbatim: "\(month.title): \(month.sentence.spoken(hidesAmounts: hides))"))
                }
            }
        }
    }

    /// The answer in words on the Mac and iPad.
    private func wideWords(title: String, detail: AmountSentence) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(title)
                .font(Self.wideTitleFont)
                .foregroundStyle(Palette.ink)
                .privacySensitiveInFeedback()
                .accessibilityAddTraits(.isHeader)
            AmountSentenceText(detail)
                .font(PlanProgressFont.text)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The figures as tiles on the Mac and iPad: to go, since January, and the month.
    private func tileRow(_ tiles: [Tile], month: MonthReport?) -> some View {
        HStack(alignment: .top, spacing: Metrics.s) {
            ForEach(tiles) { tile in
                PlanStatTile(title: tile.title, value: AmountSentence(tile.value))
            }
            if let month {
                PlanStatTile(title: month.title, value: month.figures)
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

    /// "To go · 15½ years", "Since Jan 2024 · 3 years sooner". To go is
    /// from the plan's latest answer (``PlanSession/latestAnswer``): its
    /// results, else the answer recorded at the latest check-in.
    private func tiles(_ answerHistory: PlanAnswerHistory) -> [Tile] {
        var tiles: [Tile] = []
        if let answer = session.latestAnswer?.answer {
            if answer.canRetireNow {
                tiles.append(Tile(title: "To go", value: "None: you could stop"))
            } else if let date = answer.earliestDate {
                let months = library.asOfDate.yearMonth.months(to: date.yearMonth)
                if months > 0 { tiles.append(Tile(title: "To go", value: Self.duration(months: months))) }
            }
        }
        if let change = answerHistory.change {
            let value = change.years == 0 ? "No change" : PlanProgressText.move(years: change.years).capitalizedFirst
            tiles.append(Tile(title: "Since \(GlanceText.shortMonthAndYear(change.since, locale: locale))",
                              value: value))
        }
        return tiles
    }

    /// The latest check-in's month: what you saved and what markets did.
    private struct MonthReport {
        /// "September".
        var title: String
        /// "Saved 1.532 € · markets +3.236 €", on the Mac's tile.
        var figures: AmountSentence
        /// "you saved 1.532 € and markets added 3.236 €.", in the card on iPhone.
        var sentence: AmountSentence
    }

    private var monthReport: MonthReport? {
        guard let report = library.valuator.changeSinceLastCheckIn(asOf: library.asOfDate, in: .planAssets) else {
            return nil
        }
        let saved = report.total.newMoney
        let markets = report.total.market
        func amount(_ value: Decimal) -> AmountSentence {
            .amount(AmountFormat.amount(abs(value), currency: report.currency, locale: locale))
        }
        let signedMarkets = AmountSentence.amount(
            AmountFormat.signedAmount(markets, currency: report.currency, locale: locale))
        let savedWords: AmountSentence = saved >= 0 ? "you saved \(amount(saved))" : "you took out \(amount(saved))"
        let marketWords: AmountSentence = markets >= 0 ? "markets added \(amount(markets))"
            : "markets took \(amount(markets))"
        let figures: AmountSentence = "\(saved >= 0 ? "Saved" : "Took out") \(amount(saved)) · markets \(signedMarkets)"
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
            let hint = isWide ? "Scroll back, or use the arrows." : "Scroll back through the years; tap one."
            PlanStripHeader(
                title: "Year by year", hint: cards.count > 1 ? hint : nil,
                steps: isWide && cards.count > 1
                    ? PlanStepButtons(index: selected, count: cards.count, today: cards.count - 1,
                                      select: { selection.wrappedValue = $0 })
                    : nil)
                .padding(.leading, gutter)
                .padding(.trailing, isWide ? 0 : gutter)
            // An inset at both ends, beside the milestones too: on the Mac
            // the strip opened with today's card a scroller's width (16
            // points) past its trailing edge without one.
            PlanYearStrip(timeline: timeline, selection: selection, pointsPerMonth: isWide ? 26 : 21,
                          inset: gutter, showsFooter: isWide,
                          today: library.asOfDate)
            PlanYearDetails(card: cards[selected], index: selected, count: cards.count, isWide: isWide,
                            onSelect: { selection.wrappedValue = $0 }, onAddPastBaseline: addPastBaseline)
                .padding(.leading, gutter)
                .padding(.trailing, isWide ? 0 : gutter)
        }
    }

    /// *Add What You Planned in 2021…*: *Add Past Baseline…* on the year's
    /// first day; `nil` when the library or the plan can't take one.
    private var addPastBaseline: ((Int) -> Void)? {
        guard library.canEdit, session.plan != nil else { return nil }
        return { year in
            pastBaselineDay = CalendarDate.firstDay(ofYear: year)
            showsPastBaseline = true
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
                        .privacySensitiveInFeedback()
                    Spacer(minLength: Metrics.s)
                    Button("Open", action: onShowPlan)
                        .buttonStyle(.borderless)
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

    /// *Actual vs baseline*, folded away; the answer at each check-in is on Trends.
    private var moreCharts: some View {
        DisclosureGroup(isExpanded: $showsMoreCharts) {
            baselineCard
                .frame(maxWidth: isWide ? Metrics.readableWidth : .infinity, alignment: .leading)
                .padding(.top, Metrics.s)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("More charts")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text("Your money against any baseline.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    /// "ahead of the median" or "behind the median".
    private static func side(of gap: Decimal) -> String {
        gap >= 0 ? "ahead of the median" : "behind the median"
    }

    private var shownBaseline: PlanBaselineEntry? {
        baselines.first { $0.id == selectedBaseline } ?? baselines.first
    }

    private var baselineCard: some View {
        Card {
            if let shown = shownBaseline {
                let comparison = PlanBaselineComparison(baseline: shown.baseline, library: library.library,
                                                        valuator: library.valuator, asOf: library.asOfDate)
                ProjectionLegend()
                FanChart(fan: comparison.fan, actual: comparison.actual, currency: library.baseCurrency)
                if let position = comparison.position {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Metrics.xs) {
                            DeltaText(position.gap, currency: library.baseCurrency)
                                .font(.subheadline.weight(.semibold))
                            Text(Self.side(of: position.gap))
                                .font(.subheadline)
                                .privacySensitiveInFeedback()
                        }
                        Text(PlanBaselineComparison.percentileText(position))
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                            .privacySensitiveInFeedback()
                    }
                } else {
                    Text("Your actual numbers appear here after the next check-in.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Text(comparison.unitsNote(baseCurrency: library.baseCurrency, locale: locale))
                    .font(.caption)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
                Button(role: .destructive) {
                    deletingBaseline = shown
                    confirmsBaselineDelete = true
                } label: {
                    Label("Delete Baseline…", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .font(PlanProgressFont.caption)
                .disabled(!library.canEdit)
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
                    // Never nil while there are baselines, nor a deleted one's: those have no tag.
                    Picker("Baseline", selection: Binding(get: { shownBaseline?.id },
                                                          set: { selectedBaseline = $0 })) {
                        ForEach(baselines) { entry in
                            Text(PlanBaselineComparison.label(for: entry.baseline, locale: locale))
                                .tag(Optional(entry.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .personalControl()
                }
            }
        }
    }
}

/// A figure with its title above it, beside Progress's headline on the Mac.
struct PlanStatTile: View {
    let title: String
    /// The figure: its amounts hide with the eye.
    let value: AmountSentence

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
            AmountSentenceText(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, Metrics.s)
        .frame(minWidth: 110, alignment: .leading)
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
                .privacySensitiveInFeedback()
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
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
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanProgressView(session: session, onSaveBaseline: {}, onShowPlan: {})
    }
}

#Preview("Progress · Mac") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanProgressView(session: session, isWide: true, onSaveBaseline: {}, onShowPlan: {})
            .frame(width: 1_100, height: 1_000)
    }
}
