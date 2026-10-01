import Model
import SwiftUI

/// Comparing two plans (UI.md, "Comparing two plans"): both headlines, both
/// success curves on one chart with direct labels, and a table of key
/// numbers: net income in a chosen year, public pensions, lifetime taxes,
/// earliest retirement. The screen for regime decisions. A pushed page on
/// iPhone and in the Mac's plan stack.
///
/// Like the Plan screen it runs nothing on its own: one *Calculate* runs
/// both plans that need it, one after the other, with their progress and
/// *Cancel*; results out of date are dimmed and say so.
struct PlanCompareScreen: View {
    let firstID: PlanID

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(\.locale) private var locale
    @State private var secondID: PlanID?
    @State private var year: Int?
    @State private var calculation: Task<Void, Never>?
    /// The plan being calculated, and how many are, for "Base case (1 of 2)".
    @State private var calculating: (plan: PlanID, index: Int, count: Int)?

    init(firstID: PlanID, secondID: PlanID? = nil) {
        self.firstID = firstID
        _secondID = State(initialValue: secondID)
    }

    /// The other plan: the one chosen, else the first other plan.
    private var otherID: PlanID? {
        secondID ?? library.sortedPlans.first { $0.id != firstID }?.id
    }

    private var data: PlanComparisonData? {
        guard let first = library.library.plans[firstID], let otherID,
              let second = library.library.plans[otherID] else { return nil }
        return PlanComparisonData(first: side(first), second: side(second))
    }

