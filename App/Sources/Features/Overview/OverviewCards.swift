import Glance
import Model
import Prices
import Storage
import SwiftUI
import Tracker

// The Overview's cards below the chart (UI.md, "Overview"): since the last
// check-in, this year, the answer before there is one, what needs
// attention, and the allocation. The header above the chart is
// `OverviewHeader`.

// MARK: - Since last check-in

/// The change since the previous check-in (UI.md, "Since last check-in"),
/// which the hero number above says ("▲ +5.730 € in September"): the
/// totals before and after, and a bar each for markets, new money and
/// other, from a shared zero line (``WaterfallChart``). Titled by the month
/// it covers when the check-in before was the end of the month before.
struct OverviewChangeCard: View {
    let report: ChangeReport
    @Environment(\.locale) private var locale

    private var title: String {
        guard let month = GlanceText.coveredMonth(from: report.from, to: report.to) else {
            return "Since last check-in"
        }
        return "What moved in \(GlanceText.month(month, relativeTo: .today(), locale: locale))"
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.m) {
                WaterfallChart(change: report.total,
                               from: AmountFormat.shortDate(report.from, relativeTo: .today(), locale: locale),
                               to: AmountFormat.shortDate(report.to, relativeTo: .today(), locale: locale),
                               showsChange: false)
                Text(Self.explanation(report.total))
                    .font(.footnote)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeader(title)
                .privacySensitiveInFeedback()
        }
    }

    /// What the bars mean, under them; *Other* only when there is some.
    static func explanation(_ change: ValueChange) -> String {
        var text = "Markets: prices, exchange rates and interest. New money: what you added or took out."
        if change.other != 0 {
            text += " Other: changes in accounts without new money recorded."
        }
        return text
    }
}

// MARK: - This year

/// How net worth changed since 31 December of last year (UI.md, "This
/// year"), split as *What moved* splits a check-in's change: markets, new
/// money and other, so what you saved stands apart from what markets did.
/// The hero says this year's change in per cent; this card leads with it
/// in money ("▲ +18.240 € since 31 Dec 2025"), and in per cent while
/// amounts are hidden. Under it, the savings rate over the money in and
/// out recorded this year, when there is some (``OverviewYearText``).
struct OverviewYearCard: View {
    /// Tracker's `Valuator.changeThisYear(asOf:)`.
    let report: ChangeReport
    /// Tracker's `Valuator.savingsRate(from:through:)` over the values
    /// recorded this year; `nil` without money in and out.
    var savings: SavingsRate?
    @Environment(\.locale) private var locale

