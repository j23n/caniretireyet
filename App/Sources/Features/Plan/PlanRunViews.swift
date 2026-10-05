import Model
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
    /// A title in place of "Calculating…", e.g. for one of two plans.
    var title: String?
    /// Stops the run; `nil` hides the button (a check-in's run goes on).
    var onCancel: (() -> Void)?

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(title ?? PlanRunText.title(progress, isCheckIn: isCheckIn))
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

/// "Out of date · Inputs changed since this was calculated", with the
/// button that brings the results up to date (Recalculate, Run What-If,
/// Calculate). Nothing when the results are current.
struct PlanOutOfDateBanner: View {
    let state: PlanResultsState
    let perform: (PlanResultsState.Action) -> Void

    var body: some View {
        if state.isOutOfDate, !state.isRunning,
           let message = PlanRunText.staleMessage(state.staleReasons, focusAge: state.focusAge) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Metrics.m) {
                    words(message)
                    Spacer(minLength: Metrics.s)
                    button
                }
                VStack(alignment: .leading, spacing: Metrics.s) {
                    words(message)
                    button
                }
            }
            .padding(Metrics.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.warning, lineWidth: 1)
            }
        }
    }

    private func words(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(Palette.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(PlanRunText.outOfDateTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var button: some View {
        if let action = state.action {
            Button {
                perform(action)
            } label: {
                Label(action.title, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Before the first calculation: the answer recorded at the last check-in,
/// dated, if there is one, a short explanation and Calculate.
struct PlanCalculatePrompt: View {
    let state: PlanResultsState
    /// The plan's number of runs, for the explanation.
    let runs: Int
    var isAvailable = true
    let calculate: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        Card("Can I retire yet?") {
            if case .recorded(let headline, let planChanged) = state.content {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text(PlanResultsText.answer(headline))
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Palette.ink)
                    Text(PlanResultsText.earliest(headline, locale: locale))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(PlanResultsText.confidence(headline.confidence))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                    if let recorded = PlanRunText.recorded(headline, planChanged: planChanged, locale: locale) {
                        Label(recorded, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(Palette.mutedInk)
                    }
                    Text(AboutText.disclaimer)
                        .font(.caption)
                        .foregroundStyle(Palette.mutedInk)
                }
                Text(PlanRunText.chartsNeedCalculation)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                Text(PlanRunText.calculateExplanation(runs: runs, locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isAvailable {
                Button {
                    calculate()
                } label: {
                    Label("Calculate", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}

#Preview("Progress") {
    VStack(spacing: Metrics.l) {
        Card {
            PlanRunProgressView(
                progress: PlanRunProgress(phase: .simulating, completed: 1_234, total: 2_000, fraction: 0.91),
                onCancel: {})
        }
        Card {
            PlanRunProgressView(
                progress: PlanRunProgress(phase: .earliestAge, completed: 12, total: 35, fraction: 0.3, ages: 41...75),
                isCheckIn: true)
        }
    }
    .padding()
    .background(Palette.page)
}
