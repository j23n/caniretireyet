import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The Timeline at *Decades* (UI.md, "Timeline"): your records to now, then
/// the main plan's futures to its end, on one chart. The time span menu
/// above it, the chart stacked by asset class with its legend, a short
/// caption with an ⓘ for the full explanation, and the notes on missing or
/// old prices.
///
/// The past is plan assets, by asset class (``HistoryChartData``), through
/// the latest check-in, where the projection starts: the projection is of
/// what the plan counts, so the past's total meets it there. The projection
/// reaches as far as the chosen horizon (``FutureHorizon``, remembered on
/// the device). Without a projection yet, it calculates the main plan, with
/// its progress (or why it can't run) above the chart; until then the past
/// is your whole net worth, through today.
struct DecadesChart: View {
    let plan: PlanDocument
    let results: PlanResults?
    let today: CalendarDate
    /// The plot's height: taller on the Timeline, where it's the page.
    var chartHeight: CGFloat = 220
    @AppStorage("overview.range") private var range: HistoryRange = .threeYears
    @Environment(LibraryStore.self) private var library
    @Environment(AppPreferences.self) private var preferences
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @State private var fillsPastPrices = false

    private var valuator: Valuator { library.valuator }
    private var planStart: CalendarDate { library.asOfDate }
    private var planID: PlanID? { plan.id }
    private var planName: String? { plan.name }

    var body: some View {
        let projection = results?.portfolio ?? []
        let future = !projection.isEmpty
        let now = planStart.dateValue
        let retirement = results?.retirementDate
        let planEnd = projection.last?.date ?? now
        let horizon = preferences.futureHorizon.effective(start: now, retirement: retirement)
        let history = HistoryChartData(
            valuator: valuator, through: future ? planStart : today, range: range,
            projection: future ? projection : [], markers: future ? (results?.markers ?? []) : [],
            horizon: future ? horizon.end(start: now, retirement: retirement, planEnd: planEnd) : nil)
        VStack(alignment: .leading, spacing: Metrics.m) {
            let horizonBinding = preferences.horizonBinding(start: now, retirement: retirement)
            let choices = FutureHorizon.choices(start: now, retirement: retirement)
            ViewThatFits(in: .horizontal) {
                TimeSpanMenu(range: $range, horizon: future ? horizonBinding : nil, choices: choices)
                TimeSpanMenu(range: $range, horizon: future ? horizonBinding : nil, choices: choices,
                             compact: true)
            }
            if projection.isEmpty, let planID {
                futureStatus(planID)
            }
            NetWorthChart(history: history.points, stacked: history.stacked, projection: history.projection,
                          markers: history.markers, title: history.scope == .planAssets ? "Money in the plan" : "Net worth",
                          height: chartHeight)
            if future {
                ChartCaption(text: futureCaption, detail: futureDetail)
                    .privacySensitiveInFeedback()
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
        .task(id: plan.id) { await calculateForFuture() }
    }

    /// Without results, calculates the main plan for its projection, when
    /// nothing is running. After a failure it waits for *Try Again*, so a
    /// plan that can't run isn't retried on every visit.
    private func calculateForFuture() async {
        guard let planID, results == nil, !isCalculating(planID),
              plans.errors[planID] == nil else { return }
        await plans.run(planID)
    }

    private func isCalculating(_ plan: PlanID) -> Bool {
        plans.isRunning(plan, .base) || plans.isRunning(plan, .checkIn)
    }

    /// Above the chart without a projection: the
    /// main plan's calculation with its bar, why it can't run (with *Try
    /// Again* and *Open Plan*), or *Calculate*.
    @ViewBuilder
    private func futureStatus(_ plan: PlanID) -> some View {
        if let progress = plans.progress(of: plan, .base) ?? plans.progress(of: plan, .checkIn) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                HStack {
                    Text("Calculating \(planTitle)'s projection…")
                        .privacySensitiveInFeedback()
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
                    .privacySensitiveInFeedback()
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
                    .privacySensitiveInFeedback()
                Spacer(minLength: Metrics.s)
                Button("Calculate") { Task { await plans.run(plan) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .font(.subheadline)
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
        "The money in the plan by asset class, then \(planTitle)'s projection, in today's money."
    }

    /// The full explanation, in the ⓘ popover.
    private var futureDetail: String {
        "The past shows the money in your plan: the accounts your plans count, e.g. without your "
            + "home. That's what the projection is of, so the two meet at today; your accounts show your "
            + "whole net worth. After today the chart continues with \(planTitle)'s projection, in today's "
            + "money: the dashed line is the middle of the simulated futures, the darker band holds half of them "
            + "and the lighter band 8 in 10. The lighter band can run off the top, so the rest stays readable. "
            + "The projection is one total: it starts from what the plan's accounts add up to today, less any "
            + "debts below the zero line. The time span menu sets how far back and ahead the chart reaches."
    }
}
