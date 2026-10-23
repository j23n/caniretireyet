import Glance
import Model
import Planner
import SwiftUI

// The pieces of the results area that say where a calculation is and
// whether the results are current (UI.md, "Calculating" and "Out of
// date"), shared by the Plan screen and the check-in's confirmation. Their words come from `PlanRunText`.

/// A run in progress: what it's doing with that phase's bar ("Simulating
/// 1.234 / 2.000 runs"), the whole run's bar, and Cancel.
struct PlanRunProgressView: View {
    let progress: PlanRunProgress
    /// A check-in's run, recording the month's answer.
    var isCheckIn = false
    /// Stops the run; `nil` hides the button (a check-in's run goes on).
    var onCancel: (() -> Void)?

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(PlanRunText.title(progress, isCheckIn: isCheckIn))
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Metrics.s)
                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(PlanRunText.phase(progress, locale: locale))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .privacySensitiveInFeedback()
                ProgressView(value: progress.phaseFraction, total: 1)
                    .tint(Palette.accent)
            }
            VStack(alignment: .leading, spacing: Metrics.xs) {
                HStack {
                    Text("Overall")
                    Spacer(minLength: Metrics.s)
                    Text(PlanRunText.overall(progress, locale: locale))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                ProgressView(value: min(1, max(0, progress.fraction)), total: 1)
                    .tint(Palette.secondaryInk)
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(PlanRunText.accessibility(progress, isCheckIn: isCheckIn, locale: locale)))
    }
}

#Preview("Progress") {
    VStack(spacing: Metrics.l) {
        Card {
            PlanRunProgressView(
                progress: PlanRunProgress(mode: .full, planner: PlannerProgress(
                    phase: .simulating, completed: 1_234, total: 2_000, fraction: 0.91, runs: 2_000)),
                onCancel: {})
        }
        Card {
            PlanRunProgressView(
                progress: PlanRunProgress(mode: .full, planner: PlannerProgress(
                    phase: .earliestAge, completed: 12, total: 35, fraction: 0.3, ages: 41...75, runs: 2_000)),
                isCheckIn: true)
        }
    }
    .padding()
    .background(Palette.page)
}
