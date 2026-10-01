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
                Text("since \(AmountFormat.shortDate(from))")
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

/// The history chart: range, *Future*, the chart, and *Total / By asset
/// class*. With *Future* on, the chart shows plan assets, so the history
/// lines up with the projection, which is of what the plan counts.
private struct OverviewHistorySection: View {
    let valuator: Valuator
    let asOf: CalendarDate
    let scope: NetWorthScope
    let results: PlanResults?
    let planName: String?
    @Binding var range: OverviewRange
    @Binding var isStacked: Bool
    @Binding var showsFuture: Bool
    @State private var fillsPastPrices = false

    var body: some View {
        let projection = results?.portfolio ?? []
        let canShowFuture = !projection.isEmpty
        let future = showsFuture && canShowFuture
        let chartScope: NetWorthScope = future ? .planAssets : scope
        let history = OverviewHistory(
            valuator: valuator, through: asOf, scope: chartScope, range: range, stacked: isStacked,
            projection: future ? projection : [], markers: future ? (results?.markers ?? []) : [])
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack(spacing: Metrics.m) {
                Picker("Range", selection: $range) {
                    ForEach(OverviewRange.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: Metrics.s)
                if canShowFuture {
                    Toggle("Future", isOn: $showsFuture)
                        .toggleStyle(.switch)
                        .font(.subheadline)
                        .fixedSize()
                        .help("Continue the chart into your plan's projection")
                }
            }
            NetWorthChart(history: history.points, stacked: history.stacked, projection: history.projection,
                          markers: history.markers)
            HStack(spacing: Metrics.m) {
                Picker("Show", selection: $isStacked) {
                    Text("Total").tag(false)
                    Text("By asset class").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: Metrics.s)
                if future {
                    HistoryLegend()
                }
            }
            if future {
                Text(futureCaption)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else if chartScope == .planAssets {
                Text("Plan assets: the accounts your plans count.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if let summary = history.oldPrices {
                OldPriceNoteView(text: OldPriceNote.text(summary) { valuator.instruments[$0]?.name ?? $0.rawValue }) {
                    fillsPastPrices = true
                }
            }
        }
        .pastPricesSheet(isPresented: $fillsPastPrices)
    }

    private var futureCaption: String {
        let plan = planName.map { "\($0)'s" } ?? "your plan's"
        return "Plan assets, continued by \(plan) projection in today's money. "
            + "The shaded band covers 8 of 10 simulated futures; the dashed line is the middle one."
    }
}

/// "— Actual  - - Projected", under the chart while the future is shown.
private struct HistoryLegend: View {
    var body: some View {
        HStack(spacing: Metrics.m) {
            HStack(spacing: Metrics.xs) {
                Capsule()
                    .fill(Palette.ink)
                    .frame(width: 14, height: 2)
                Text("Actual")
            }
            HStack(spacing: Metrics.xs) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 1))
                    path.addLine(to: CGPoint(x: 14, y: 1))
                }
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                .frame(width: 14, height: 2)
                Text("Projected")
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.secondaryInk)
        .accessibilityElement(children: .combine)
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
