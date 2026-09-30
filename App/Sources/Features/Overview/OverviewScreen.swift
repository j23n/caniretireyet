import Model
import Storage
import SwiftUI
import Tracker

// PLACEHOLDER — Overview feature engineer: replace this screen's content
// (UI.md, "Overview"). Keep the name `OverviewScreen` and its `init()`: the
// navigation creates it, wraps it in a NavigationStack and adds the eye and
// gear toolbar buttons. It shows real data so the wiring can be checked.

/// The home screen: net worth, history, how you're doing (UI.md, "Overview").
struct OverviewScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        Group {
            if library.hasNoAccounts {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.l) {
                        hero
                        history
                        sinceLastCheckIn
                        answer
                        needsAttention
                        allocation
                    }
                    .padding(Metrics.l)
                    .frame(maxWidth: Metrics.readableWidth)
                    .frame(maxWidth: .infinity)
                }
                .background(Palette.page)
            }
        }
        .navigationTitle("Overview")
    }

    // MARK: Sections

    private var hero: some View {
        let netWorth = library.netWorth
        let change = library.changeSinceLastCheckIn
        return VStack(alignment: .leading, spacing: Metrics.xs) {
            Text("Net worth")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
            AmountText(netWorth.total, tabular: false, animatesChanges: true)
                .font(.largeTitle.bold())
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            if let change {
                HStack(spacing: Metrics.xs) {
                    DeltaText(change.total.change)
                    Text("since \(AmountFormat.shortDate(change.from))")
                        .foregroundStyle(Palette.secondaryInk)
                }
                .font(.subheadline)
            }
        }
    }

    private var history: some View {
        Card {
            NetWorthChart(
                history: library.valuator.series(through: library.asOfDate).chartPoints,
                projection: navigation.showsFuture ? plans.results[library.settings.mainPlan ?? ""]?.portfolio ?? [] : [],
                markers: navigation.showsFuture ? plans.results[library.settings.mainPlan ?? ""]?.markers ?? [] : [])
        } header: {
            SectionHeader("History") {
                Toggle("Future", isOn: Bindable(navigation).showsFuture)
                    .toggleStyle(.switch)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var sinceLastCheckIn: some View {
        if let change = library.changeSinceLastCheckIn {
            Card("Since last check-in") {
                WaterfallChart(steps: WaterfallStep.steps(
                    for: change.total, startLabel: AmountFormat.shortDate(change.from),
                    endLabel: AmountFormat.shortDate(change.to)))
            }
        }
    }

    @ViewBuilder
    private var answer: some View {
        if let headline = plans.mainHeadline {
            Card("Can I retire yet?") {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text(headline.canRetireNow ? "Yes." : "Not yet")
                        .font(.title3.weight(.semibold))
                    if let age = headline.earliestAge {
                        Text("Earliest at \(age), in \(Int((headline.confidence * 10).rounded())) of 10 simulated futures")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    if let progress = headline.fiProgress {
                        ProgressView(value: min(max(progress, 0), 1)) {
                            Text("\(AmountFormat.percent(progress, digits: 0)) of the way")
                                .font(.footnote)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        .tint(Palette.accent)
                    }
                    if let recorded = headline.recordedOn {
                        Text("As recorded on \(AmountFormat.shortDate(recorded))")
                            .font(.caption)
                            .foregroundStyle(Palette.mutedInk)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { navigation.showPlan() }
            }
        }
    }

    @ViewBuilder
    private var needsAttention: some View {
        let stale = library.staleAccounts(threshold: preferences.stalenessThreshold)
        if !stale.isEmpty || library.lastError != nil || !library.mergedConflicts.isEmpty
            || library.loadIssues.contains(where: { $0.severity == .error }) {
            Card("Needs attention") {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    LibraryStatusBanners()
                    ForEach(stale, id: \.account) { account in
                        Button {
                            navigation.showAccount(account.account)
                        } label: {
                            Label(staleText(account), systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Palette.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var allocation: some View {
        Card("Allocation · asset class") {
            BreakdownBars(rows: library.valuator.breakdown(by: .assetClass, on: library.asOfDate).rows)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing here yet", systemImage: AppSymbol.overview)
        } description: {
            Text("Add your accounts, or import the spreadsheet you've kept so far.")
        } actions: {
            Button("Add accounts") { navigation.newAccount() }
                .buttonStyle(.borderedProminent)
            Button("Import a spreadsheet") { navigation.startImport() }
        }
    }

    private func staleText(_ stale: StaleAccount) -> String {
        let name = library.account(stale.account)?.name ?? stale.account.rawValue
        guard let last = stale.lastValuation else { return "\(name): no value yet" }
        return "\(name): last value \(AmountFormat.shortDate(last))"
    }
}

#Preview("Overview") {
    NavigationStack {
        OverviewScreen()
            .overviewToolbar()
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        OverviewScreen()
    }
    .previewEnvironment(PreviewLibrary.empty)
}
