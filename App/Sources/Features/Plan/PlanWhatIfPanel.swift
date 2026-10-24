import Model
import Planner
import SwiftUI

/// The levers (UI.md, "Plan"): when you stop working, spending and saving
/// a month, and what shares make above inflation, on top of the plan.
/// Moving one moves your date: once the levers rest, a quick estimate runs,
/// then every run, and the date follows. *Reset* puts them back; *Save as
/// Plan…* (here on iPhone, in the header row on the Mac and iPad) keeps
/// them where they are as a plan of its own. The levers and *Save as
/// Plan…* come with Plus: without it the sliders rest, and *Move the
/// Levers…* opens the paywall (UI.md, "Plus").
struct PlanLeversCard: View {
    let session: PlanSession

    @Environment(PlusStore.self) private var plus
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @State private var isNaming = false

    var body: some View {
        VStack(alignment: .leading, spacing: layout.isWide ? Metrics.m : Metrics.l) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text("Levers")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                if session.isRunningWhatIf {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Updating your date")
                }
                Spacer(minLength: Metrics.s)
                if session.hasWhatIf {
                    Button("Reset") { session.reset() }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                }
            }
            if let model = session.whatIfModel {
                ForEach(PlanWhatIfSlider.allCases) { slider in
                    sliderRow(slider, model: model, value: binding(slider))
                }
            }
            footer
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
        #if os(iOS)
        // A light tap when the levers move the earliest age (UI.md, "Haptics").
        .sensoryFeedback(.selection, trigger: session.shownResults?.headline.earliestAge)
        #endif
        .planSaveAsPlan(session: session, isPresented: $isNaming)
    }

    /// Under the levers: *Save as Plan…* once one has moved (iPhone), *Move
    /// the Levers…* without Plus, else how they work.
    @ViewBuilder
    private var footer: some View {
        if session.hasWhatIf {
            if !layout.isWide {
                HStack {
                    Spacer(minLength: 0)
                    Button("Save as Plan…") {
                        plus.unlock(.morePlans) { isNaming = true }
                    }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                    .disabled(!session.canEdit)
                }
            }
        } else if !plus.hasPlus {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
                Text("Move a lever and your date follows.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Move the Levers…") { plus.unlock(.whatIf) {} }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
                    .fixedSize()
            }
        } else {
            Text("Move a lever and your date follows.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The lever's value in the session: the value shown, and moving it
    /// moves the what-if (``PlanSession/set(_:to:)``).
    private func binding(_ slider: PlanWhatIfSlider) -> Binding<Double> {
        Binding(get: { session.whatIfModel?.value(slider) ?? 0 }, set: { session.set(slider, to: $0) })
    }

    /// A lever: its name and value on one line, the slider under them. On
    /// the Mac and iPad the value sits in a field-like box.
    private func sliderRow(_ slider: PlanWhatIfSlider, model: PlanWhatIfModel, value binding: Binding<Double>)
        -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(slider.title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: Metrics.s)
                value(slider, model: model)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.isChanged(slider) ? Palette.accent : Palette.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, layout.isWide ? 6 : 0)
                    .padding(.vertical, layout.isWide ? 2 : 0)
                    .frame(minWidth: layout.isWide ? 56 : nil, alignment: .trailing)
                    .background(layout.isWide ? Palette.page : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            Slider(value: binding, in: model.range(slider), step: slider.step)
                .disabled(!model.isAvailable(slider) || !session.canEdit || !plus.hasPlus)
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
                .privacySensitiveInFeedback()
        case .spending, .saving:
            if model.isAvailable(slider) {
                AmountText(Decimal(wholeNumber: number))
            } else {
                Text("Once calculated")
                    .foregroundStyle(Palette.secondaryInk)
            }
        case .equityReturn:
            Text(AmountFormat.percent(number, digits: 2, locale: locale))
                .monospacedDigit()
                .privacySensitiveInFeedback()
        }
    }
}

#Preview("Levers") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        ScrollView {
            PlanLeversCard(session: session)
                .padding()
        }
        .background(Palette.page)
    }
}