    private func side(_ plan: PlanDocument) -> PlanComparisonData.Side {
        PlanComparisonData.Side(
            plan: plan, results: plans.results[plan.id], staleReasons: plans.staleReasons(of: plan.id),
            recorded: plans.recordedHeadlines(for: plan.id).last.map { PlanHeadline(recorded: $0) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                if let data {
                    content(data)
                } else {
                    ContentUnavailableView {
                        Label("Nothing to compare yet", systemImage: "square.split.2x1")
                    } description: {
                        Text("Duplicate this plan and change one thing, e.g. forfettario instead of ordinario, "
                            + "to see both side by side.")
                    }
                }
            }
            .padding(Metrics.l)
            .frame(maxWidth: 1_000)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .navigationTitle("Compare plans")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                picker
            }
        }
        .task(id: otherID) {
            // Results the engine kept for the plans as they are: no runs.
            await plans.adoptCached(firstID)
            if let otherID { await plans.adoptCached(otherID) }
        }
    }

    // MARK: Calculating

    /// One Calculate for both plans: their progress, or the button.
    @ViewBuilder
    private func calculateCard(_ data: PlanComparisonData) -> some View {
        if let calculating {
            let progress = plans.progress(of: calculating.plan, .base)
                ?? plans.progress(of: calculating.plan, .checkIn) ?? .starting(.full)
            Card {
                PlanRunProgressView(progress: progress, title: calculatingTitle(calculating),
                                    onCancel: { cancel() })
            }
        } else if !data.plansToCalculate.isEmpty, plans.isAvailable {
            Card {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Metrics.m) {
                        calculateWords(data)
                        Spacer(minLength: Metrics.s)
                        calculateButton(data)
                    }
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        calculateWords(data)
                        calculateButton(data)
                    }
                }
            }
        }
    }

    private func calculateWords(_ data: PlanComparisonData) -> some View {
        let names = data.plansToCalculate.compactMap { library.library.plans[$0]?.name }
        let outOfDate = [data.first, data.second].contains { $0.results != nil && !$0.staleReasons.isEmpty }
        return VStack(alignment: .leading, spacing: 2) {
            if outOfDate {
                Label(PlanRunText.outOfDateTitle, systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.warning)
            }
            Text("Calculates \(PlanResultsText.list(names)) with their inputs and your latest data.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func calculateButton(_ data: PlanComparisonData) -> some View {
        Button {
            calculate(data.plansToCalculate)
        } label: {
            Label(data.calculateTitle, systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
    }

    /// "Calculating Base case (1 of 2)…".
    private func calculatingTitle(_ calculating: (plan: PlanID, index: Int, count: Int)) -> String {
        let name = library.library.plans[calculating.plan]?.name ?? calculating.plan.rawValue
        let of = calculating.count > 1 ? " (\(calculating.index + 1) of \(calculating.count))" : ""
        return "Calculating \(name)\(of)…"
    }

    /// Runs `ids` one after the other.
    private func calculate(_ ids: [PlanID]) {
        calculation?.cancel()
        calculation = Task {
            for (index, id) in ids.enumerated() {
                calculating = (id, index, ids.count)
                await plans.run(id)
                if Task.isCancelled { break }
            }
            calculating = nil
        }
    }

    private func cancel() {
        calculation?.cancel()
        calculation = nil
        if let calculating { plans.cancel(calculating.plan) }
        calculating = nil
    }

    /// Chooses the other plan.
    private var picker: some View {
        Menu {
            ForEach(library.sortedPlans.filter { $0.id != firstID }) { plan in
                Button {
                    secondID = plan.id
                } label: {
                    if plan.id == otherID {
                        Label(plan.name, systemImage: "checkmark")
                    } else {
                        Text(plan.name)
                    }
                }
            }
        } label: {
            Label("Compare with", systemImage: "square.split.2x1")
        }
    }

    @ViewBuilder
    private func content(_ data: PlanComparisonData) -> some View {
        calculateCard(data)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Metrics.l) {
                headline(data.first, color: .series(0))
                headline(data.second, color: .series(1))
            }
            VStack(spacing: Metrics.l) {
                headline(data.first, color: .series(0))
                headline(data.second, color: .series(1))
            }
        }
        if let threshold = data.first.results?.headline.confidence ?? data.second.results?.headline.confidence {
            Card("Chance of success by retirement age") {
                SuccessCurveChart(series: data.series, threshold: threshold, height: 240)
            }
            .opacity(dims(data) ? 0.6 : 1)
        }
        Card {
            table(data)
                .opacity(dims(data) ? 0.6 : 1)
        } header: {
            SectionHeader("Key numbers") {
                if !data.years.isEmpty {
                    Menu {
                        ForEach(data.years, id: \.self) { value in
                            Button(String(value)) { year = value }
                        }
                    } label: {
                        Text("Net income in \(String(year ?? data.defaultYear ?? 0))")
                    }
                    .fixedSize()
                }
            }
        }
    }

    /// Whether the charts and table are dimmed: a plan is being calculated,
    /// or its results are out of date.
    private func dims(_ data: PlanComparisonData) -> Bool {
        calculating != nil || [data.first, data.second].contains { $0.results != nil && !$0.staleReasons.isEmpty }
    }

    private func headline(_ side: PlanComparisonData.Side, color: ChartColor) -> some View {
        Card {
            HStack(spacing: Metrics.s) {
                Circle()
                    .fill(Palette.stroke(for: color))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(side.plan.name)
                    .font(.headline)
                Spacer(minLength: Metrics.s)
                if let progress = plans.progress(of: side.plan.id, .base) {
                    Text(PlanRunText.overall(progress, locale: locale))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                } else if side.results != nil, !side.staleReasons.isEmpty {
                    Label(PlanRunText.outOfDateTitle, systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(Palette.warning)
                }
            }
            if let headline = side.results?.headline ?? side.recorded {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text(PlanResultsText.answer(headline))
                        .font(.title.weight(.bold))
                    Text(PlanResultsText.earliest(headline, locale: locale))
                        .font(.subheadline.weight(.semibold))
                    Text(PlanResultsText.confidence(headline.confidence))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                    if side.results == nil, let recorded = PlanRunText.recorded(headline, planChanged: false,
                                                                                  locale: locale) {
                        Text(recorded)
                            .font(.caption)
                            .foregroundStyle(Palette.mutedInk)
                    }
                }
                .opacity(side.results != nil && side.staleReasons.isEmpty ? 1 : 0.6)
            } else if let error = plans.errors[side.plan.id] {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                Text("Not calculated yet.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    private func table(_ data: PlanComparisonData) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Metrics.l, verticalSpacing: Metrics.s) {
            GridRow {
                Text("")
                Text(data.first.plan.name)
                    .font(.subheadline.weight(.semibold))
                    .gridColumnAlignment(.trailing)
                Text(data.second.plan.name)
                    .font(.subheadline.weight(.semibold))
                    .gridColumnAlignment(.trailing)
            }
            Divider()
            ForEach(Array(data.rows(year: year ?? data.defaultYear).indices), id: \.self) { index in
                let row = data.rows(year: year ?? data.defaultYear)[index]
                GridRow {
                    Text(row.label)
                        .foregroundStyle(Palette.secondaryInk)
                    PlanFigureText(figure: row.values.first ?? .missing)
                    PlanFigureText(figure: row.values.dropFirst().first ?? .missing)
                }
            }
        }
        .font(.subheadline)
    }
}

#Preview("Compare") {
    NavigationStack {
        PlanCompareScreen(firstID: "base")
    }
    .previewEnvironment(model: AppModel.preview(planEngine: PlanPreviewEngine()))
}
