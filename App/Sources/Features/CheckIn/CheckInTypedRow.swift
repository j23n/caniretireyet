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
///
/// An account that loses value (``TypedCheckInAccount/estimate``) has its
/// estimate on the date in the field, "Loses 15% a year · was 20.000 €"
/// under its name, and a note that what it lost is lost value. Kept, the
/// estimate isn't saved: the account's value is estimated between values.
struct CheckInTypedRow: View {
    let account: Account
    let date: CalendarDate
    /// "Last value 30 Jun".
    var lastValue: String?
    var isStale = false
    /// Its estimate on the date, for an account that loses value.
    var typed: TypedCheckInAccount?

    @Environment(LibraryStore.self) private var library
    @Environment(CheckInTypedEdits.self) private var edits: CheckInTypedEdits?
    @Environment(\.locale) private var locale

    /// The form as last loaded or saved: its balance is what the field
    /// started from.
    @State private var form: TypedValueForm?
    @State private var text = ""
    @State private var problem: String?
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            row
            if problem == nil, let note = CheckInTypedText.lostNote(typed, account: account, locale: locale) {
                AmountSentenceText(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Metrics.xs)
            }
        }
    }

    private var row: some View {
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
                } else if let loses = CheckInTypedText.loses(typed, account: account, locale: locale) {
                    AmountSentenceText(loses)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
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
        .onChange(of: date) { _, _ in reload() }
        // A value saved elsewhere (Update Value…) refills a field you
        // haven't changed.
        .onChange(of: library.revision) { _, _ in
            if !isFocused, !isSaving, text == form?.balance { reload() }
        }
        .onChange(of: text) { _, new in
            if let form { edits?.note(account, form: form, text: new) }
        }
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
        let loaded = CheckInTypedValue.form(for: account, on: date, valuator: library.valuator,
                                            estimate: typed?.estimate, locale: locale)
        form = loaded
        text = loaded.balance
        edits?.note(account, form: loaded, text: loaded.balance)
    }

    /// Loads the form again: on the check-in's new date, or from a value
    /// saved since.
    private func reload() {
        form = nil
        problem = nil
        load()
    }

    /// Saves the balance when it changed, and waits for the write.
    private func save() {
        guard var edited = form, !isSaving else { return }
        guard text != edited.balance else {
            problem = nil
            return
        }
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
                edits?.note(account, form: saved, text: text)
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
    /// then, or from `estimate`, the value estimated for an account that
    /// loses value.
    static func form(for account: Account, on date: CalendarDate, valuator: Valuator, estimate: Decimal? = nil,
                     today: CalendarDate = .today(), locale: Locale = .current) -> TypedValueForm {
        let day = min(date, TypedValueForm.latestDate(of: account, today: today))
        let previous = valuator.latestValuation(for: account.id, onOrBefore: day)
        var form = TypedValueForm(new: account, on: day, previous: previous, locale: locale)
        if let estimate {
            form.balance = AmountInput.balanceText(for: estimate, isLiability: account.kind.isLiability,
                                                   locale: locale)
        }
        return form
    }
}

/// The words of a typed row for an account that loses value.
enum CheckInTypedText {
    /// "Loses 15% a year · was 20.000,00 €": under the name of an account
    /// with an estimate. `nil` without one.
    static func loses(_ typed: TypedCheckInAccount?, account: Account,
                      locale: Locale = .current) -> AmountSentence? {
        guard typed?.estimate != nil, let rate = account.depreciation, let was = typed?.last?.balance else {
            return nil
        }
        let percent = AmountFormat.percent(rate, digits: 0, locale: locale)
        let amount = AmountFormat.amount(was, currency: account.currency, precision: .cents, locale: locale)
        return "Loses \(percent) a year · was \(amount: amount)"
    }

    /// "Estimated from 15% a year: type over it if you know better. The
    /// 230,00 € it lost is lost value: not spent, not saved."
    static func lostNote(_ typed: TypedCheckInAccount?, account: Account,
                         locale: Locale = .current) -> AmountSentence? {
        guard let lost = typed?.lost, lost > 0, let rate = account.depreciation else { return nil }
        let percent = AmountFormat.percent(rate, digits: 0, locale: locale)
        let amount = AmountFormat.amount(lost, currency: account.currency, precision: .cents, locale: locale)
        var note: AmountSentence = "Estimated from \(percent) a year: type over it if you know better. "
        note += "The \(amount: amount) it lost is lost value: not spent, not saved."
        return note
    }
}

/// The balances typed into a check-in's rows and not saved yet
/// (``CheckInTypedRow``), so the check-in's *Save* writes them before it
/// saves the month: tapping *Save* doesn't end a field's editing.
@MainActor @Observable
final class CheckInTypedEdits {
    /// A row's field: the form it started from and what it holds now.
    struct Edit {
        var account: Account
        var form: TypedValueForm
        var text: String
    }

    /// The fields that hold a changed balance, by account.
    private(set) var edits: [AccountID: Edit] = [:]

    /// A balance that can't be saved: "Home: Enter a balance."
    struct Problem: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// Notes what a row's field holds; an unchanged balance needs no save.
    func note(_ account: Account, form: TypedValueForm, text: String) {
        edits[account.id] = text == form.balance ? nil : Edit(account: account, form: form, text: text)
    }

    /// The values the changed fields hold, by account; throws the first
    /// that can't be saved, naming its account.
    func valuations(today: CalendarDate, locale: Locale) throws -> [Valuation] {
        try edits.values.sorted { $0.account.id < $1.account.id }.map { edit in
            var form = edit.form
            form.balance = edit.text
            if let first = form.problems(for: edit.account, today: today, locale: locale).first {
                throw Problem(message: "\(edit.account.name): \(first)")
            }
            guard let valuation = form.valuation(locale: locale) else {
                throw Problem(message: "\(edit.account.name): the balance can't be read.")
            }
            return valuation
        }
    }

    /// Saves every changed field's balance, then forgets them.
    func saveAll(to library: LibraryStore, locale: Locale) async throws {
        for valuation in try valuations(today: .today(), locale: locale) {
            try await library.saveTypedValue(valuation)
            edits[valuation.account] = nil
        }
    }
}
