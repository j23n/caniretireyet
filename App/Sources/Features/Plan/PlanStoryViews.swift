import Model
import Planner
import SwiftUI

// The pieces the plan's words are made of (UI.md, "Plan"): sentences whose
// values you change where they read, a month's money as a bar, the futures
// as ten dots, and each chapter's number in its colour.

/// Sentences with values to change: each value reads in the hue on a light
/// wash, and tapping it hands its ``PlanToken`` to `onToken`. The text wraps
/// as text does; VoiceOver reads it whole, with each value as a link.
struct PlanStoryText: View {
    let runs: [PlanChapterStory.Run]
    var onToken: (PlanToken) -> Void = { _ in }

    private static let scheme = "plan-token"

    var body: some View {
        Text(attributed)
            .fixedSize(horizontal: false, vertical: true)
            .tint(Palette.accent)
            .environment(\.openURL, OpenURLAction { url in
                if let token = token(for: url) { onToken(token) }
                return .handled
            })
    }

    private var attributed: AttributedString {
        var text = AttributedString()
        for run in runs {
            switch run {
            case .text(let words):
                text += AttributedString(words)
            case .token(let words, let token):
                var value = AttributedString(words)
                value.link = URL(string: "\(Self.scheme):\(token.id)")
                value.foregroundColor = Palette.accent
                value.backgroundColor = Palette.accent.opacity(0.1)
                value.inlinePresentationIntent = .stronglyEmphasized
                text += value
            }
        }
        return text
    }

