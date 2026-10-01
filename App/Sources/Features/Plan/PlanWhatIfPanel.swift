import Model
import SwiftUI

/// What if… (UI.md, "What if"): sliders for retirement age, spending,
/// saving and equity return. Moving one runs nothing: the answer next to
/// the sliders says it's from before the change until *Run What-If* runs
/// a quick estimate with fewer runs, then every run. The headline then
/// shows the difference ("Earliest 54 → 53"); *Keep* writes the change into
/// the plan, *Reset* throws it away. On iPhone it's a bottom sheet; on the
/// Mac, in the inspector.
struct PlanWhatIfPanel: View {
    let session: PlanSession
    /// Shows the answer at the top even without a what-if (the iPhone sheet
    /// covers the headline).
    var showsAnswer = false

    @Environment(\.locale) private var locale

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("What if…")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Metrics.s)
                if session.hasWhatIf {
                    Button("Reset") { session.reset() }
                        .buttonStyle(.borderless)
                    Button("Keep") { session.keep() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!session.canEdit)
                }
            }
            if showsAnswer || session.hasWhatIf {
                answer
            }
            if let model = session.whatIfModel {
                ForEach(PlanWhatIfSlider.allCases) { slider in
                    sliderRow(slider, model: model, value: binding(slider, $session))
                }
            }
            run
            Text(footnote)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        #if os(iOS)
        // A light tap when a what-if run moves the earliest age (UI.md, "Haptics").
        .sensoryFeedback(.selection, trigger: session.shownResults?.headline.earliestAge)
        #endif
    }

    private var footnote: String {
        let runs = session.plan?.simulation.effectiveRuns ?? 2_000
        return "Moving a slider runs nothing. Run What-If gives a quick estimate, then all "
            + "\(AmountFormat.number(Decimal(runs), locale: locale)) runs."
    }

    /// Run What-If while the what-if is out of date; its progress while it runs.
    @ViewBuilder
    private var run: some View {
        if session.isRunningWhatIf, let progress = session.runProgress {
            PlanRunProgressView(progress: progress, onCancel: { session.cancel() })
        } else if session.whatIfIsOutOfDate {
            Button {
                session.runWhatIf()
            } label: {
                Label("Run What-If", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(session.isRunning)
        }
    }

    /// "Not yet · Earliest 54 → 53", or the answer from before the change.
    private var answer: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Metrics.s) {
                if let results = session.shownResults {
                    Text(PlanResultsText.answer(results.headline))
                        .font(.title3.weight(.bold))
                    if let change {
                        Text("Earliest \(change)")
                            .foregroundStyle(Palette.accent)
                    } else if let age = results.headline.earliestAge {
                        Text("Earliest \(age)")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                } else {
                    Text("No answer yet")
                        .foregroundStyle(Palette.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            if session.whatIfIsOutOfDate {
                Label(PlanRunText.beforeWhatIf, systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "54 → 53" when the what-if's own results move the earliest age.
    private var change: String? {
        guard session.hasWhatIf, !session.whatIfIsOutOfDate, session.baseIsUpToDate,
              let base = session.baseResults, let results = session.shownResults else { return nil }
        return PlanResultsText.change(from: base.headline.earliestAge, to: results.headline.earliestAge)
    }

    /// The slider's value in the session.
    private func binding(_ slider: PlanWhatIfSlider, _ session: Bindable<PlanSession>) -> Binding<Double> {
        switch slider {
        case .retirementAge: session.whatIfRetirementAge
        case .spending: session.whatIfSpending
        case .saving: session.whatIfSaving
        case .equityReturn: session.whatIfEquityReturn
        }
    }

    private func sliderRow(_ slider: PlanWhatIfSlider, model: PlanWhatIfModel, value binding: Binding<Double>)
        -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(slider.title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Metrics.s)
                value(slider, model: model)
                    .font(.subheadline.weight(model.isChanged(slider) ? .semibold : .regular))
                    .foregroundStyle(model.isChanged(slider) ? Palette.accent : Palette.ink)
            }
            Slider(value: binding, in: model.range(slider), step: slider.step)
                .disabled(!model.isAvailable(slider))
                .accessibilityLabel(Text(slider.title))
        }
    }

    @ViewBuilder
    private func value(_ slider: PlanWhatIfSlider, model: PlanWhatIfModel) -> some View {
        let number = model.value(slider)
        switch slider {
        case .retirementAge:
            Text("\(Int(number.rounded()))")
                .monospacedDigit()
        case .spending:
            HStack(spacing: 2) {
                AmountText(Decimal(Int(number.rounded())))
                Text("/yr")
            }
        case .saving:
            if model.isAvailable(.saving) {
                AmountText(Decimal(Int(number.rounded())))
            } else {
                Text("–")
            }
        case .equityReturn:
            Text(AmountFormat.percent(number, digits: 2, locale: locale))
                .monospacedDigit()
        }
    }
}

#Preview("What if") {
    PlanPreviewHost(model: AppModel.preview(planEngine: PlanPreviewEngine())) { session in
        ScrollView {
            PlanWhatIfPanel(session: session, showsAnswer: true)
                .padding()
        }
    }
}
