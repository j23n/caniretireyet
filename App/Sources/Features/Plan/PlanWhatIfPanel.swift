import Model
import Planner
import SwiftUI

// What if (UI.md, "What if"): three levers on top of the plan, when you
// stop working, take-home pay while working and spending a month in
// retirement. Moving one moves your date: once the levers rest, a quick
// estimate runs, then every run, and the date and the chart follow. On
// iPhone a sheet, the levers over *With these levers*; on the Mac and iPad
// a card beside your date. *Apply to Base case* writes the levers into the
// plan, *Save as a New Plan…* keeps them as a plan of its own, *Reset*
// puts them back. The levers come with Plus: without it they rest, and
// *Move the Levers…* opens the paywall (UI.md, "Plus").

/// The three levers, each with its name and value over its slider, and
/// what the plan says under it ("As planned: 3.000 € in every retired
/// chapter.").
struct PlanLeverRows: View {
    let session: PlanSession

    @Environment(PlusStore.self) private var plus
    @Environment(\.locale) private var locale

    private var words: PlanWords { PlanWords(currency: session.currency, locale: locale) }

    var body: some View {
        if let model = session.whatIfModel {
            VStack(alignment: .leading, spacing: Metrics.l) {
                ForEach(PlanWhatIfSlider.allCases) { slider in
                    row(slider, model: model)
                }
            }
            #if os(iOS)
            // A light tap when the levers move the earliest age (UI.md, "Haptics").
            .sensoryFeedback(.selection, trigger: session.whatIfResults?.headline.earliestAge)
            #endif
        }
    }

    /// The lever's value in the session: the value shown, and moving it
    /// moves the what-if (``PlanSession/set(_:to:)``).
    private func binding(_ slider: PlanWhatIfSlider) -> Binding<Double> {
        Binding(get: { session.whatIfModel?.value(slider) ?? 0 }, set: { session.set(slider, to: $0) })
    }

    private func row(_ slider: PlanWhatIfSlider, model: PlanWhatIfModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(slider.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: Metrics.s)
                value(slider, model: model)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.isChanged(slider) ? Palette.accent : Palette.ink)
                    .lineLimit(1)
                    .fixedSize()
            }
            Slider(value: binding(slider), in: model.range(slider), step: slider.step)
                .disabled(!model.isAvailable(slider) || !session.canEdit || !plus.hasPlus)
                .accessibilityLabel(Text(slider.title))
            AmountSentenceText(planned(slider, model: model))
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The lever's value: the age, or "As early as you can"; the change in
    /// pay, or "As planned"; spending a month.
    @ViewBuilder
    private func value(_ slider: PlanWhatIfSlider, model: PlanWhatIfModel) -> some View {
        let number = model.value(slider)
        switch slider {
        case .retirementAge:
            if !model.isChanged(slider) && model.planRetiresEarliest {
                Text("As early as you can")
            } else {
                Text(verbatim: "\(Int(wholeNumber: number))")
                    .monospacedDigit()
                    .privacySensitiveInFeedback()
            }
        case .takeHome:
            if model.isChanged(slider) {
                AmountSentenceText(words.signedAmount(Decimal(wholeNumber: number)))
                    .monospacedDigit()
            } else if model.isAvailable(slider) {
                Text("As planned")
            } else {
                Text("No pay set")
                    .foregroundStyle(Palette.secondaryInk)
            }
        case .spending:
            AmountText(Decimal(wholeNumber: number), currency: session.currency)
        }
    }

    /// What the plan says, under the lever.
    private func planned(_ slider: PlanWhatIfSlider, model: PlanWhatIfModel) -> AmountSentence {
        switch slider {
        case .retirementAge:
            guard let age = model.planRetirementAge else { return "Once calculated, the plan's age." }
            return model.planRetiresEarliest ? "As planned: as early as you can, now \(age)."
                : AmountSentence("As planned: at \(age).")
        case .takeHome:
            let pay = model.planTakeHome
            guard !pay.isEmpty else { return "Set take-home pay in a working chapter to move it." }
            let change = model.whatIf.takeHomeChange ?? 0
            let list = pay.map { words.amount(max(0, $0 + change)) }.joined(separator: ", then ")
            return change == 0 ? "As planned: \(list) a month."
                : "A month, on top of each working chapter: \(list)."
        case .spending:
            return "As planned: \(words.monthly(model.planSpending)) in every retired chapter."
        }
    }
}

/// *Apply to Base case*, *Save as a New Plan…* and *Reset*, once a lever
/// has moved; *Move the Levers…* without Plus.
struct PlanLeverButtons: View {
    let session: PlanSession
    /// Called once the levers are applied or saved, e.g. to close the sheet.
    var onDone: () -> Void = {}

    @Environment(PlusStore.self) private var plus
    @State private var isNaming = false

    private var name: String { session.plan?.name ?? "the plan" }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            if session.hasWhatIf {
                Button {
                    session.applyWhatIf()
                    onDone()
                } label: {
                    Text("Apply to \(name)")
                        .frame(maxWidth: .infinity)
                        .privacySensitiveInFeedback()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!session.canEdit)
                Button {
                    plus.unlock(.morePlans) { isNaming = true }
                } label: {
                    Text("Save as a New Plan…")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!session.canEdit)
                Text("Apply writes the levers into the chapters: the pay into each working chapter, the "
                     + "spending into each retired one.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !plus.hasPlus {
                Button("Move the Levers…") { plus.unlock(.whatIf) {} }
                    .buttonStyle(.bordered)
            }
        }
        .planSaveAsPlan(session: session, isPresented: $isNaming, onSaved: onDone)
    }
}

/// What if on the Mac and iPad: a card beside your date, its title with
/// *Reset* and a spinner while the date updates, the levers, and their
/// buttons. The chart and the tiles on the page follow the levers.
struct PlanLeversCard: View {
    let session: PlanSession

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What if")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Move a lever and the chart follows.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
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
            PlanLeverRows(session: session)
            PlanLeverButtons(session: session)
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
    }
}

/// What if on iPhone, in a sheet: *The main levers* on a card, then *With
/// these levers*, what they do (``PlanChangeSummary``), and their buttons.
/// *Reset* puts them back; *Done* closes the sheet with the levers where
/// they are, so Ahead shows their date until they're reset.
struct PlanWhatIfSheet: View {
    let session: PlanSession

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.l) {
                    VStack(alignment: .leading, spacing: 6) {
                        PlanPartLabel("The main levers")
                        PlanLeverRows(session: session)
                            .padding(Metrics.l)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSurface()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        PlanPartLabel("With these levers")
                        PlanChangeSummary(session: session, changed: session.whatIfResults, document: session.shownPlan,
                                          isUpdating: session.whatIfIsOutOfDate || session.isRunningWhatIf,
                                          error: session.hasWhatIf ? session.runError : nil,
                                          label: "With the levers")
                    }
                    PlanLeverButtons(session: session) { dismiss() }
                }
                .padding(.horizontal, Metrics.l)
                .padding(.vertical, Metrics.s)
            }
            .background(Palette.page)
            .navigationTitle("What if")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { session.reset() }
                        .disabled(!session.hasWhatIf)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }
}

#Preview("What if") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        PlanWhatIfSheet(session: session)
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