    private func token(for url: URL) -> PlanToken? {
        guard url.scheme == Self.scheme else { return nil }
        let id = String(url.absoluteString.dropFirst(Self.scheme.count + 1))
        for case .token(_, let token) in runs where token.id == id {
            return token
        }
        return nil
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
            Text("Each month")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.secondaryInk)
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
    var size: CGFloat = 9

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<10, id: \.self) { index in
                Circle()
                    .fill(index < filled ? Palette.accent : Color.clear)
                    .overlay {
                        Circle().strokeBorder(index < filled ? Palette.accent : Palette.border, lineWidth: 1.5)
                    }
                    .frame(width: size, height: size)
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

/// The small editor a value in the plan's words opens: the field, stepper
/// or switch for that one value, and for an item a way to its whole sheet.
/// Edits apply at once, as everywhere in the plan.
struct PlanTokenEditor: View {
    let token: PlanToken
    @Binding var plan: PlanDocument
    /// When work stops, for the retirement age.
    var model: PlanChaptersModel?
    /// Opens an item's sheet (or the target mix's).
    var onOpen: (PlanToken) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.baseCurrency) private var currency

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            editor
            if let more = moreToken {
                Button(moreTitle) {
                    dismiss()
                    onOpen(more)
                }
                .buttonStyle(.borderless)
            }
        }
        .font(.subheadline)
        .padding(Metrics.l)
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 420, alignment: .leading)
        .presentationDetents([.medium])
    }

    // MARK: The editors

    @ViewBuilder
    private var editor: some View {
        switch token {
        case .workIncome(let index):
            title("Take-home pay")
            PlanNumberRow("A month", value: monthly($plan.work[planSafe: index, default: workFallback(index)].netIncome),
                          unit: "/month")
            note("After income tax and social contributions, in \(PlanMoney.todaysMoney(currency)).")
        case .workGrowth(let index):
            title("Pay growth")
            PlanNumberRow("Above inflation", value: $plan.work[planSafe: index, default: workFallback(index)].realGrowth,
                          kind: .percent, unit: "%/yr", prompt: "0")
        case .workingSpending:
            title("Spending while working")
            PlanNumberRow("A month", value: monthly($plan.spending.working), unit: "/month")
        case .retiredSpending:
            title("Spending in retirement")
            PlanNumberRow("A month", value: monthly($plan.spending.retired), unit: "/month")
            note("In \(PlanMoney.todaysMoney(currency)). Later phases spend a share of it.")
        case .retirementAge:
            title("When work stops")
            Toggle("As early as you can", isOn: $plan.planRetiresEarliest)
            if !plan.planRetiresEarliest {
                Stepper("At \(plan.planRetirementAge)", value: $plan.planRetirementAge, in: 30...85)
            }
            if let model { note(model.retirementNote) }
        case .pensionAmount(let index):
            title(pensionName(index))
            PlanNumberRow("A month, after tax",
                          value: monthly($plan.pensions[planSafe: index, default: pensionFallback(index)].perYear),
                          unit: "/month")
            note("From your pension statement, after the tax you expect to pay on it.")
        case .pensionAge(let index):
            title(pensionName(index))
            Stepper("Paid from \(pensionAge(index))",
                    value: $plan.pensions[planSafe: index, default: pensionFallback(index)].planFromAge, in: 40...90)
        case .contributionAmount(let index):
            title("Contribution")
            if contributionIsOneOff(index) {
                PlanNumberRow("Once", value: $plan.contributions[planSafe: index,
                                                                   default: contributionFallback(index)].planAmount)
            } else {
                PlanNumberRow("A month", value: monthly($plan.contributions[planSafe: index,
                                                                            default: contributionFallback(index)].perYear),
                              unit: "/month")
            }
        case .eventAmount(let index):
            title(eventName(index))
            PlanNumberRow("Amount", value: $plan.events[planSafe: index, default: eventFallback(index)].planSize)
        case .eventWhen(let index):
            title(eventName(index))
            eventWhen(index)
        case .eventProbability(let index):
            title(eventName(index))
            PlanNumberRow("Chance it happens",
                          value: $plan.events[planSafe: index, default: eventFallback(index)].planProbability,
                          kind: .percent, unit: "%")
        case .spendingPhase(let index):
            title("Later spending")
            PlanSpendingPhaseRow(phases: $plan.spending.phases, index: index)
            note("From an age, a share of what you spend in retirement.")
        case .endAge:
            title("The plan's end")
            Stepper("Plan to age \(plan.planEndAge)", value: $plan.planEndAge, in: 70...110)
        case .flexibleSpending:
            PlanFlexibleSpendingEditor(spending: $plan.spending)
        case .inflation:
            title("Inflation")
            PlanNumberRow("A year", value: $plan.assumptions.inflation, kind: .percent, unit: "%", prompt: "2")
        case .equityReturn:
            title("Shares")
            PlanNumberRow("Typical year, above inflation", value: $plan.assumptions[planMedianReal: .equity],
                          kind: .percent, unit: "%")
            note(PlanEditing.returnsExplanation)
        case .bondsReturn:
            title("Bonds")
            PlanNumberRow("Typical year, above inflation", value: $plan.assumptions[planMedianReal: .bonds],
                          kind: .percent, unit: "%")
            note(PlanEditing.returnsExplanation)
        case .investmentTax, .wealthTax:
            title("Taxes")
            PlanTaxesEditor(plan: $plan)
        case .confidence:
            title("When a plan works")
            PlanSimulationEditor(plan: $plan)
        case .targetMix, .work, .pension, .contribution, .event:
            EmptyView()
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

    @ViewBuilder
    private func eventWhen(_ index: Int) -> some View {
        let event = $plan.events[planSafe: index, default: eventFallback(index)]
        Picker("Set by", selection: event.planByAge) {
            Text("Age").tag(true)
            Text("Year").tag(false)
        }
        .pickerStyle(.segmented)
        let byAge = event.wrappedValue.planByAge
        let label: String = byAge ? "At \(event.wrappedValue.planWhen)" : "In \(String(event.wrappedValue.planWhen))"
        Stepper(label, value: event.planWhen, in: byAge ? 18...110 : 2_000...2_150)
    }

    // MARK: An item's sheet

    /// The item whose whole sheet the editor offers.
    private var moreToken: PlanToken? {
        switch token {
        case .workIncome(let index), .workGrowth(let index): .work(index)
        case .pensionAmount(let index), .pensionAge(let index): .pension(index)
        case .contributionAmount(let index): .contribution(index)
        case .eventAmount(let index), .eventWhen(let index), .eventProbability(let index): .event(index)
        default: nil
        }
    }

    private var moreTitle: String {
        guard let more = moreToken else { return "" }
        switch more {
        case .work: return "Edit the work phase…"
        case .pension: return "Edit the pension…"
        case .contribution: return "Edit the contribution…"
        case .event: return "Edit the event…"
        default: return ""
        }
    }

    // MARK: Values

    /// A yearly amount as a month's, in whole units; writing sets the year's.
    private func monthly(_ yearly: Binding<Decimal?>) -> Binding<Decimal?> {
        Binding(get: { yearly.wrappedValue.map { Decimal(wholeNumber: ($0 / 12).doubleValue) } },
                set: { yearly.wrappedValue = $0.map { $0 * 12 } })
    }

    private func monthly(_ yearly: Binding<Decimal>) -> Binding<Decimal> {
        Binding(get: { Decimal(wholeNumber: (yearly.wrappedValue / 12).doubleValue) },
                set: { yearly.wrappedValue = $0 * 12 })
    }

    private func workFallback(_ index: Int) -> WorkPhase {
        plan.work.indices.contains(index) ? plan.work[index]
            : WorkPhase(from: .today(), until: .retirement, netIncome: nil)
    }

    private func pensionFallback(_ index: Int) -> PlanPension {
        plan.pensions.indices.contains(index) ? plan.pensions[index] : PlanEditing.newPension()
    }

    private func contributionFallback(_ index: Int) -> PlanContribution {
        plan.contributions.indices.contains(index) ? plan.contributions[index]
            : PlanContribution(account: "account", perYear: 0)
    }

    private func eventFallback(_ index: Int) -> PlanEvent {
        plan.events.indices.contains(index) ? plan.events[index] : PlanEvent(name: "", timing: .year(2030), amount: 0)
    }

    private func pensionName(_ index: Int) -> String {
        guard plan.pensions.indices.contains(index) else { return "Pension" }
        return PlanResultsMapping.pensionName(plan.pensions[index], index: index, of: plan.pensions.count)
    }

    private func pensionAge(_ index: Int) -> Int {
        plan.pensions.indices.contains(index) ? plan.pensions[index].planFromAge : 67
    }

    private func contributionIsOneOff(_ index: Int) -> Bool {
        plan.contributions.indices.contains(index) && plan.contributions[index].isOneOff
    }

    private func eventName(_ index: Int) -> String {
        plan.events.indices.contains(index) ? plan.events[index].name : "Event"
    }
}
