import SwiftUI

/// A question of the tour with a number to type (UI.md, "Empty states and
/// first launch"): its title, and the field drawn as a filled box with
/// its unit inside, such as "0 €", so it reads as a place to type. The
/// tour's cards aren't forms, where a bare field would show.
struct OnboardingNumberRow: View {
    let title: String
    @Binding var value: Decimal?
    var kind: PlanNumberText.Kind = .amount
    /// The currency symbol, or "%".
    let unit: String
    var prompt: String = "0"

    init(_ title: String, value: Binding<Decimal?>, kind: PlanNumberText.Kind = .amount, unit: String,
         prompt: String = "0") {
        self.title = title
        _value = value
        self.kind = kind
        self.unit = unit
        self.prompt = prompt
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: Metrics.xs) {
                PlanNumberField(title, value: $value, kind: kind, prompt: prompt, isOptional: true, isOutlined: false)
                Text(unit)
                    .foregroundStyle(Palette.secondaryInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Metrics.s)
            .padding(.vertical, 6)
            .frame(maxWidth: 160)
            .background(Palette.page, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            }
        } label: {
            Text(title)
        }
    }
}
