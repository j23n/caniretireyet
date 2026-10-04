import Model
import Prices
import Storage
import SwiftUI
import Tracker

// The Overview's cards below the chart (UI.md, "Overview"): since the last
// check-in, the answer, what needs attention, and the allocation.

// MARK: - Since last check-in

/// The change since the previous check-in (UI.md, "Since last check-in"):
/// a headline ("▲ +5.730 € since 31 Aug"), the totals before and after,
/// and a bar each for markets, new money and other, from a shared zero
/// line (``WaterfallChart``).
struct OverviewChangeCard: View {
    let report: ChangeReport
    @Environment(\.locale) private var locale

    var body: some View {
        Card("Since last check-in") {
            VStack(alignment: .leading, spacing: Metrics.m) {
                WaterfallChart(steps: WaterfallStep.steps(
                    for: report.total,
                    startLabel: AmountFormat.shortDate(report.from, relativeTo: .today(), locale: locale),
                    endLabel: AmountFormat.shortDate(report.to, relativeTo: .today(), locale: locale)))
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var explanation: String {
        var text = "Markets: prices, exchange rates and interest. New money: what you added or took out."
        if report.total.other != 0 {
            text += " Other: changes in accounts without new money recorded."
        }
        return text
    }
}

// MARK: - Can I retire yet?

/// The main plan's answer (its latest results, or the headline recorded at
/// the last check-in), how close your plan assets are to what retiring
/// today needs (``PlanReadinessView``, with an ⓘ), and how you compare with
/// the latest baseline. Tapping it opens the plan. It never starts a run:
/// plans run from the Plan screen and at check-ins.
///
/// The card opens the plan with a tap gesture rather than being a button,
/// so the ⓘ inside it gets its own taps; the chevron is the button
/// VoiceOver and keyboards use.
struct OverviewAnswerCard: View {
    let valuator: Valuator
    let asOf: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale

    var body: some View {
        Card {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            SectionHeader("Can I retire yet?") {
                Button {
                    navigation.showPlan()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.mutedInk)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open the plan")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            navigation.showPlan()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open the plan") {
            navigation.showPlan()
        }
    }

    @ViewBuilder
    private var content: some View {
        let plan = library.mainPlan
        if let headline = plans.mainHeadline {
            answer(headline, gap: baselineGap(for: plan))
        } else if let plan {
            waiting(for: plan)
        } else {
            VStack(alignment: .leading, spacing: Metrics.s) {
                Text("Make a plan to see when you could retire.")
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Text("Create a plan")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
    }

    @ViewBuilder
    private func answer(_ headline: PlanHeadline, gap: OverviewBaselineGap?) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(headline.canRetireNow ? "Yes" : "Not yet")
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(earliestText(headline))
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Text(confidenceText(headline))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
            // Plan assets against what retiring today needs, from the simulation. An answer
            // recorded before that existed has only the old FI progress, which disagreed with
            // the chance of retiring today, so it gets a neutral line instead.
            PlanReadinessView(headline: headline,
                              fallback: headline.recordedOn != nil ? PlanResultsText.readinessNotRecorded : nil)
            if let gap {
                HStack(spacing: Metrics.xs) {
                    DeltaText(gap.gap, currency: gap.currency)
                    Text(gapText(gap))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .font(.subheadline)
            }
            if let recorded = headline.recordedOn {
                Text("As recorded at the check-in on \(AmountFormat.shortDate(recorded, locale: locale))")
                    .font(.caption)
                    .foregroundStyle(Palette.mutedInk)
            } else if let status = runStatus {
                Text(status)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.mutedInk)
            }
            Text(AboutText.disclaimer)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
        }
    }

    /// Under an answer from this session's results: a calculation going on,
    /// or that they're out of date.
    private var runStatus: String? {
        guard let main = library.settings.mainPlan else { return nil }
        if let progress = plans.progress(of: main, .checkIn) ?? plans.progress(of: main, .base) {
            return PlanRunText.status(progress, isCheckIn: plans.isRunning(main, .checkIn), locale: locale)
        }
        guard !plans.staleReasons(of: main).isEmpty else { return nil }
        return "Calculated before your latest changes · open the plan to recalculate"
    }

    @ViewBuilder
    private func waiting(for plan: PlanDocument) -> some View {
        if plans.isRunning(plan.id) {
            HStack(spacing: Metrics.s) {
                ProgressView()
                if let progress = plans.progress(of: plan.id, .checkIn) ?? plans.progress(of: plan.id, .base) {
                    Text("Working out \(plan.name)… \(PlanRunText.overall(progress, locale: locale))")
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                } else {
                    Text("Working out \(plan.name)…")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        } else if plans.isAvailable, let error = plans.errors[plan.id] {
            Text(error)
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("\(plan.name)'s answer appears here after your next check-in, or once you calculate the plan.")
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func baselineGap(for plan: PlanDocument?) -> OverviewBaselineGap? {
        guard let plan, let baseline = library.library.baselines(for: plan.id).last else { return nil }
        return OverviewBaselineGap(baseline: baseline, valuator: valuator, on: asOf,
                                   currency: PlanMoney.currency(of: baseline, settings: library.settings))
    }

    private func earliestText(_ headline: PlanHeadline) -> String {
        if headline.canRetireNow { return "You could retire today" }
        guard let age = headline.earliestAge else { return "No retirement age works out yet" }
        guard let date = headline.earliestDate else { return "Earliest at \(age)" }
        let when = date.dateValue.formatted(Date.FormatStyle.dateTime.month(.wide).year().locale(locale))
        return "Earliest at \(age) · \(when)"
    }

    private func confidenceText(_ headline: PlanHeadline) -> String {
        let tenths = Int(wholeNumber: headline.confidence * 10)
        return headline.canRetireNow
            ? "It works in at least \(tenths) of 10 simulated futures"
            : "The first age that works in \(tenths) of 10 simulated futures"
    }

    private func gapText(_ gap: OverviewBaselineGap) -> String {
        let name = gap.name(relativeTo: asOf, locale: locale)
        return gap.gap >= 0 ? "ahead of your \(name) baseline" : "behind your \(name) baseline"
    }
}

// MARK: - Needs attention

/// Only shown when something needs you: stale accounts, accounts with
/// problems in their trades (opening the account), prices that are missing
/// or couldn't be fetched, past prices and exchange rates the history is
/// missing (opening *Fill In Past Prices*), the library's own state (merged
/// sync conflicts, save errors, unreadable files) and plan warnings.
struct OverviewAttentionCard: View {
    let valuator: Valuator
    let asOf: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(CheckInStore.self) private var checkIn
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @State private var fillsPastPrices = false

    var body: some View {
        let items = self.items
        let showsBanners = hasLibraryBanners
        if !items.isEmpty || showsBanners {
            Card("Needs attention") {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    if showsBanners {
                        LibraryStatusBanners()
                    }
                    ForEach(items) { item in
                        row(for: item)
                    }
                }
            }
            .pastPricesSheet(isPresented: $fillsPastPrices)
        }
    }

    private var items: [OverviewAttentionItem] {
        var items = OverviewAttention.items(
            library: library.library, valuator: valuator, asOf: asOf, today: .today(),
            stalenessThreshold: preferences.stalenessThreshold, locale: locale)
        if checkIn.hasDraft, let failures = checkIn.priceList?.failures, !failures.isEmpty {
            items.append(OverviewAttentionItem(
                id: "checkin.prices", systemImage: "tag.slash",
                title: failures.count == 1 ? "A price couldn't be fetched" : "\(failures.count) prices couldn't be fetched",
                detail: "Type them in on the check-in's price list.", target: .checkIn))
        }
        if plans.isAvailable, let main = library.settings.mainPlan, let error = plans.errors[main] {
            items.append(OverviewAttentionItem(
                id: "plan.error", systemImage: "exclamationmark.triangle",
                title: "\(library.mainPlan?.name ?? "Your plan") couldn't run", detail: error, target: .plan))
        }
        if let main = library.settings.mainPlan, let failure = plans.results[main]?.failure,
           let share = failure.bridgeShare, share >= 0.05 {
            let futures = Int(wholeNumber: share * 100)
            let age = failure.bridgeAge.map { " at \($0)" } ?? ""
            items.append(OverviewAttentionItem(
                id: "plan.bridge", systemImage: "lock",
                title: "Money could run short before locked money opens",
                detail: "In \(futures) of 100 simulated futures, it runs out before your pension money becomes "
                    + "available\(age).",
                target: .plan))
        }
        return items
    }

    private var hasLibraryBanners: Bool {
        library.isReadOnly || library.lastError != nil || !library.mergedConflicts.isEmpty
            || !library.conflictFailures.isEmpty || library.loadIssues.contains(where: { $0.severity == .error })
    }

    @ViewBuilder
    private func row(for item: OverviewAttentionItem) -> some View {
        switch item.target {
        case .account(let id):
            NavigationLink(value: id) {
                OverviewAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        case .instrument(let id):
            NavigationLink {
                InstrumentEditor(instrumentID: id)
            } label: {
                OverviewAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        case .checkIn:
            Button {
                navigation.startCheckIn()
            } label: {
                OverviewAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        case .plan:
            Button {
                navigation.showPlan()
            } label: {
                OverviewAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        case .fillPastPrices:
            Button {
                fillsPastPrices = true
            } label: {
                OverviewAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        }
    }
}

/// One item: a warning icon, what it is, what to do, and a chevron.
private struct OverviewAttentionRow: View {
    let item: OverviewAttentionItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
            Image(systemName: item.systemImage)
                .foregroundStyle(Palette.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Metrics.s)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.mutedInk)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Metrics.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Allocation

/// Horizontal bars with values and shares, grouped by the chosen dimension.
struct OverviewAllocationCard: View {
    let breakdown: Breakdown
    @Binding var dimension: OverviewAllocation

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.s) {
                BreakdownBars(rows: breakdown.rows, limit: dimension.limit)
                if dimension == .assetClass && breakdown.slices.contains(where: { $0.key == .debts }) {
                    Text("Shares are of what you own; debts are their own bar.")
                        .font(.footnote)
                        .foregroundStyle(Palette.mutedInk)
                }
            }
        } header: {
            SectionHeader("Allocation") {
                Picker("Group by", selection: $dimension) {
                    ForEach(OverviewAllocation.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

#Preview("Cards") {
    let valuator = PreviewLibrary.valuator
    let date = PreviewLibrary.latestCheckIn
    NavigationStack {
        ScrollView {
            VStack(spacing: Metrics.l) {
                if let report = valuator.changeSinceLastCheckIn(asOf: date) {
                    OverviewChangeCard(report: report)
                }
                OverviewAnswerCard(valuator: valuator, asOf: date)
                OverviewAttentionCard(valuator: valuator, asOf: date)
                OverviewAllocationCard(breakdown: valuator.breakdown(by: .assetClass, on: date),
                                       dimension: .constant(.assetClass))
            }
            .padding()
        }
        .background(Palette.page)
    }
    .previewEnvironment()
}
