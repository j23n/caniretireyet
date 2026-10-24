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

/// A group's name above its card, as grouped lists write it: "ALONG THE
/// WAY, TYPICALLY", "IN THIS CHAPTER".
struct PlanPartLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            .textCase(.uppercase)
            .lineLimit(1)
            .padding(.horizontal, Metrics.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A month's money as one bar of parts, each as wide as its share of the
/// month: spent and saved while working, what pensions pay and what comes
/// from savings once retired, striped. The chapters' rows draw it thin; a
/// chapter's own card draws it with its words (``PlanMonthBarView``).
struct PlanChapterMoneyBar: View {
    let bar: PlanChapterStory.Bar
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Array(bar.segments.enumerated()), id: \.offset) { _, segment in
                    Self.fill(segment.role)
                        .frame(width: max(0, proxy.size.width * share(segment.value)))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func share(_ value: Double) -> CGFloat {
        let total = bar.total
        guard total > 0 else { return 0 }
        return CGFloat(min(1, max(0, value / total)))
    }

    /// A part's fill: what comes from savings is striped in orange.
    @ViewBuilder
    static func fill(_ role: PlanChapterStory.Bar.Role) -> some View {
        switch role {
        case .fromSavings:
            Rectangle()
                .fill(Palette.orange.opacity(0.3))
                .overlay { PlanStripes().fill(Palette.orange.opacity(0.75)) }
                .clipped()
        default:
            Rectangle()
                .fill(color(role))
        }
    }

    static func color(_ role: PlanChapterStory.Bar.Role) -> Color {
        switch role {
        case .spent, .pay: Palette.accent.opacity(0.45)
        case .saved: Palette.accent
        case .fromSavings: Palette.orange.opacity(0.6)
        case .tax: Palette.orangeStroke
        case .pensions: Palette.violet.opacity(0.55)
        case .spare: Palette.green
        }
    }
}

/// Diagonal stripes, for what comes from savings.
struct PlanStripes: Shape {
    /// From one stripe to the next.
    var spacing: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rise = rect.height
        var x = rect.minX - rise
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rise, y: rect.minY))
            path.addLine(to: CGPoint(x: x + rise + spacing / 2, y: rect.minY))
            path.addLine(to: CGPoint(x: x + spacing / 2, y: rect.maxY))
            path.closeSubpath()
            x += spacing
        }
        return path
    }
}

/// A month's money as a bar with its words under it, each on one line:
/// "Spent 3.000 €" on the left, "Saved 2.100 €" on the right.
struct PlanMonthBarView: View {
    let bar: PlanChapterStory.Bar

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlanChapterMoneyBar(bar: bar, height: 10)
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                AmountSentenceText(bar.leading)
                    .lineLimit(1)
                Spacer(minLength: Metrics.s)
                AmountSentenceText(bar.trailing)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: bar.label.spoken(hidesAmounts: redactionReasons.hidesAmounts)))
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
        case .bridge: Palette.orangeStroke
        case .pensions: Palette.violet
        case .later: Palette.violet.opacity(0.6)
        }
    }
}

/// A chapter's number, white in a circle of its colour; in the accent when
/// it's the chosen one.
struct PlanChapterBadge: View {
    let number: Int
    let style: PlanChaptersModel.Style
    var isSelected = false

    var body: some View {
        Text(verbatim: "\(number)")
            .font(.footnote.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .frame(width: 24, height: 24)
            .background(isSelected ? Palette.accent : PlanChapterColors.color(style), in: Circle())
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
