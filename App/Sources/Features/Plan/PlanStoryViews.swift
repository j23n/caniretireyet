import Model
import Planner
import SwiftUI
import Tracker

// The pieces the plan's words are made of (UI.md, "Plan"): sentences with
// their values in bold, a month's money as a bar, the futures as ten dots,
// each chapter's number in its colour, and the small editor a setting opens.

/// Sentences with their values in bold. They only read: values change in
/// the chapter's settings. The text wraps as text does.
struct PlanStoryText: View {
    let runs: [PlanChapterStory.Run]

    var body: some View {
        Text(attributed)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var text = AttributedString()
        for run in runs {
            switch run {
            case .text(let words):
                text += AttributedString(words)
            case .value(let words):
                var value = AttributedString(words)
                value.inlinePresentationIntent = .stronglyEmphasized
                text += value
            }
        }
        return text
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
                Text(bar.leading)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Metrics.s)
                Text(bar.trailing)
                    .fontWeight(.semibold)
                    .foregroundStyle(bar.trailingRole.map(Self.textColor) ?? Palette.secondaryInk)
            }
            .font(.footnote)
            .privacySensitive()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(bar.label))
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

/// The small editor a setting opens: the field, stepper or switch for that
/// one value. Edits apply at once, as everywhere in the plan.
struct PlanValueEditor: View {
    let value: PlanValue
    @Binding var plan: PlanDocument
    /// When work stops, for the retirement age.
    let model: PlanChaptersModel
    /// Goes back to the plan's own retirement age, when the charts are for another.
    var onUsePlanAge: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.baseCurrency) private var currency
    @Environment(LibraryStore.self) private var library
    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

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
        case .workingSpending:
            title("Spending while working")
            PlanNumberRow("A month", value: $plan.spending.working.perMonth, unit: "/month")
            if let spent = spentNote {
                note(spent)
            }
        case .retiredSpending:
            title("Spending in retirement")
            PlanNumberRow("A month", value: $plan.spending.retired.perMonth, unit: "/month")
            note("In \(PlanMoney.todaysMoney(currency)). Later phases spend a share of it.")
        case .retirementAge:
            title("When work stops")
            Toggle("As early as you can", isOn: $plan.planRetiresEarliest)
            if !plan.planRetiresEarliest {
                Stepper("At \(plan.planRetirementAge)", value: $plan.planRetirementAge, in: 30...85)
            }
            note(model.retirementNote)
            if let onUsePlanAge, model.ageSource == .chosen {
                Button("Plan's age") {
                    dismiss()
                    onUsePlanAge()
                }
                .buttonStyle(.borderless)
            }
        case .spendingPhase(let index):
            title("Later spending")
            PlanSpendingPhaseRow(phases: $plan.spending.phases, index: index)
            note("From an age, a share of what you spend in retirement.")
        case .endAge:
            title("The plan's end")
            Stepper("Plan to age \(plan.planEndAge)", value: $plan.planEndAge, in: 70...110)
        case .flexibleSpending:
            PlanFlexibleSpendingEditor(spending: $plan.spending)
        }
    }

    /// What the cash and savings accounts that record money in and out
    /// spent over the last twelve months, a month on average, to set the
    /// plan's spending against (PROGRESS.md, "Money in and out"); `nil`
    /// when nothing was recorded.
    private var spentNote: String? {
        let summary = library.valuator.moneyInOut(overYearEndingOn: .today())
        guard let perYear = summary.moneyOutPerYear else { return nil }
        let amount = hidesAmounts
            ? AmountFormat.hidden : AmountFormat.amount(perYear / 12, currency: summary.currency, locale: locale)
        let unconverted = summary.isComplete ? "" : " Values without an exchange rate are left out too."
        return "Your accounts recorded \(amount) a month on average going out in the last year, credit card "
            + "payments included. Money moved between them, such as loan and mortgage payments, is left out."
            + unconverted
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
