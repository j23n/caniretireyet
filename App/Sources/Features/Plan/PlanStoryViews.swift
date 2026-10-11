import Model
import Planner
import SwiftUI
import Tracker

// The pieces the plan's words are made of (UI.md, "Plan"): sentences with
// their values in bold, a month's money as a bar, the futures as ten dots,
// each chapter's number in its colour, and the small editor a setting opens.

/// Sentences with their values in bold. They only read: values change in
/// the chapter's settings. The text wraps as text does. While amounts are
/// hidden, each amount draws as a placeholder, and in a feedback screenshot
/// every word does (``AmountSentenceText``).
struct PlanStoryText: View {
    let runs: [PlanChapterStory.Run]

    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.hidesPersonalData) private var hidesPersonalData

    var body: some View {
        let hides = redactionReasons.hidesAmounts
        text(hidesAmounts: hides)
            .textRenderer(AmountPlaceholderRenderer(hidesAmounts: hides, hidesWords: hidesPersonalData))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Text(verbatim: sentence.spoken(hidesAmounts: hides)))
    }

    private func text(hidesAmounts: Bool) -> Text {
        var text = Text(verbatim: "")
        for run in runs {
            switch run {
            case .text(let words):
                text = Text("\(text)\(Text(sentence: words, hidesAmounts: hidesAmounts, hidesWords: hidesPersonalData))")
            case .value(let words):
                let value = Text(sentence: words, hidesAmounts: hidesAmounts, hidesWords: hidesPersonalData)
                text = Text("\(text)\(value.bold())")
            }
        }
        return text
    }

    private var sentence: AmountSentence {
        runs.reduce(AmountSentence()) { $0 + $1.sentence }
    }
}

/// A part's name in a chapter's words: "What happens", "A month".
struct PlanPartLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.secondaryInk)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A month's money as one bar, with its words under it ("Pay 4.500 € ·
/// spend 3.000 €" and "save 1.500 €"). Bars share `maximum`, so a month
/// in one chapter reads against another's.
struct PlanMonthBarView: View {
    let bar: PlanChapterStory.Bar
    /// The largest total of the bars shown together.
    let maximum: Double

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            PlanPartLabel("A month")
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(Array(bar.segments.enumerated()), id: \.offset) { _, segment in
                        Rectangle()
                            .fill(Self.color(segment.role))
                            .frame(width: max(2, proxy.size.width * share(segment.value)))
                    }
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                AmountSentenceText(bar.leading)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Metrics.s)
                AmountSentenceText(bar.trailing)
                    .fontWeight(.semibold)
                    .foregroundStyle(bar.trailingRole.map(Self.textColor) ?? Palette.secondaryInk)
            }
            .font(.footnote)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: bar.label.spoken(hidesAmounts: redactionReasons.hidesAmounts)))
    }

    private func share(_ value: Double) -> CGFloat {
        guard maximum > 0 else { return 0 }
        return CGFloat(min(1, max(0, value / maximum)))
    }

    static func color(_ role: PlanChapterStory.Bar.Role) -> Color {
        switch role {
        case .spent, .pay: Palette.gridline
        case .saved: Palette.accent
        case .fromSavings: Palette.orange
        case .tax: Palette.orangeStroke
        case .pensions: Palette.violet
        case .spare: Palette.green
        }
    }

    static func textColor(_ role: PlanChapterStory.Bar.Role) -> Color {
        switch role {
        case .spent, .pay: Palette.secondaryInk
        case .saved: Palette.accent
        case .fromSavings, .tax: Palette.orangeStroke
        case .pensions: Palette.violet
        case .spare: Palette.positive
        }
    }
}

/// Ten dots, `filled` of them in the hue: how many futures in 10 last.
struct PlanTenthsView: View {
    let filled: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<10, id: \.self) { index in
                Circle()
                    .fill(index < filled ? Palette.accent : Color.clear)
                    .overlay {
                        Circle().strokeBorder(index < filled ? Palette.accent : Palette.border, lineWidth: 1.5)
                    }
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(filled) in 10 futures"))
    }
}

/// The colours of a chapter's kind of life, on its card and badge.
enum PlanChapterColors {
    static func color(_ style: PlanChaptersModel.Style) -> Color {
        switch style {
        case .working: Palette.mutedInk
        case .notWorking: Palette.secondaryInk
        case .bridge: Palette.orange
        case .pensions: Palette.violet
        case .later: Palette.violet.opacity(0.55)
        }
    }
}

/// A chapter's number in a circle of its colour.
struct PlanChapterBadge: View {
    let number: Int
    let style: PlanChaptersModel.Style
    var isSelected = false

    var body: some View {
        Text(verbatim: "\(number)")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(isSelected ? Color.white : Palette.ink)
            .frame(width: 22, height: 22)
            .background(isSelected ? Palette.accent : PlanChapterColors.color(style).opacity(0.3), in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Changing a value

/// The small editor an age's setting opens: its stepper and switch. Edits
/// apply at once.
struct PlanValueEditor: View {
    let value: PlanValue
    @Binding var plan: PlanDocument
    /// When work stops, for the retirement age.
    let model: PlanChaptersModel
    /// Goes back to the plan's own retirement age, when the charts are for another.
    var onUsePlanAge: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            editor
        }
        .font(.subheadline)
        .padding(Metrics.l)
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 420, alignment: .leading)
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var editor: some View {
        switch value {
        case .retirementAge:
            title("When work stops")
            Toggle("As early as you can", isOn: $plan.planRetiresEarliest)
            if !plan.planRetiresEarliest {
                Stepper("At \(plan.planRetirementAge)", value: $plan.planRetirementAge, in: 30...85)
                    .personalControl()
            }
            note(model.retirementNote)
                .privacySensitiveInFeedback()
            if let onUsePlanAge, model.ageSource == .chosen {
                Button("Plan's age") {
                    dismiss()
                    onUsePlanAge()
                }
                .buttonStyle(.borderless)
            }
        case .endAge:
            title("The plan's end")
            Stepper("Plan to age \(plan.planEndAge)", value: $plan.planEndAge, in: 70...110)
                .personalControl()
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Palette.ink)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}
