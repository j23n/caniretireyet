import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// So far (UI.md, "So far"): how you've been doing, from your own records,
/// always against the main plan. One page: the chosen year's chart against
/// what you planned in January, with ‹ › to step through the years, and its
/// tiles; the last 12 months' savings rate and spending; what happened in
/// the year; your savings rate and your money in and out by month, over the
/// accounts' time span; year by year; your last Monday at each check-in;
/// the milestones; and where this leads, which opens Ahead.
struct SoFarScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans

    init() {}

    /// The main plan, else the first.
    private var plan: PlanDocument? {
        library.mainPlan ?? library.sortedPlans.first
    }

    var body: some View {
        Group {
            if let plan, !library.hasNoAccounts {
                SoFarContentView(planID: plan.id, library: library, plans: plans)
                    .id(plan.id)
            } else {
                ContentUnavailableView {
                    Label("Nothing to show yet", systemImage: AppSymbol.soFar)
                } description: {
                    Text(library.hasNoAccounts
                         ? "So far starts with your first values. Import a file to add them."
                         : "So far follows your main plan. Create one on Ahead.")
                }
                .background(Palette.page)
            }
        }
        .navigationTitle("So far")
    }
}

/// So far for one plan: its session, the page, and on iPhone the large
/// title drawn on the page, as Ahead draws its own.
private struct SoFarContentView: View {
    let planID: PlanID

    @Environment(LibraryStore.self) private var library
    @Environment(\.pageLayout) private var layout
    @State private var session: PlanSession

    init(planID: PlanID, library: LibraryStore, plans: PlanStore) {
        self.planID = planID
        _session = State(initialValue: PlanSession(planID: planID, library: library, plans: plans))
    }

    var body: some View {
        SoFarView(session: session)
            #if os(iOS)
            .toolbar(layout.isWide ? .automatic : .hidden, for: .navigationBar)
            #endif
            .task(id: library.revision) {
                await session.refresh()
            }
            .onDisappear { session.saveNow() }
    }
}

/// So far's page (UI.md, "So far").
struct SoFarView: View {
    let session: PlanSession

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @AppStorage("overview.range") private var range: HistoryRange = .threeYears
    /// The year chosen; the latest when `nil`.
    @State private var selectedYear: Int?

    private var isWide: Bool { layout.isWide }

    private var isMainPlan: Bool { library.settings.mainPlan == session.planID }

    private var milestoneText: PlanMilestoneText {
        PlanMilestoneText(currency: library.baseCurrency, locale: locale)
    }

    /// The year's card, which a year in *Year by year* scrolls back to.
    private static let yearCard = "year"

