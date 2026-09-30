import Model
import SwiftUI
import Tracker

// Small form controls shared by the account and instrument sheets.

/// A number typed in a form row: the label on the left, the field on the
/// right, with the currency or unit after it. Accepts `1.234,56` and
/// `1234.56` (see `AmountInput`).
struct AccountsNumberField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    /// The currency symbol or unit shown after the field.
    var suffix: String?
    /// Whether a minus sign can be typed (balances of debts, flows).
    var allowsNegative = true

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Metrics.xs) {
                TextField(title, text: $text, prompt: Text(prompt))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .privacySensitive()
                    #if os(iOS)
                    .keyboardType(allowsNegative ? .numbersAndPunctuation : .decimalPad)
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
struct AccountsTextField: View {
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

extension AssetMixForm {
    /// The typed percentage of one class, for a text field.
    subscript(text assetClass: AssetClass) -> String {
        get { percents[assetClass] ?? "" }
        set { percents[assetClass] = newValue }
    }
}

/// One row per asset class with its percentage, and what's wrong when the
/// percentages don't add up to 100%.
struct AssetMixFields: View {
    @Binding var mix: AssetMixForm
    @Environment(\.locale) private var locale

    var body: some View {
        ForEach(mix.shownClasses, id: \.self) { assetClass in
            AccountsNumberField(title: BreakdownKey.assetClass(assetClass).description,
                                text: $mix[text: assetClass], prompt: "0", suffix: "%", allowsNegative: false)
        }
        if let problem = mix.problem(required: false, locale: locale) {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
    }
}

/// A list of what must be fixed before saving, under a form.
struct AccountsProblemsSection: View {
    let problems: [String]

    var body: some View {
        if !problems.isEmpty {
            Section {
                ForEach(problems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
    }
}
