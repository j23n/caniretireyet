import Glance
import Model
import Planner
import SwiftUI

/// Beside the money and later-in-life steps on the Mac and iPad (UI.md,
/// "Empty states and first launch"): the answer moving as you type. Each
/// change runs a quick estimate, a few hundred futures of the library and
/// plan *See My Answer* would create, in memory
/// (``OnboardingModel/estimateRequest(today:)``); the full answer comes at
/// the end.
struct OnboardingEstimatePanel: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(PlanStore.self) private var plans
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            Text("Quick estimate · updates as you type")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.secondaryInk)
            if let estimate = model.estimate, model.estimateRequest() != nil {
                Text(Self.title(estimate.headline))
                    .font(.title2.bold())
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
                if let change = Self.change(from: model.previousEstimate?.headline, to: estimate.headline) {
                    Text(change.text)
                        .font(.callout)
                        .foregroundStyle(change.isSooner ? Palette.positive : Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                }
                Divider()
                if let spending = estimate.spendingPerMonth {
                    row("Spending", spending)
                }
                if let saving = estimate.savingPerMonth {
                    row("Saving", saving)
                }
            } else {
                Text(waitingText)
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Each change runs a few hundred futures. The full answer comes when you finish.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onboardingCard()
        .task(id: model.estimateInputs) { await model.updateEstimate(plans: plans) }
    }

    private func row(_ title: String, _ amount: Decimal) -> some View {
        LabeledContent(title) {
            AmountText(amount, currency: model.currency)
                .monospacedDigit()
        }
        .font(.subheadline)
    }

    /// What the estimate still needs.
    private var waitingText: String {
        if model.birthDate == nil { return "Your birth date, on the step before, lets it say an age." }
        if !model.answers.hasStartingAmounts { return "Type what you have today to see an estimate." }
        return "Working it out…"
    }

    /// "You could retire at 57", "You could retire today", or "No age works
    /// yet".
    static func title(_ headline: RetirementAnswer) -> String {
        if headline.canRetireNow { return "You could retire today" }
        guard let age = headline.earliestAge else { return "No age works yet" }
        return "You could retire at \(age)"
    }

    /// "A year sooner than before your last change", "2 years later than
    /// before your last change"; `nil` when the age didn't move.
    static func change(from before: RetirementAnswer?, to now: RetirementAnswer) -> (text: String, isSooner: Bool)? {
        guard let then = before?.earliestAge, let age = now.earliestAge, then != age else { return nil }
        let years = abs(age - then)
        let count = years == 1 ? "A year" : "\(years) years"
        return ("\(count) \(age < then ? "sooner" : "later") than before your last change", age < then)
    }
}
