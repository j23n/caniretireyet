import Model
import SwiftUI

// Fields you type into (UI.md, "Fields"): each looks like a place to type.
// In a form, a row keeps its label beside the field; outside a form, the
// field has a rounded outline that turns the accent while it's edited.

/// A number typed in a form row: the label on the left, the field on the
/// right, with the currency or unit after it. Accepts `1.234,56` and
/// `1234.56` (see `AmountInput`).
struct FormNumberField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    /// The currency symbol or unit shown after the field.
    var suffix: String?
    /// Whether a minus sign can be typed (balances of debts).
    var allowsNegative = true

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Metrics.xs) {
                TextField(title, text: $text, prompt: Text(prompt))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    // Not `.privacySensitive()`: what you type shows while amounts are hidden.
                    #if os(iOS)
                    .numberKeyboard(allowsNegative ? .numbersAndPunctuation : .decimalPad)
                    #endif
                if let suffix {
                    Text(suffix)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
    }
}

/// A text typed in a form row, with the label on the left.
struct FormTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text, prompt: Text(prompt))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
        }
    }
}

/// An amount typed on a card, outside a form: the currency's symbol, then
/// the field, in a rounded outline (`typedFieldOutline(isFocused:)`).
/// Not `.privacySensitive()`: what you type shows while amounts are
/// hidden.
struct OutlinedAmountField: View {
    let title: String
    @Binding var text: String
    let currency: CurrencyCode
    var isFocused: FocusState<Bool>.Binding

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: Metrics.xs) {
            Text(verbatim: AmountFormat.symbol(for: currency, locale: locale))
                .foregroundStyle(Palette.secondaryInk)
            TextField(title, text: $text, prompt: Text(verbatim: "0"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                #if os(iOS)
                .numberKeyboard(.numbersAndPunctuation)
                #endif
                .focused(isFocused)
        }
        .frame(width: 136)
        .typedFieldOutline(isFocused: isFocused.wrappedValue)
    }
}

extension View {
    /// A field outside a form: a rounded 1-pt outline, 2 pt in the accent
    /// while it's edited, so it reads as a place to type.
    func typedFieldOutline(isFocused: Bool) -> some View {
        padding(.horizontal, Metrics.s)
            .padding(.vertical, 6)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isFocused ? Palette.accent : Palette.border, lineWidth: isFocused ? 2 : 1)
            }
    }
}
