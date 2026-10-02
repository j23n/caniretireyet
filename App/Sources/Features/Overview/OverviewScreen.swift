import Model
import SwiftUI
import Tracker

/// The home screen: net worth, history, how you're doing (UI.md, "Overview").
///
/// Top to bottom: the hero number (tap it to switch to plan assets), the
/// history chart with its range, *Total / By asset class* and *Future*
/// switches, the change since the last check-in, the answer to "can I
/// retire yet?", what needs attention, and the allocation bars. The
/// navigation wraps it in a NavigationStack and adds the eye and gear.
struct OverviewScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation

    @AppStorage("overview.scope") private var scope: NetWorthScope = .netWorth
    @AppStorage("overview.range") private var range: OverviewRange = .threeYears
    @AppStorage("overview.stacked") private var isStacked = false
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
        let asOf = library.asOfDate
        let mainPlan = library.mainPlan
        let results = mainPlan.flatMap { plans.results[$0.id] }
        return ScrollView {
            VStack(alignment: .leading, spacing: Metrics.xl) {
                OverviewHeroView(hero: OverviewHero(valuator: valuator, asOf: asOf, scope: scope)) {
                    withAnimation { scope = scope == .netWorth ? .planAssets : .netWorth }
                }
                if library.latestCheckIn == nil {
                    FirstCheckInCard()
                }
                OverviewHistorySection(
                    valuator: valuator, asOf: asOf, scope: scope, results: results, planName: mainPlan?.name,
                    range: $range, isStacked: $isStacked, showsFuture: $navigation.showsFuture)
                VStack(alignment: .leading, spacing: Metrics.l) {
                    if let report = valuator.changeSinceLastCheckIn(asOf: asOf, in: scope) {
                        OverviewChangeCard(report: report)
                    }
                    OverviewAnswerCard(valuator: valuator, asOf: asOf)
                    OverviewAttentionCard(valuator: valuator, asOf: asOf)
                    OverviewAllocationCard(
                        breakdown: valuator.breakdown(by: allocation.dimension, on: asOf, in: scope),
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

/// Net worth (or plan assets) at the latest check-in, with its changes.
/// Tapping it switches between the two.
private struct OverviewHeroView: View {
    let hero: OverviewHero
    let toggleScope: () -> Void

    var body: some View {
        Button(action: toggleScope) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                HStack(spacing: Metrics.xs) {
                    Text(title)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
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
                if hero.scope == .planAssets {
                    Text("What your plans count, e.g. without your home.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(hero.scope == .netWorth ? "Switches to plan assets" : "Switches to net worth")
    }

    private var title: String {
        hero.scope == .netWorth ? "Net worth" : "Plan assets"
    }

    @ViewBuilder
    private var changes: some View {
        if let change = hero.sinceLastCheckIn, let from = hero.lastCheckIn {
            HStack(spacing: Metrics.xs) {
                DeltaText(change)
                Text("since \(AmountFormat.shortDate(from, relativeTo: .today()))")
                    .foregroundStyle(Palette.secondaryInk)
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
            Text("Add your accounts, or import the spreadsheet or ledger journals you've kept so far.")
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
/// it (the time span, *Total / By asset class*, *Future*), the chart with
/// its legend, a short caption with an ⓘ for the full explanation, and the
/// notes on missing or old prices.
///
/// With *Future* on, the chart shows plan assets, so the history lines up
/// with the projection, which is of what the plan counts; the history is
/// the total line, since the projection is a total (*By asset class* is
/// for the past alone); and the projection reaches as far as the chosen
/// horizon (``FutureHorizon``, remembered on the device).
private struct OverviewHistorySection: View {
    let valuator: Valuator
    let asOf: CalendarDate
    let scope: NetWorthScope
    let results: PlanResults?
    let planName: String?
    @Binding var range: OverviewRange
    @Binding var isStacked: Bool
    @Binding var showsFuture: Bool
    @Environment(AppPreferences.self) private var preferences
    @State private var fillsPastPrices = false

    var body: some View {
        // In the base currency, as the history is; a plan in another
        // currency is converted at its start date's rate.
        let projection = results?.portfolio(in: valuator.baseCurrency, valuator: valuator) ?? []
        let canShowFuture = !projection.isEmpty
        let future = showsFuture && canShowFuture
        let chartScope: NetWorthScope = future ? .planAssets : scope
        let now = asOf.dateValue
        let retirement = results?.retirementDate
        let planEnd = projection.last?.date ?? now
        let horizon = preferences.futureHorizon.effective(start: now, retirement: retirement)
        let history = OverviewHistory(
            valuator: valuator, through: asOf, scope: chartScope, range: range, stacked: isStacked && !future,
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
            }
            NetWorthChart(history: history.points, stacked: history.stacked, projection: history.projection,
                          markers: history.markers)
                .environment(\.chartSurface, Palette.page)
            if future {
                ChartCaption(text: futureCaption, detail: futureDetail)
            } else if chartScope == .planAssets {
                Text("Plan assets: the accounts your plans count.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if history.stacked.isEmpty, let missing = history.missing {
                missingNoteView(missing)
            }
            if let summary = history.oldPrices {
                OldPriceNoteView(text: OldPriceNote.text(summary) { valuator.instruments[$0]?.name ?? $0.rawValue }) {
                    fillsPastPrices = true
                }
            }
        }
        .pastPricesSheet(isPresented: $fillsPastPrices)
    }

    /// The row above the chart: the time span, *Total / By asset class*
    /// (only for the past alone) and *Future*. The compact one fits an
    /// iPhone: shorter words, icons for *Total / By asset class*, and
    /// *Future* as a button that stays lit while it's on.
    private func controls(future: Bool, canShowFuture: Bool, horizon: Binding<FutureHorizon>,
                          choices: [FutureHorizon], compact: Bool) -> some View {
        HStack(spacing: Metrics.s) {
            TimeSpanMenu(range: $range, horizon: future ? horizon : nil, choices: choices, compact: compact)
            Picker("Show", selection: $isStacked) {
                if compact {
                    Image(systemName: "chart.xyaxis.line")
                        .accessibilityLabel("Total")
                        .tag(false)
                    Image(systemName: "square.stack.3d.up")
                        .accessibilityLabel("By asset class")
                        .tag(true)
                } else {
                    Text("Total").tag(false)
                    Text("By asset class").tag(true)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(future)
            .help(future ? "With Future on, the past shows as a total" : "Show the total or each asset class")
            Spacer(minLength: 0)
            if canShowFuture {
                if compact {
                    Toggle(isOn: $showsFuture) {
                        Label("Future", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .toggleStyle(.button)
                    .font(.subheadline)
                    .fixedSize()
                } else {
                    Toggle("Future", isOn: $showsFuture)
                        .toggleStyle(.switch)
                        .font(.subheadline)
                        .fixedSize()
                        .help("Continue the chart into your plan's projection")
                }
            }
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
        planName ?? "your plan"
    }

    /// The short caption under the chart while the future is shown.
    private var futureCaption: String {
        isStacked
            ? "Plan assets, then \(planTitle)'s projection. The past shows as a total while Future is on."
            : "Plan assets, then \(planTitle)'s projection, in today's money."
    }

    /// The full explanation, in the ⓘ popover.
    private var futureDetail: String {
        "Plan assets are the accounts your plans count. After today the chart continues with \(planTitle)'s "
            + "projection, in today's money: the dashed line is the middle of the simulated futures, the darker "
            + "band holds half of them and the lighter band 8 in 10. The lighter band can run off the top, so "
            + "the rest stays readable. The projection is a total, so with Future on the past is the total "
            + "line too; By asset class is for the past alone. The time span menu sets how far back and ahead "
            + "the chart reaches."
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
