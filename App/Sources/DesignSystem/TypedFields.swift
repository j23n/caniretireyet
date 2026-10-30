import Model
import SwiftUI

// Fields you type into (UI.md, "Fields"): each looks like a place to type,
// in a rounded outline that turns the accent while it's edited. In a form,
// a row keeps its label beside the field.

/// A number typed in a form row: the label on the left, and on the right
/// the field in its outline (`typedFieldOutline(isFocused:)`) with the
/// currency or unit after it. Accepts `1.234,56` and `1234.56` (see
/// `AmountInput`).
struct FormNumberField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    /// The currency symbol or unit shown after the field.
    var suffix: String?
    /// Whether a minus sign can be typed (balances of debts).
    var allowsNegative = true

    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Metrics.xs) {
                TextField(title, text: $text, prompt: Text(prompt))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($isFocused)
                    // Not `.privacySensitive()`: what you type shows while amounts are hidden.
                    #if os(iOS)
                    .numberKeyboard(allowsNegative ? .numbersAndPunctuation : .decimalPad)
                    #endif
                if let suffix {
                    Text(suffix)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .frame(maxWidth: 160)
            .typedFieldOutline(isFocused: isFocused)
        }
    }
}

/// A text typed in a form row: the label on the left, the field in its
/// outline on the right.
struct FormTextField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""

    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .typedFieldOutline(isFocused: isFocused)
        }
    }
}

/// An amount typed on a card, outside a form: the currency's symbol, then
/// the field, in a rounded outline (`typedFieldOutline(isFocused:)`). An
/// estimate the app filled in is in the accent, in a dashed outline, until
/// it's typed over. Not `.privacySensitive()`: what you type shows while
/// amounts are hidden.
struct OutlinedAmountField: View {
    let title: String
    @Binding var text: String
    let currency: CurrencyCode
    var isFocused: FocusState<Bool>.Binding
    /// Whether the field holds an estimate rather than a value you typed.
    var isEstimate = false

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: Metrics.xs) {
            Text(verbatim: AmountFormat.symbol(for: currency, locale: locale))
                .foregroundStyle(Palette.secondaryInk)
            TextField(title, text: $text, prompt: Text(verbatim: "0"))
                .labelsHidden()
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .foregroundStyle(isEstimate ? Palette.accent : Palette.ink)
                #if os(iOS)
                .numberKeyboard(.numbersAndPunctuation)
                #endif
                .focused(isFocused)
        }
        .frame(width: 136)
        .typedFieldOutline(isFocused: isFocused.wrappedValue, isEstimate: isEstimate)
    }
}

/// A choice from a menu, drawn as a tinted pill with ⌄ (UI.md, "Fields"):
/// "EUR ⌄", "Directa ⌄". In a form row, its title on the left. The menu
/// lists the picker's options, with a check on the one chosen.
struct PillPicker<Value: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Value
    /// What the pill says: the chosen option's name.
    let value: String
    /// Whether the title shows beside the pill; off where a row has its own.
    var showsTitle = true
    /// Whether `value` is the person's data, such as an account's name.
    var isPersonal = false
    let options: Options

    init(_ title: String, selection: Binding<Value>, value: String, showsTitle: Bool = true,
         isPersonal: Bool = false, @ViewBuilder options: () -> Options) {
        self.title = title
        _selection = selection
        self.value = value
        self.showsTitle = showsTitle
        self.isPersonal = isPersonal
        self.options = options()
    }

    var body: some View {
        if showsTitle {
            LabeledContent(title) { menu }
        } else {
            menu
        }
    }

    private var menu: some View {
        Menu {
            Picker(title, selection: $selection) { options }
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            PillLabel(value, isPersonal: isPersonal)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// The label of a choice from a menu: its name and ⌄ in the accent, on a
/// tinted, rounded background.
struct PillLabel: View {
    let value: String
    var isPersonal = false
    /// Grey instead of the accent, for a choice that leaves something out.
    var isMuted = false

    init(_ value: String, isPersonal: Bool = false, isMuted: Bool = false) {
        self.value = value
        self.isPersonal = isPersonal
        self.isMuted = isMuted
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: value)
                .lineLimit(1)
                .privacySensitiveInFeedback(isPersonal)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
        }
        .fontWeight(.semibold)
        .foregroundStyle(isMuted ? Palette.secondaryInk : Palette.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((isMuted ? Palette.secondaryInk : Palette.accent).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// A text field outside the shared fields: plain, in the rounded outline,
/// focus and all (`typedFieldOutline(isFocused:)`). Its label is hidden,
/// so in a Mac form the outline holds the field alone: its prompt says
/// what it's for.
private struct OutlinedField: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($isFocused)
            .typedFieldOutline(isFocused: isFocused)
    }
}

extension View {
    /// Draws a `TextField` as every field is drawn (UI.md, "Fields"): in a
    /// rounded outline that turns the accent while it's edited.
    func outlinedField() -> some View {
        modifier(OutlinedField())
    }

    /// A field outside a form: a rounded 1-pt outline, 2 pt in the accent
    /// while it's edited, so it reads as a place to type. An estimate's
    /// outline is dashed, in the accent.
    func typedFieldOutline(isFocused: Bool, isEstimate: Bool = false) -> some View {
        padding(.horizontal, Metrics.s)
            .padding(.vertical, 6)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isFocused || isEstimate ? Palette.accent : Palette.border,
                                  style: StrokeStyle(lineWidth: isFocused ? 2 : 1,
                                                     dash: isEstimate && !isFocused ? [4, 3] : []))
            }
    }
}
