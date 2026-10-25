import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The Timeline at a year (UI.md, "Year"; PROGRESS.md): the chosen year's
/// chart on a card, your money against what you planned in January, with
/// ‹ › to step through the years and its verdict in a line; then tiles for
/// what you saved and what markets did, why you're ahead or behind, your
/// money, the earliest age and the check-ins; then the year month by
/// month, what happened, and the milestones. The same at every width, the
/// tiles on the grid of slots. Your date at each check-in is on *Look
/// back*.
struct PlanProgressView: View {
    let session: PlanSession
    /// Shows the plan.
    let onShowPlan: () -> Void
    /// A year to open, asked for elsewhere (Today's *Your year* note); taken
    /// once, then cleared.
    var openingYear: Binding<Int?> = .constant(nil)

    @Environment(LibraryStore.self) private var library
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    /// The year chosen; the latest when `nil`.
    @State private var selectedYear: Int?

    private var isWide: Bool { layout.isWide }

    private var milestoneText: PlanMilestoneText {
        PlanMilestoneText(currency: library.baseCurrency, locale: locale)
    }

    var body: some View {
        let progress = session.progress
        let timeline = PlanProgressTimeline(progress, text: milestoneText)
        let milestones = session.baseDerived(locale: locale).milestones
        ScrollView {
            content(timeline, history: progress.history, milestones: milestones)
                .padding(layout.gutter)
                .frame(maxWidth: isWide ? Metrics.wideReadableWidth : Metrics.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
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

    @ViewBuilder
    private func content(_ timeline: PlanProgressTimeline, history: PlanAnswerHistory,
                         milestones: PlanMilestones?) -> some View {
        let cards = timeline.cards
        if cards.isEmpty {
            Card {
                Text("Your year shows here from your first check-in.")
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            let index = selectedYear.flatMap { year in cards.firstIndex { $0.year.year == year } } ?? cards.count - 1
            let card = cards[index]
            let select: (Int) -> Void = { target in
                if cards.indices.contains(target) { selectedYear = cards[target].year.year }
            }
            VStack(alignment: .leading, spacing: Metrics.m) {
                PlanYearChartCard(timeline: timeline, index: index, select: select)
                PlanYearTiles(card: card, history: history)
                PlanYearMonthsCard(card: card)
                happenings(card)
                milestonesCard(milestones)
            }
        }
    }

    /// "What happened", over its card.
    private func happenings(_ card: PlanProgressTimeline.Card) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            SectionHeader("What happened")
                .padding(.horizontal, Metrics.xs)
            PlanYearHappenings(card: card)
        }
    }

    @ViewBuilder
    private func milestonesCard(_ milestones: PlanMilestones?) -> some View {
        if let milestones {
            PlanProgressMilestones(milestones: milestones, text: milestoneText, asOf: library.asOfDate,
                                   planName: session.plan?.name ?? "", hasResults: session.baseResults != nil)
        }
    }
}

/// Text in the year's words and Look Back's cards: 15 points on iPhone and
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

#Preview("Year") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanProgressView(session: session, onShowPlan: {})
            .environment(\.pageLayout, PageLayout())
    }
}

#Preview("Year · Mac") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanProgressView(session: session, onShowPlan: {})
            .environment(\.pageLayout, PageLayout(isWide: true))
            .frame(width: 1_100, height: 1_000)
    }
}
