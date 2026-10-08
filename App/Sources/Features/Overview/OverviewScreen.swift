import Model
import SwiftUI
import Tracker

/// The home screen: net worth, history, how you're doing (UI.md, "Overview").
///
/// Top to bottom: the hero number (net worth), the history chart by asset
/// class with its time span and *Future* switch, the change since the last
/// check-in, the answer to "can I retire yet?", what needs attention, and
/// the allocation bars. Everything is net worth; only the chart with
/// *Future* on shows plan assets, so its past meets the projection. The
/// navigation wraps it in a NavigationStack and adds the eye and gear.
struct OverviewScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation

    // `overview.scope` and `overview.stacked`, stored by earlier versions, are no longer read.
    @AppStorage("overview.range") private var range: OverviewRange = .threeYears
    @AppStorage("overview.allocation") private var allocation: OverviewAllocation = .assetClass

    init() {}

    var body: some View {
        Group {
            if library.hasNoAccounts {
                OverviewEmptyState()
            } else {
                content
            }
        }
        .navigationTitle("Overview")
    }

    private var content: some View {
        @Bindable var navigation = navigation
        let valuator = library.valuator
        // Your accounts as they are today, as the accounts list has them:
        // values since the latest check-in (a trade, an import) and prices
        // fetched since count. The plan's projection starts at the latest
        // check-in instead.
        let today = CalendarDate.today()
        let planStart = library.asOfDate
        let mainPlan = library.mainPlan
        let results = mainPlan.flatMap { plans.results[$0.id] }
        return ScrollView {
            VStack(alignment: .leading, spacing: Metrics.xl) {
                OverviewHeroView(hero: OverviewHero(valuator: valuator, asOf: today))
                if library.latestCheckIn == nil {
                    FirstCheckInCard()
                }
                OverviewHistorySection(
                    valuator: valuator, today: today, planStart: planStart, results: results, planID: mainPlan?.id,
                    planName: mainPlan?.name, range: $range, showsFuture: $navigation.showsFuture)
                VStack(alignment: .leading, spacing: Metrics.l) {
                    if let report = valuator.changeSinceLastCheckIn(asOf: today) {
                        OverviewChangeCard(report: report)
                    }
                    OverviewAnswerCard(valuator: valuator, asOf: today)
                    OverviewAttentionCard(valuator: valuator, asOf: today)
                    OverviewAllocationCard(
                        breakdown: valuator.breakdown(by: allocation.dimension, on: today),
                        dimension: $allocation)
                }
            }
            .padding(Metrics.l)
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
    }
}

// MARK: - Hero

