import Model
import SwiftUI

/// What if… (UI.md, "What if"): try a change before making it in the
/// plan. The plan's answer now, then sliders for when you stop working,
/// spending and saving a month, and what shares make above inflation.
/// Moving one runs nothing: the answer says it's from before the change
/// until *Run What If* runs a quick estimate with fewer runs, then every
/// run. The answer then shows the difference ("Earliest 54 → 53"); *Keep*
/// writes the change into the plan, *Reset* throws it away. On iPhone it's
/// a bottom sheet; on the Mac and iPad, a column beside the plan.
struct PlanWhatIfPanel: View {
    let session: PlanSession

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("What if")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Try a change before you make it in the plan.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            answer
            if let model = session.whatIfModel {
                ForEach(PlanWhatIfSlider.allCases) { slider in
                    sliderRow(slider, model: model, value: binding(slider))
                }
            }
            actions
            Text("A quick estimate first, then the full answer.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(iOS)
        // A light tap when a what-if run moves the earliest age (UI.md, "Haptics").
        .sensoryFeedback(.selection, trigger: session.shownResults?.headline.earliestAge)
        #endif
    }

    /// *Run What If* and *Reset*, and *Keep* once there's a change; the
    /// run's progress while it runs.
    @ViewBuilder
    private var actions: some View {
        if session.isRunningWhatIf, let progress = session.runProgress {
            PlanRunProgressView(progress: progress, onCancel: { session.cancel() })
        } else {
            HStack(spacing: Metrics.m) {
                Button("Run What If") { session.runWhatIf() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.whatIfIsOutOfDate || session.isRunning)
                Button("Reset") { session.reset() }
                    .buttonStyle(.borderless)
                    .disabled(!session.hasWhatIf)
                Spacer(minLength: 0)
                if session.hasWhatIf {
                    Button("Keep") { session.keep() }
                        .buttonStyle(.bordered)
                        .disabled(!session.canEdit)
                }
            }
        }
    }

    /// "Your plan now · Not yet. Stop at 63.", or with the what-if's
    /// difference once it has run.
    private var answer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(answerTitle)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            if let results = session.shownResults {
                Text(Self.answerText(results.headline))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let change {
                    Text("Earliest \(change)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.accent)
                }
            } else {
                Text("No answer yet")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.page, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// What the answer is: the plan's own, the what-if's, or from before its changes.
    private var answerTitle: String {
        guard session.hasWhatIf else { return "Your plan now" }
        return session.whatIfIsOutOfDate ? PlanRunText.beforeWhatIf : "With your changes"
    }

    /// "Not yet. Stop at 63.", "Yes. You could stop today."
    static func answerText(_ headline: PlanHeadline) -> String {
        if headline.canRetireNow { return "Yes. You could stop today." }
        guard let age = headline.earliestAge else { return "Not yet. No age reaches your bar yet." }
        return "Not yet. Stop at \(age)."
    }

    /// "54 → 53" when the what-if's own results move the earliest age.
    private var change: String? {
        guard session.hasWhatIf, !session.whatIfIsOutOfDate, session.baseIsUpToDate,
              let base = session.baseResults, let results = session.shownResults else { return nil }
        return PlanResultsText.change(from: base.headline.earliestAge, to: results.headline.earliestAge)
    }

    /// The slider's value in the session: the value shown, and moving it
    /// moves the what-if (``PlanSession/set(_:to:)``).
    private func binding(_ slider: PlanWhatIfSlider) -> Binding<Double> {
        Binding(get: { session.whatIfModel?.value(slider) ?? 0 }, set: { session.set(slider, to: $0) })
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
                    .font(.subheadline.weight(.semibold))
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
            Text("\(Int(wholeNumber: number))")
                .monospacedDigit()
        case .spending, .saving:
            if model.isAvailable(slider) {
                HStack(spacing: 4) {
                    AmountText(Decimal(wholeNumber: number))
                    Text("a month")
                }
            } else {
                Text("After Calculate")
                    .foregroundStyle(Palette.secondaryInk)
            }
        case .equityReturn:
            Text("\(AmountFormat.percent(number, digits: 2, locale: locale)) a year")
                .monospacedDigit()
        }
    }
}

#Preview("What if") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        ScrollView {
            PlanWhatIfPanel(session: session)
                .padding()
        }
    }
}