    var body: some View {
        Card("This year") {
            VStack(alignment: .leading, spacing: Metrics.m) {
                WaterfallChart(change: report.total,
                               from: AmountFormat.shortDate(report.from, relativeTo: .today(), locale: locale),
                               to: AmountFormat.shortDate(report.to, relativeTo: .today(), locale: locale))
                Text(OverviewChangeCard.explanation(report.total))
                    .font(.footnote)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let savings, let text = OverviewYearText.savings(savings, today: report.to, locale: locale) {
                    AmountSentenceText(text)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Can I retire yet?

/// "Can I retire yet?" before the main plan has an answer (UI.md,
/// "Overview"): a card below the chart with the next step, *Create a plan*
/// or *Calculate* the main plan. With an answer, the header
/// (``OverviewHeader``) says it instead.
struct OverviewAnswerCard: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @State private var error: String?

    var body: some View {
        Card("Can I retire yet?") {
            Group {
                if let plan = library.mainPlan {
                    waiting(for: plan)
                } else {
                    noPlan
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Without a main plan: create the first plan, as the Plan screen does,
    /// or open the plans to choose one; when the main plan's file couldn't
    /// be read, its details instead. Why *Create a plan* failed shows under
    /// it until the plans change.
    private var noPlan: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            Text(noPlanText)
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if mainPlanIsUnreadable {
                Button("Show Details") { navigation.show(.sync) }
                    .buttonStyle(.borderedProminent)
            } else if library.sortedPlans.isEmpty {
                Button("Create a plan") { createPlan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!library.canEdit)
            } else {
                Button("Open Plan") { navigation.showPlan() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .onChange(of: library.sortedPlans.isEmpty) { error = nil }
    }

    private var noPlanText: String {
        if mainPlanIsUnreadable { return "Your main plan's file couldn't be read, so it has no answer." }
        return library.sortedPlans.isEmpty ? "Make a plan to see when you could retire."
            : "Choose a main plan to see when you could retire."
    }

    /// Whether a main plan is chosen but its file couldn't be read.
    private var mainPlanIsUnreadable: Bool {
        guard let main = library.settings.mainPlan else { return false }
        return library.library.plans[main] == nil && library.unloadedFiles.contains(.plan(main))
    }

    /// "Base case can't be calculated: …", with *Try Again* and *Open Plan*.
    private func cantCalculate(_ plan: PlanDocument, error: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Label("\(plan.name) can't be calculated: \(error)", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
            HStack(spacing: Metrics.s) {
                Button("Try Again") { Task { await plans.run(plan.id) } }
                Button("Open Plan") { navigation.showPlan(plan.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// The main plan without an answer: its calculation going on, why it
    /// can't run (with *Try Again* and *Open Plan*), or *Calculate*.
    @ViewBuilder
    private func waiting(for plan: PlanDocument) -> some View {
        if plans.isRunning(plan.id) {
            HStack(spacing: Metrics.s) {
                ProgressView()
                if let progress = plans.progress(of: plan.id, .checkIn) ?? plans.progress(of: plan.id, .base) {
                    Text("Working out \(plan.name)… \(PlanRunText.overall(progress, locale: locale))")
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                } else {
                    Text("Working out \(plan.name)…")
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                }
            }
        } else if let error = plans.errors[plan.id] {
            cantCalculate(plan, error: error)
        } else {
            VStack(alignment: .leading, spacing: Metrics.m) {
                Text("Calculate \(plan.name) to see when you could retire. Each check-in then records its answer.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
                Button("Calculate") { Task { await plans.run(plan.id) } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Creates the first plan, "Base case", from the latest check-in, makes
    /// it the main plan and opens it, as the Plan screen's *Create your
    /// first plan* does.
    private func createPlan() {
        let plan = PlanEditing.newPlan(id: library.newPlanID(for: "Base case"), name: "Base case",
                                       library: library.library, asOf: library.asOfDate)
        do {
            try library.save(plan)
            if library.needsMainPlan { try library.setMainPlan(plan.id) }
            error = nil
            navigation.showPlan(plan.id)
        } catch {
            self.error = LibraryStore.describe(error)
        }
    }

}

// MARK: - Needs attention

/// Only shown when something needs you: stale accounts, accounts with
/// problems in their trades (opening the account), prices that are missing
/// or couldn't be fetched, past prices and exchange rates the history is
/// missing (opening *Fill In Past Prices*), the library's own state (merged
/// sync conflicts, save errors, unreadable files) and plan warnings.
struct OverviewAttentionCard: View {
    /// The day the Overview reports on.
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(CheckInStore.self) private var checkIn
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @State private var fillsPastPrices = false

    var body: some View {
        let items = self.items
        let showsBanners = LibraryStatusBanners.showsAny(for: library)
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
            library: library.library, valuator: library.valuator, on: today,
            stalenessThreshold: preferences.stalenessThreshold, locale: locale)
        if checkIn.hasDraft, let failures = checkIn.priceList?.failures, !failures.isEmpty {
            items.append(OverviewAttentionItem(
                id: "checkin.prices", systemImage: "tag.slash",
                title: failures.count == 1 ? "A price couldn't be fetched" : "\(failures.count) prices couldn't be fetched",
                detail: "Type them in on the check-in's price list.", target: .checkIn))
        }
        if let main = library.settings.mainPlan, let error = plans.errors[main] {
            items.append(OverviewAttentionItem(
                id: "plan.error", systemImage: "exclamationmark.triangle",
                title: "\(library.mainPlan?.name ?? "Your plan") couldn't run", detail: error, target: .plan))
        }
        if let main = library.settings.mainPlan, let bridge = plans.results[main]?.details.focus.bridges.first,
           bridge.share >= 0.05 {
            let futures = Int(wholeNumber: bridge.share * 100)
            let age = bridge.accessibleFromAge.map { " at \($0)" } ?? ""
            items.append(OverviewAttentionItem(
                id: "plan.bridge", systemImage: "lock",
                title: "Money could run short before locked money opens",
                detail: "In \(futures) of 100 simulated futures, it runs out before your pension money becomes "
                    + "available\(age).",
                target: .plan))
        }
        return items
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
                    .privacySensitiveInFeedback()
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
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
    @Binding var dimension: BreakdownDimension

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
                    ForEach(BreakdownDimension.allCases, id: \.self) { option in
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
                if let report = valuator.changeThisYear(asOf: date) {
                    OverviewYearCard(report: report,
                                     savings: valuator.savingsRate(from: report.from.adding(days: 1), through: date))
                }
                // Before the main plan's first calculation.
                OverviewAnswerCard()
                OverviewAttentionCard(today: date)
                OverviewAllocationCard(breakdown: valuator.breakdown(by: .assetClass, on: date),
                                       dimension: .constant(.assetClass))
            }
            .padding()
        }
        .background(Palette.page)
    }
    .previewEnvironment()
}