/// Net worth today, with its changes.
private struct OverviewHeroView: View {
    let hero: OverviewHero

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text("Net worth")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
            AmountText(hero.total, tabular: false, animatesChanges: true)
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.ink)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Metrics.m) { changes }
                VStack(alignment: .leading, spacing: 2) { changes }
            }
            .font(.subheadline)
            if !hero.isComplete {
                Text("Some values are missing: see Needs attention.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var changes: some View {
        if let change = hero.sinceLastCheckIn, let from = hero.lastCheckIn {
            HStack(spacing: Metrics.xs) {
                DeltaText(change)
                if let month = hero.changeMonth {
                    Text("in \(OverviewAttention.monthName(month, today: .today()))")
                        .foregroundStyle(Palette.secondaryInk)
                } else {
                    Text("since \(AmountFormat.shortDate(from, relativeTo: .today()))")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
        if let year = hero.thisYear {
            HStack(spacing: Metrics.xs) {
                DeltaText(percent: year)
                Text("this year")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}

/// Before the first check-in: one clear next step.
private struct FirstCheckInCard: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Card("Record your first values") {
            VStack(alignment: .leading, spacing: Metrics.m) {
                Text("A check-in records what each account is worth today. Your history starts with it.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start a check-in") { navigation.startCheckIn() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// A new library: add accounts or import a spreadsheet.
private struct OverviewEmptyState: View {
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        ContentUnavailableView {
            Label("Nothing here yet", systemImage: AppSymbol.overview)
        } description: {
            Text("Add your accounts, or import the spreadsheet you've kept so far.")
        } actions: {
            Button("Add accounts") { navigation.newAccount() }
                .buttonStyle(.borderedProminent)
            Button("Import…") { navigation.startImport() }
        }
        .background(Palette.page)
    }
}

// MARK: - History

/// The history chart (UI.md, "History chart"): one row of controls above
/// it (the time span and *Future*), the chart stacked by asset class with
/// its legend, with *Future* on a short caption with an ⓘ for the full
/// explanation, and the notes on missing or old prices.
///
/// The past is net worth, through today. With *Future* on it's plan assets,
/// still by asset class (``OverviewHistory``), through the latest check-in,
/// where the projection starts: the projection is of what the plan counts,
/// so the past's total meets it there. The projection reaches as far as the
/// chosen horizon (``FutureHorizon``, remembered on the device).
///
/// *Future* shows whenever there's a main plan. Plans only run when asked,
/// so the main plan may have no results yet: turning *Future* on is that
/// request, and calculates it, with its progress (or why it can't run)
/// under the controls until the projection is there.
private struct OverviewHistorySection: View {
    let valuator: Valuator
    let today: CalendarDate
    /// Where the plan's projection starts: the latest check-in.
    let planStart: CalendarDate
    let results: PlanResults?
    let planID: PlanID?
    let planName: String?
    @Binding var range: OverviewRange
    @Binding var showsFuture: Bool
    @Environment(AppPreferences.self) private var preferences
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @State private var fillsPastPrices = false

    var body: some View {
        // In the base currency, as the history is; a plan in another
        // currency is converted at its start date's rate.
        let projection = results?.portfolio(in: valuator.baseCurrency, valuator: valuator) ?? []
        let canShowFuture = planID != nil
        let future = showsFuture && !projection.isEmpty
        let now = planStart.dateValue
        let retirement = results?.retirementDate
        let planEnd = projection.last?.date ?? now
        let horizon = preferences.futureHorizon.effective(start: now, retirement: retirement)
        let history = OverviewHistory(
            valuator: valuator, through: future ? planStart : today, range: range,
            projection: future ? projection : [], markers: future ? (results?.markers ?? []) : [],
            horizon: future ? horizon.end(start: now, retirement: retirement, planEnd: planEnd) : nil)
        VStack(alignment: .leading, spacing: Metrics.m) {
            let horizonBinding = preferences.horizonBinding(start: now, retirement: retirement)
            let choices = FutureHorizon.choices(start: now, retirement: retirement)
            ViewThatFits(in: .horizontal) {
                controls(future: future, canShowFuture: canShowFuture, horizon: horizonBinding, choices: choices,
                         compact: false)
                controls(future: future, canShowFuture: canShowFuture, horizon: horizonBinding, choices: choices,
                         compact: true)
                // The largest text sizes: *Future* under the time span.
                VStack(alignment: .leading, spacing: Metrics.s) {
                    TimeSpanMenu(range: $range, horizon: future ? horizonBinding : nil, choices: choices,
                                 compact: true)
                    if canShowFuture {
                        futureToggle(compact: true)
                    }
                }
            }
            if showsFuture, projection.isEmpty, let planID {
                futureStatus(planID)
            }
            NetWorthChart(history: history.points, stacked: history.stacked, projection: history.projection,
                          markers: history.markers, title: history.scope == .planAssets ? "Plan assets" : "Net worth")
                .environment(\.chartSurface, Palette.page)
            if future {
                ChartCaption(text: futureCaption, detail: futureDetail)
            }
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
        .task(id: showsFuture) { await calculateForFuture() }
    }

    /// Turning *Future* on asks for the main plan's projection: calculates
    /// it when there are no results and nothing is running. After a failure
    /// it waits for *Try Again*, so a plan that can't run isn't retried on
    /// every visit.
    private func calculateForFuture() async {
        guard showsFuture, let planID, plans.results[planID] == nil, !isCalculating(planID),
              plans.errors[planID] == nil else { return }
        await plans.run(planID)
    }

    private func isCalculating(_ plan: PlanID) -> Bool {
        plans.isRunning(plan, .base) || plans.isRunning(plan, .checkIn)
    }

    /// Under the controls while *Future* is on without a projection: the
    /// main plan's calculation with its bar, why it can't run (with *Try
    /// Again* and *Open Plan*), or *Calculate*.
    @ViewBuilder
    private func futureStatus(_ plan: PlanID) -> some View {
        if let progress = plans.progress(of: plan, .base) ?? plans.progress(of: plan, .checkIn) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                HStack {
                    Text("Calculating \(planTitle)'s projection…")
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
                Text("Calculate \(planTitle) to see its projection.")
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Metrics.s)
                Button("Calculate") { Task { await plans.run(plan) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .font(.subheadline)
        }
    }

    /// The row above the chart: the time span and *Future*. The compact
    /// one is for an iPhone at larger text sizes: shorter words, and
    /// *Future* as a button that stays lit while it's on.
    private func controls(future: Bool, canShowFuture: Bool, horizon: Binding<FutureHorizon>,
                          choices: [FutureHorizon], compact: Bool) -> some View {
        HStack(spacing: Metrics.s) {
            TimeSpanMenu(range: $range, horizon: future ? horizon : nil, choices: choices, compact: compact)
            Spacer(minLength: 0)
            if canShowFuture {
                futureToggle(compact: compact)
            }
        }
    }

    /// *Future*: a switch, or where room is short a button that stays lit
    /// while it's on.
    @ViewBuilder
    private func futureToggle(compact: Bool) -> some View {
        if compact {
            Toggle(isOn: $showsFuture) {
                Label("Future", systemImage: "chart.line.uptrend.xyaxis")
            }
            .toggleStyle(.button)
            .font(.subheadline)
            .fixedSize()
            .help(Self.futureHelp)
        } else {
            Toggle("Future", isOn: $showsFuture)
                .toggleStyle(.switch)
                .font(.subheadline)
                .fixedSize()
                .help(Self.futureHelp)
        }
    }

    private static let futureHelp = "Continue the chart into your plan's projection, from your plan assets"

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
        planName ?? "your plan"
    }

    /// The short caption under the chart while the future is shown.
    private var futureCaption: String {
        "Plan assets by asset class, then \(planTitle)'s projection, in today's money."
    }

    /// The full explanation, in the ⓘ popover.
    private var futureDetail: String {
        "With Future on, the past shows your plan assets: the accounts your plans count, e.g. without your "
            + "home. That's what the projection is of, so the two meet at today; turn Future off to see your "
            + "whole net worth. After today the chart continues with \(planTitle)'s projection, in today's "
            + "money: the dashed line is the middle of the simulated futures, the darker band holds half of them "
            + "and the lighter band 8 in 10. The lighter band can run off the top, so the rest stays readable. "
            + "The projection is one total: it starts from what the plan's accounts add up to today, less any "
            + "debts below the zero line. The time span menu sets how far back and ahead the chart reaches."
    }
}

#Preview("Overview") {
    NavigationStack {
        OverviewScreen()
            .overviewToolbar()
            .appDestinations()
    }
    .previewEnvironment()
}

#Preview("Missing past rates") {
    // A dollar account imported without past exchange rates: dashed history, a note, and Needs attention.
    NavigationStack {
        OverviewScreen()
            .overviewToolbar()
            .appDestinations()
    }
    .previewEnvironment(PreviewLibrary.withForeignAccount)
}

#Preview("Problems with trades") {
    // Directa's statement differs from its trades, and a buy has no price: one Needs attention item.
    NavigationStack {
        OverviewScreen()
            .overviewToolbar()
            .appDestinations()
    }
    .previewEnvironment(PreviewLibrary.withStatementMismatch)
}

#Preview("Hidden amounts") {
    NavigationStack {
        OverviewScreen()
            .environment(\.hidesAmounts, true)
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        OverviewScreen()
    }
    .previewEnvironment(PreviewLibrary.empty)
}
