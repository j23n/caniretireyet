import Model
import SwiftUI
import Tracker

/// An account whose values you type, in the check-in (UI.md, "Check-in"):
/// its name over when its last value was, and its balance on the
/// check-in's date in a field, prefilled from the last value. Changing the
/// field and pressing Return, or leaving it, saves the balance as a typed
/// value on that date (`LibraryStore.saveTypedValue(_:replacing:)`, with
/// its backup), as *Update Value* does; a value that can't be read or
/// saved says so under the name.
struct CheckInTypedRow: View {
    let account: Account
    let date: CalendarDate
    /// "Last value 30 Jun".
    var lastValue: String?
    var isStale = false

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    /// The form as last loaded or saved: its balance is what the field
    /// started from.
    @State private var form: TypedValueForm?
    @State private var text = ""
    @State private var problem: String?
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: account.name)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .privacySensitiveInFeedback()
                if let problem {
                    Text(verbatim: problem)
                        .font(.subheadline)
                        .foregroundStyle(Palette.critical)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let lastValue {
                    Text(verbatim: lastValue)
                        .font(.subheadline)
                        .foregroundStyle(isStale ? Palette.warning : Palette.secondaryInk)
                        .lineLimit(1)
                        .privacySensitiveInFeedback()
                }
            }
            Spacer(minLength: Metrics.s)
            field
        }
        .padding(.vertical, Metrics.s)
        .onAppear(perform: load)
    }

    /// The balance, in a rounded field that turns the accent while it's
    /// edited. Not `.privacySensitive()`: what you type shows while
    /// amounts are hidden.
    private var field: some View {
        HStack(spacing: Metrics.xs) {
            Text(verbatim: AmountFormat.symbol(for: account.currency, locale: locale))
                .foregroundStyle(Palette.secondaryInk)
            TextField(account.kind.isLiability ? "Owed" : "Balance", text: $text, prompt: Text(verbatim: "0"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                #if os(iOS)
                .numberKeyboard(.numbersAndPunctuation)
                #endif
                .focused($isFocused)
                .onSubmit(save)
                .disabled(!library.canEdit || isSaving)
        }
        .frame(width: 136)
        .padding(.horizontal, Metrics.s)
        .padding(.vertical, 6)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isFocused ? Palette.accent : Palette.border, lineWidth: isFocused ? 2 : 1)
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { save() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(account.name), \(account.kind.isLiability ? "owed" : "balance")"))
    }

    private func load() {
        guard form == nil else { return }
        let loaded = CheckInTypedValue.form(for: account, on: date, valuator: library.valuator, locale: locale)
        form = loaded
        text = loaded.balance
    }

    /// Saves the balance when it changed, and waits for the write.
    private func save() {
        guard var edited = form, text != edited.balance, !isSaving else { return }
        edited.balance = text
        if let first = edited.problems(for: account, today: .today(), locale: locale).first {
            problem = first
            return
        }
        guard let valuation = edited.valuation(locale: locale) else {
            problem = "The balance can't be read."
            return
        }
        isSaving = true
        let saved = edited
        Task {
            do {
                try await library.saveTypedValue(valuation)
                form = saved
                problem = nil
            } catch {
                problem = LibraryStore.describe(error)
            }
            isSaving = false
        }
    }
}

/// The typed value a check-in's row starts from (``CheckInTypedRow``).
enum CheckInTypedValue {
    /// A new value of `account` on `date` (or the day it closed, if
    /// earlier), its balance prefilled from the latest value on or before
    /// then.
    static func form(for account: Account, on date: CalendarDate, valuator: Valuator,
                     today: CalendarDate = .today(), locale: Locale = .current) -> TypedValueForm {
        let day = min(date, TypedValueForm.latestDate(of: account, today: today))
        let previous = valuator.latestValuation(for: account.id, onOrBefore: day)
        return TypedValueForm(new: account, on: day, previous: previous, locale: locale)
    }
}
