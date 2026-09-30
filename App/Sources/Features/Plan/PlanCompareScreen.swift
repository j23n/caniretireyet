import Model
import SwiftUI

/// Comparing two plans (UI.md, "Comparing two plans"): both headlines, both
/// success curves on one chart with direct labels, and a table of key
/// numbers: net income in a chosen year, public pensions, lifetime taxes,
/// earliest retirement. The screen for regime decisions. A pushed page on
/// iPhone and in the Mac's plan stack.
struct PlanCompareScreen: View {
    let firstID: PlanID

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(\.locale) private var locale
    @State private var secondID: PlanID?
    @State private var year: Int?

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
        return PlanComparisonData(first: .init(plan: first, results: plans.results[firstID]),
                                  second: .init(plan: second, results: plans.results[otherID]))
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
            await plans.run(firstID)
            if let otherID { await plans.run(otherID) }
        }
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
        }
        Card {
            table(data)
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

    private func headline(_ side: PlanComparisonData.Side, color: ChartColor) -> some View {
        Card {
            HStack(spacing: Metrics.s) {
                Circle()
                    .fill(Palette.color(for: color))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(side.plan.name)
                    .font(.headline)
            }
            if let results = side.results {
                Text(PlanResultsText.answer(results.headline))
                    .font(.title.weight(.bold))
                Text(PlanResultsText.earliest(results.headline, locale: locale))
                    .font(.subheadline.weight(.semibold))
                Text(PlanResultsText.confidence(results.headline.confidence))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            } else if plans.isRunning(side.plan.id) {
                HStack(spacing: Metrics.s) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running…")
                        .foregroundStyle(Palette.secondaryInk)
                }
            } else if let error = plans.errors[side.plan.id] {
                Text(error)
                    .font(.footnote)
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
