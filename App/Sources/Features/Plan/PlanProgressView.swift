import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The Timeline at a year (UI.md, "Timeline"; PROGRESS.md): whether you're
/// on track; year by year on a strip that opens at today, each year's card
/// with your money against what you planned in January, where your date
/// moved and the milestones reached; the year's words (under the strip on
/// iPhone, in each card on the Mac and iPad); and the milestones and what's
/// next in the plan (beside the strip on the Mac and iPad). Your date at
/// each check-in is on *Look back*.
struct PlanProgressView: View {
    let session: PlanSession
    /// Shows the plan.
    let onShowPlan: () -> Void
    /// A year to open on the strip, asked for elsewhere (a row of Trends'
    /// *Year by year*); taken once, then cleared.
    var openingYear: Binding<Int?> = .constant(nil)

    @Environment(LibraryStore.self) private var library
    @Environment(\.pageLayout) private var layout
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.hidesPersonalData) private var hidesPersonalData
    @Environment(\.locale) private var locale
    /// The year chosen on the strip; the latest when `nil`.
    @State private var selectedYear: Int?

    private var isWide: Bool { layout.isWide }

    private var gutter: CGFloat { layout.gutter }

    /// The column beside the strip on the Mac and iPad: the milestones and what's next.
    private static let sideWidth: CGFloat = 300

    private var milestoneText: PlanMilestoneText {
        PlanMilestoneText(currency: library.baseCurrency, locale: locale)
    }

    var body: some View {
        let progress = session.progress
        let timeline = PlanProgressTimeline(progress, text: milestoneText)
        let derived = session.baseDerived(locale: locale)
        let milestones = derived.milestones
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
                            footer(derived.chapters)
                        }
                        .frame(width: Self.sideWidth)
                        .padding(.trailing, gutter)
                    }
                } else {
                    yearByYear(timeline)
                    milestonesCard(milestones)
                        .padding(.horizontal, gutter)
                    footer(derived.chapters)
                        .padding(.horizontal, gutter)
                }
            }
            .padding(.vertical, gutter)
        }
        .background(Palette.page)
        .onAppear {
            if let year = openingYear.wrappedValue {
                selectedYear = year
                openingYear.wrappedValue = nil
            }
        }
        .onChange(of: openingYear.wrappedValue) { _, year in
            guard let year else { return }
            selectedYear = year
            openingYear.wrappedValue = nil
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
                            FigureTile {
                                Text(tile.title)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.secondaryInk)
                                    .privacySensitiveInFeedback()
                                Text(tile.value)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(Palette.ink)
                                    .minimumScaleFactor(0.8)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .privacySensitiveInFeedback()
                            }
                            .accessibilityElement(children: .combine)
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
                statTile(tile.title, AmountSentence(tile.value))
            }
            if let month {
                statTile(month.title, month.figures)
            }
        }
    }

    /// A figure with its title above it, beside the answer's words; its
    /// amounts hide with the eye.
    private func statTile(_ title: String, _ value: AmountSentence) -> some View {
        FigureTile(surface: .raised, fills: false) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
            AmountSentenceText(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
        let saved = report.total.saved
        let markets = report.total.market
        let words = PlanWords(currency: report.currency, locale: locale)
        let took = saved >= 0 ? "Saved" : "Took out"
        let figures: AmountSentence = "\(took) \(words.amount(abs(saved))) · markets \(words.signedAmount(markets))"
        return MonthReport(title: AmountFormat.monthName(report.to, locale: locale), figures: figures,
                           sentence: words.savedAndMarkets(saved: saved, markets: markets))
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
            PlanYearStrip(timeline: timeline, selection: selection, today: library.asOfDate)
            PlanYearDetails(card: cards[selected], index: selected, count: cards.count,
                            onSelect: { selection.wrappedValue = $0 }, onAddPastBaseline: nil)
                .padding(.leading, gutter)
                .padding(.trailing, isWide ? 0 : gutter)
        }
    }

    // MARK: Milestones and what's next

    @ViewBuilder
    private func milestonesCard(_ milestones: PlanMilestones?) -> some View {
        if let milestones {
            PlanProgressMilestones(milestones: milestones, text: milestoneText, asOf: library.asOfDate,
                                   hasResults: session.baseResults != nil)
        }
    }

    /// The next chapter of the plan, when there is one.
    @ViewBuilder
    private func footer(_ chapters: PlanChaptersModel?) -> some View {
        if let model = chapters, model.chapters.chapters.count > 1 {
            let next = model.chapters.chapters[1]
            let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
            VStack(alignment: .leading, spacing: Metrics.s) {
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
            .padding(Metrics.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: shape)
            .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
        }
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
        PlanProgressView(session: session, onShowPlan: {})
            .environment(\.pageLayout, PageLayout())
    }
}

#Preview("Progress · Mac") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanProgressView(session: session, onShowPlan: {})
            .environment(\.pageLayout, PageLayout(isWide: true))
            .frame(width: 1_100, height: 1_000)
    }
}
