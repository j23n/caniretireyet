import Model
import SwiftUI

/// Progress (UI.md, "Progress"; PROGRESS.md): how the answer moved from one
/// check-in to the next, and your actual numbers against a baseline.
struct PlanProgressView: View {
    let session: PlanSession
    var isWide = false
    /// Asks for a label and saves a baseline (the screen owns the alert).
    let onSaveBaseline: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @State private var selectedBaseline: BaselineID?

    private var answerHistory: PlanAnswerHistory {
        PlanAnswerHistory(library.library.headlines(for: session.planID))
    }

    private var baselines: [PlanBaselineEntry] {
        PlanBaselineComparison.baselines(for: session.planID, in: library.library)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                answerCard
                baselineCard
            }
            .padding(Metrics.l)
            .frame(maxWidth: isWide ? 1_000 : Metrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .onAppear {
            if selectedBaseline == nil { selectedBaseline = baselines.first?.id }
        }
    }

    // MARK: Your answer over time

    private var answerCard: some View {
        let history = answerHistory
        return Card {
            Text("Earliest retirement age at each check-in")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            PlanAnswerHistoryChart(history: history)
            if let latest = history.latestAge {
                HStack(spacing: Metrics.s) {
                    Text("\(latest) now")
                        .font(.subheadline.weight(.semibold))
                    if let change = history.change, change.years != 0 {
                        Text(changeText(change.years))
                            .font(.subheadline)
                            .monospacedDigit()
                            // An earlier age is good news.
                            .foregroundStyle(change.years < 0 ? Palette.positive : Palette.negative)
                        Text("since \(PlanResultsText.monthYear(change.since, locale: locale))")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
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
        } header: {
            SectionHeader("Your answer over time")
        }
    }

    /// "ahead of the median" or "behind the median".
    private static func side(of gap: Decimal) -> String {
        gap >= 0 ? "ahead of the median" : "behind the median"
    }

    /// "The same accounts as the baseline, in EUR of 31 Dec 2025."
    private func unitsNote(_ comparison: PlanBaselineComparison) -> String {
        comparison.unitsNote(baseCurrency: library.baseCurrency, locale: locale)
    }

    /// "▼ −3 years".
    private func changeText(_ years: Int) -> String {
        let arrow = years < 0 ? "▼" : "▲"
        let sign = years < 0 ? AmountFormat.minus : "+"
        let count = abs(years)
        return "\(arrow) \(sign)\(count) \(count == 1 ? "year" : "years")"
    }

    // MARK: Actual vs baseline

    private var shownBaseline: PlanBaselineEntry? {
        baselines.first { $0.id == selectedBaseline } ?? baselines.first
    }

    private var baselineCard: some View {
        Card {
            if let shown = shownBaseline {
                let comparison = PlanBaselineComparison(baseline: shown.baseline, library: library.library,
                                                        asOf: library.asOfDate)
                PlanFanLegend(showsActual: true)
                FanChart(fan: comparison.fan, actual: comparison.actual, currency: comparison.currency)
                if let position = comparison.position {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Metrics.xs) {
                            DeltaText(position.gap, currency: comparison.currency)
                                .font(.subheadline.weight(.semibold))
                            Text(Self.side(of: position.gap))
                                .font(.subheadline)
                        }
                        Text(PlanBaselineComparison.percentileText(position))
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                } else {
                    Text("Your actual numbers appear here after the next check-in.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Text(unitsNote(comparison))
                    .font(.caption)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("A baseline remembers what you expected. Save one now, and later see how reality compares. "
                    + "One is also saved at the first check-in of each year.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                onSaveBaseline()
            } label: {
                Label("Save baseline…", systemImage: "bookmark")
            }
            .buttonStyle(.bordered)
            .disabled(!library.canEdit)
        } header: {
            SectionHeader("Actual vs baseline") {
                if !baselines.isEmpty {
                    // Never nil while there are baselines: a nil selection has no tag.
                    Picker("Baseline", selection: Binding(get: { selectedBaseline ?? baselines.first?.id },
                                                          set: { selectedBaseline = $0 })) {
                        ForEach(baselines) { entry in
                            Text(PlanBaselineComparison.label(for: entry.baseline, locale: locale))
                                .tag(Optional(entry.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }
}

#Preview("Progress") {
    PlanPreviewHost(model: AppModel.preview(planEngine: PlanPreviewEngine())) { session in
        PlanProgressView(session: session, onSaveBaseline: {})
    }
}
