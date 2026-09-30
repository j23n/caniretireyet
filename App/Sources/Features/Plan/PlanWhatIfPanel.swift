import Model
import SwiftUI

/// What if… (UI.md, "What if"): sliders for retirement age, spending,
/// saving and equity return. Results follow as you drag, with fewer runs;
/// letting go runs them all. The headline shows the difference
/// ("Earliest 54 → 53"); *Keep* writes the change into the plan, *Reset*
/// throws it away. On iPhone it's a bottom sheet; on the Mac, in the inspector.
struct PlanWhatIfPanel: View {
    let session: PlanSession
    /// Shows the answer at the top (the iPhone sheet covers the headline).
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
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!session.canEdit)
                }
            }
            if showsAnswer {
                answer
            }
            if let model = session.whatIfModel {
                ForEach(PlanWhatIfSlider.allCases) { slider in
                    sliderRow(slider, model: model, value: binding(slider, $session))
                }
            }
            Text(footnote)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
        }
        #if os(iOS)
        // A light tap when a slider moves the earliest age (UI.md, "Haptics").
        .sensoryFeedback(.selection, trigger: session.shownResults?.headline.earliestAge)
        #endif
    }

    private var footnote: String {
        let runs = session.plan?.simulation.effectiveRuns ?? 2_000
        return "Fewer runs while you drag · all \(AmountFormat.number(Decimal(runs), locale: locale)) when you let go"
    }

    /// "Not yet · Earliest 54 → 53".
    private var answer: some View {
        HStack(spacing: Metrics.s) {
            if let results = session.shownResults {
                Text(PlanResultsText.answer(results.headline))
                    .font(.title3.weight(.bold))
                if let base = session.baseResults, session.hasWhatIf,
                   let change = PlanResultsText.change(from: base.headline.earliestAge,
                                                       to: results.headline.earliestAge) {
                    Text("Earliest \(change)")
                        .foregroundStyle(Palette.accent)
                } else if let age = results.headline.earliestAge {
                    Text("Earliest \(age)")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: 0)
            if session.isRunning {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .font(.subheadline.weight(.semibold))
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
            Slider(
                value: binding, in: model.range(slider), step: slider.step,
                onEditingChanged: { editing in session.setDragging(editing) })
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