    var body: some View {
        let progress = session.progress
        let timeline = PlanProgressTimeline(progress, text: milestoneText)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    if !isWide {
                        Text("So far")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.horizontal, Metrics.xs)
                            .padding(.top, Metrics.s)
                    }
                    content(timeline, history: progress.history) { year in
                        selectedYear = year
                        withAnimation(.snappy) { proxy.scrollTo(Self.yearCard, anchor: .top) }
                    }
                }
                .padding(.horizontal, layout.gutter)
                .padding(.vertical, isWide ? layout.gutter : Metrics.s)
                .frame(maxWidth: isWide ? Metrics.wideReadableWidth : Metrics.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Palette.page)
        .toolbar {
            if isWide, library.library.accountsTurningOffTrends.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    TimeSpanMenu(range: $range, horizon: nil, choices: [])
                        .fixedSize()
                }
            }
        }
        .onChange(of: navigation.soFarYear, initial: true) { _, year in
            guard let year else { return }
            selectedYear = year
            navigation.soFarYear = nil
        }
    }

    @ViewBuilder
    private func content(_ timeline: PlanProgressTimeline, history: PlanAnswerHistory,
                         selectYear: @escaping (Int) -> Void) -> some View {
        let cards = timeline.cards
        let typedAccounts = library.library.accountsTurningOffTrends
        let monthly = session.trends(grain: .months, lastYears: range.years)
        let reference = moneyReference(on: monthly.money.end)
        if cards.isEmpty {
            Card {
                Text("Your year shows here from your first check-in.")
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            let index = selectedYear.flatMap { year in cards.firstIndex { $0.year.year == year } } ?? cards.count - 1
            let card = cards[index]
            PlanYearChartCard(timeline: timeline, index: index) { target in
                if cards.indices.contains(target) { selectedYear = cards[target].year.year }
            }
            .id(Self.yearCard)
            PlanYearTiles(card: card, history: history)
            if typedAccounts.isEmpty, !monthly.money.isEmpty {
                PlanLastTwelveMonthsTiles(year: monthly.lastTwelveMonths,
                                          plannedSpending: reference.spendingWhileWorking,
                                          kinds: [.savingsRate, .spent])
            }
            VStack(alignment: .leading, spacing: Metrics.s) {
                SectionHeader("What happened")
                    .padding(.horizontal, Metrics.xs)
                PlanYearHappenings(card: card)
            }
        }
        if !typedAccounts.isEmpty {
            PlanTrendsOffCard(accounts: typedAccounts)
        } else if monthly.money.isEmpty {
            PlanMoneyInOutEmptyCard()
        } else {
            savingsRateCard(monthly.money, planRate: reference.savingsRate)
            moneyCard(monthly.money, planSpending: reference.spending(per: monthly.money.grain))
            yearByYear(years: Set(cards.map(\.year.year)), select: selectYear)
        }
        answerCard(history)
        if let milestones = session.baseDerived(locale: locale).milestones {
            PlanProgressMilestones(milestones: milestones, text: milestoneText, asOf: library.asOfDate,
                                   planName: session.plan?.name ?? "", hasResults: session.baseResults != nil)
        }
        whereThisLeads
    }

    /// The plan's references for money in and out on the latest check-in:
    /// its spending while working and its own savings rate. From the plan
    /// as shown, so an edit moves them at once.
    private func moneyReference(on date: CalendarDate) -> PlanMoneyReference {
        PlanMoneyReference(plan: session.plan, on: date,
                           earliestAge: library.library.headlines(for: session.planID).last?.earliestAge,
                           birthDate: library.settings.person?.birthDate)
    }

    // MARK: Savings rate, Money in and out

    /// "Savings rate by month", with the accounts' time span on iPhone (in
    /// the toolbar on the Mac and iPad).
    private func savingsRateCard(_ money: PlanMoneyInOut, planRate: Decimal?) -> some View {
        Card {
            if money.counted.isEmpty {
                notYet("No money in and out was recorded in this time span.")
            } else {
                PlanSavingsRateLegend(money: money, planRate: planRate,
                                      cuts: money.cutsRates(planRate: planRate))
                PlanSavingsRateChart(money: money, planRate: planRate)
            }
            whereItStarts(money)
        } header: {
            SectionHeader("Savings rate by month") {
                if !isWide {
                    TimeSpanMenu(range: $range, horizon: nil, choices: [], compact: true)
                }
            }
        }
    }

    private func moneyCard(_ money: PlanMoneyInOut, planSpending: Decimal?) -> some View {
        Card {
            if money.counted.isEmpty {
                notYet("No money in and out was recorded in this time span.")
            } else {
                PlanMoneyInOutLegend(money: money, showsPlanSpending: planSpending != nil,
                                     cuts: money.cutsAmounts(planSpending: planSpending))
                PlanMoneyInOutChart(money: money, planSpending: planSpending)
            }
            whereItStarts(money)
        } header: {
            SectionHeader("Money in and out")
        }
    }

    /// "Money in and out is recorded since 30 Jun 2026: 3 months so far.",
    /// when the span reaches back before it.
    @ViewBuilder
    private func whereItStarts(_ money: PlanMoneyInOut) -> some View {
        if let line = money.whereItStarts(locale: locale) {
            Text(line)
                .font(PlanProgressFont.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
        }
    }

    // MARK: Year by year

    /// *Year by year*: every year with money in and out recorded, newest
    /// first (``SoFarYearByYear``); a year with a check-in opens at the top.
    private func yearByYear(years: Set<Int>, select: @escaping (Int) -> Void) -> some View {
        let money = session.trends(grain: .years, lastYears: nil).money
        return Card {
            SoFarYearByYear(money: money, years: years, select: select)
        } header: {
            SectionHeader("Year by year") {
                Text("saved and spent")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    // MARK: Your date at each check-in

    private func answerCard(_ history: PlanAnswerHistory) -> some View {
        Card {
            if !isMainPlan {
                notYet("Only your main plan records an answer at each check-in.")
                Button {
                    setMainPlan()
                } label: {
                    Label("Set as Main Plan", systemImage: "star")
                }
                .buttonStyle(.borderless)
                .font(PlanProgressFont.caption)
                .disabled(!library.canEdit)
            } else if history.latestAge == nil {
                notYet("Your date shows here from the first check-in that records it.")
            } else {
                // A key only when there's more than the earliest age to tell apart.
                let legend = answerLegend(history)
                if legend.count > 1 {
                    ChartLegendRow(items: legend)
                }
                PlanAnswerHistoryChart(history: history)
                if let line = history.nowLine(locale: locale) {
                    Text(line)
                        .font(PlanProgressFont.text)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .privacySensitiveInFeedback()
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
            }
        } header: {
            SectionHeader("Your last Monday, check-in by check-in")
        }
    }

    /// "━ earliest age ┄ at your pace ┈ saving nothing more", for the lines drawn.
    private func answerLegend(_ history: PlanAnswerHistory) -> [ChartLegendItem] {
        var items = [ChartLegendItem(name: "Earliest age", swatch: .line(.accent, dashed: false))]
        if !history.pacePoints.isEmpty {
            items.append(ChartLegendItem(name: "At your pace", swatch: .line(.taxes, dashed: true)))
        }
        if !history.coastPoints.isEmpty {
            items.append(ChartLegendItem(name: "Saving nothing more", swatch: .dottedLine(.neutral)))
        }
        return items
    }

    private func setMainPlan() {
        do {
            try library.setMainPlan(session.planID)
        } catch {
            library.reportError("The main plan couldn't be changed. \(LibraryStore.describe(error))")
        }
    }

    // MARK: Where this leads

    /// *Where this leads*: the plan's latest answer, which opens Ahead.
    private var whereThisLeads: some View {
        Button {
            navigation.showPlan(session.planID)
        } label: {
            HStack(alignment: .center, spacing: Metrics.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Where this leads")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(verbatim: session.latestAnswer.map { PlanChangeSummary.dateAndAge($0.answer, locale: locale) }
                         ?? "Your date shows on Ahead once the plan is calculated.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .privacySensitiveInFeedback()
                }
                Spacer(minLength: Metrics.s)
                Text("Ahead")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
            }
            .padding(Metrics.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows your plan on Ahead")
    }

    /// What a card needs before it can show anything, in a line.
    private func notYet(_ text: String) -> some View {
        Text(text)
            .font(PlanProgressFont.text)
            .foregroundStyle(Palette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// *Year by year* (UI.md, "So far"): a row for each year with money in and
/// out recorded, newest first: the year ("2026 so far" for this one), a bar
/// of what came in split into what was saved and what was spent, to the
/// scale of the year that took in most, and the year's savings rate. A
/// year with a check-in opens on the year's card at the top of the page.
struct SoFarYearByYear: View {
    let money: PlanMoneyInOut
    /// The years the page has a card for.
    let years: Set<Int>
    let select: (Int) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        let periods = money.counted.reversed()
        let largest = max(periods.map { max($0.cameIn, $0.saved + max(0, $0.spent)) }.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(periods.enumerated()), id: \.element.from) { offset, period in
                if offset > 0 { Divider() }
                row(period, largest: largest)
            }
        }
        Text("The percentage is that year's savings rate. Tap a year to see it at the top.")
            .font(PlanProgressFont.caption)
            .foregroundStyle(Palette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ period: MoneyInOutPeriod, largest: Decimal) -> some View {
        let year = period.from.year
        let opens = years.contains(year)
        return Button {
            select(year)
        } label: {
            HStack(alignment: .center, spacing: Metrics.m) {
                Text(verbatim: money.isSoFar(period) ? "\(String(year)) so far" : String(year))
                    .font(PlanProgressFont.text.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .frame(minWidth: 52, alignment: .leading)
                    .fixedSize()
                    .privacySensitiveInFeedback()
                bar(period, largest: largest)
                Text(verbatim: period.rate.map { AmountFormat.percent($0, digits: 0, locale: locale) } ?? "—")
                    .font(PlanProgressFont.text.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .frame(minWidth: 40, alignment: .trailing)
                    .privacySensitiveInFeedback()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.mutedInk)
                    .opacity(opens ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!opens)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: spoken(period)))
        .accessibilityHint(opens ? Text("Shows the year at the top") : Text(""))
    }

    /// What was saved, in the accent, then what was spent, in grey, to the
    /// scale of `largest`.
    private func bar(_ period: MoneyInOutPeriod, largest: Decimal) -> some View {
        let saved = max(0, period.saved.doubleValue)
        let spent = max(0, period.spent.doubleValue)
        let scale = largest.doubleValue
        return GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: 2) {
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: max(saved > 0 ? 3 : 0, width * CGFloat(saved / scale)))
                Capsule()
                    .fill(Palette.mutedInk.opacity(0.45))
                    .frame(width: max(spent > 0 ? 3 : 0, width * CGFloat(spent / scale)))
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .privacySensitiveInFeedback()
        .accessibilityHidden(true)
    }

    /// "2025: saved 31% of what came in", without amounts, which hide.
    private func spoken(_ period: MoneyInOutPeriod) -> String {
        let year = String(period.from.year)
        guard let rate = period.rate else { return "\(year): no savings rate" }
        return "\(year): saved \(AmountFormat.percent(rate, digits: 0, locale: locale)) of what came in"
    }
}

/// Text in So far's cards: 15 points on iPhone and iPad, 13 on the Mac;
/// captions 13 and 11.
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

#Preview("So far") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        SoFarView(session: session)
            .environment(\.pageLayout, PageLayout())
    }
}

#Preview("So far · Mac") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        SoFarView(session: session)
            .environment(\.pageLayout, PageLayout(isWide: true))
            .frame(width: 1_100, height: 1_000)
    }
}
