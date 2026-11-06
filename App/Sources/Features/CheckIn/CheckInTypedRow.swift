import Model
import SwiftUI
import Tracker

/// An account whose values you type, in the check-in (UI.md, "Check-in"):
/// its name over when its last value was, and its balance on the
/// check-in's date in a field, prefilled from the last value. After the
/// account's first value, fields under it ask what moved since the last
/// one (``TypedValueForm/asksWhatMoved``): what was added, or what came in,
/// what went out and the interest, empty until typed. Changing a field and
/// pressing Return, or leaving it, saves the value on that date once every
/// field it asks for is filled (`LibraryStore.saveTypedValue(_:replacing:)`,
/// with its backup), as *Update Value* does; a value that can't be read or
/// saved says so under the name, and one still missing what moved waits
/// for the check-in's *Save*, which names it.
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

    /// The form as last loaded or saved: what the fields started from.
    @State private var form: TypedValueForm?
    /// What the fields hold now.
    @State private var edited: TypedValueForm?
    @State private var problem: String?
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            row
            if let edited, edited.asksWhatMoved {
                whatMovedFields(edited)
            }
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
                    .lineLimit(2)
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
                        .fixedSize(horizontal: false, vertical: true)
                } else if let lastValue {
                    Text(verbatim: lastValue)
                        .font(.subheadline)
                        .foregroundStyle(isStale ? Palette.warning : Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .privacySensitiveInFeedback()
                }
            }
            Spacer(minLength: Metrics.s)
            field
        }
        .padding(.vertical, Metrics.s)
        .onAppear(perform: load)
        .onChange(of: date) { _, _ in reload() }
        // A value saved elsewhere (Update Value…) refills fields you
        // haven't changed.
        .onChange(of: library.revision) { _, _ in
            if !isFocused, !isSaving, edited == form { reload() }
        }
        .onChange(of: edited) { _, new in
            if let form, let new { edits?.note(account, form: form, edited: new) }
        }
    }

    /// One of the form's text fields, as a binding.
    private func binding(_ field: WritableKeyPath<TypedValueForm, String>) -> Binding<String> {
        Binding(get: { edited?[keyPath: field] ?? "" }, set: { edited?[keyPath: field] = $0 })
    }

    /// The balance, in a rounded field that turns the accent while it's
    /// edited.
    private var field: some View {
        OutlinedAmountField(title: account.kind.isLiability ? "Owed" : "Balance", text: binding(\.balance),
                            currency: account.currency, isFocused: $isFocused, isEstimate: isEstimate)
            .onSubmit(save)
            .disabled(!library.canEdit || isSaving)
            .onChange(of: isFocused) { _, focused in
                if !focused { save() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: "\(account.name), \(account.kind.isLiability ? "owed" : "balance")"))
    }

    /// What moved since the last value, each in a field under the balance.
    @ViewBuilder
    private func whatMovedFields(_ edited: TypedValueForm) -> some View {
        switch edited.whatMoved {
        case .nothing:
            EmptyView()
        case .added:
            CheckInWhatMovedField(title: edited.addedLabel, text: binding(\.added), account: account,
                                  isSaving: isSaving, onEnd: save)
        case .moneyInOut:
            CheckInWhatMovedField(title: "Came in", text: binding(\.cameIn), account: account, isSaving: isSaving,
                                  onEnd: save)
            CheckInWhatMovedField(title: "Went out", text: binding(\.wentOut), account: account,
                                  isSaving: isSaving, onEnd: save)
            CheckInWhatMovedField(title: "Interest", text: binding(\.interest), account: account,
                                  isSaving: isSaving, onEnd: save)
        }
    }

    /// Whether the field still holds the account's estimate: it loses
    /// value, has no value on the date, and nothing was typed over it.
    private var isEstimate: Bool {
        typed?.estimate != nil && edited?.balance == form?.balance
    }

    private func load() {
        guard form == nil else { return }
        let loaded = CheckInTypedValue.form(for: account, on: date, valuator: library.valuator,
                                            estimate: typed?.estimate, locale: locale)
        form = loaded
        edited = loaded
        edits?.note(account, form: loaded, edited: loaded)
    }

    /// Loads the form again: on the check-in's new date, or from a value
    /// saved since.
    private func reload() {
        form = nil
        problem = nil
        load()
    }

    /// Saves the value when it changed and every field it asks for is
    /// filled, and waits for the write.
    private func save() {
        guard let edited, !isSaving else { return }
        guard edited != form else {
            problem = nil
            return
        }
        // Still being filled in: the check-in's Save names it if it stays so.
        guard !edited.isMissingWhatMoved(locale: locale) else {
            problem = nil
            return
        }
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
                edits?.note(account, form: saved, edited: self.edited ?? saved)
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
    /// loses value. A value already typed on that day (a check-in opened
    /// again) is edited instead, so what moved keeps what was typed.
    static func form(for account: Account, on date: CalendarDate, valuator: Valuator, estimate: Decimal? = nil,
                     today: CalendarDate = .today(), locale: Locale = .current) -> TypedValueForm {
        let day = min(date, TypedValueForm.latestDate(of: account, today: today))
        let previous = valuator.latestValuation(for: account.id, onOrBefore: day)
        if let previous, previous.date == day, previous.source == .manual {
            let firstOther = valuator.valuations(for: account.id).first { $0.key != previous.key }?.date
            return TypedValueForm(editing: previous, of: account, firstOtherValue: firstOther, locale: locale)
        }
        var form = TypedValueForm(new: account, on: day, previous: previous,
                                  firstValue: valuator.valuations(for: account.id).first?.date, locale: locale)
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

/// The values typed into a check-in's rows and not saved yet
/// (``CheckInTypedRow``), so the check-in's *Save* writes them before it
/// saves the month: tapping *Save* doesn't end a field's editing, and a
/// row waits until what moved is filled in.
@MainActor @Observable
final class CheckInTypedEdits {
    /// A row's fields: the form they started from and what they hold now.
    struct Edit {
        var account: Account
        var form: TypedValueForm
        var edited: TypedValueForm
    }

    /// The rows whose fields changed, by account.
    private(set) var edits: [AccountID: Edit] = [:]

    /// A balance that can't be saved: "Home: Enter a balance."
    struct Problem: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// Notes what a row's fields hold; unchanged ones need no save.
    func note(_ account: Account, form: TypedValueForm, edited: TypedValueForm) {
        edits[account.id] = edited == form ? nil : Edit(account: account, form: form, edited: edited)
    }

    /// The values the changed fields hold, by account; throws the first
    /// that can't be saved, naming its account.
    func valuations(today: CalendarDate, locale: Locale) throws -> [Valuation] {
        try edits.values.sorted { $0.account.id < $1.account.id }.map { edit in
            let form = edit.edited
            if let first = form.problems(for: edit.account, today: today, locale: locale).first {
                throw Problem(message: "\(edit.account.name): \(first)")
            }
            guard let valuation = form.valuation(locale: locale) else {
                throw Problem(message: "\(edit.account.name): an amount can't be read.")
            }
            return valuation
        }
    }

    /// Saves every changed row's value, then forgets them.
    func saveAll(to library: LibraryStore, locale: Locale) async throws {
        for valuation in try valuations(today: .today(), locale: locale) {
            try await library.saveTypedValue(valuation)
            edits[valuation.account] = nil
        }
    }
}

/// A field under a typed row's balance for what moved since the last
/// value: its label, then the amount, in the same rounded field.
private struct CheckInWhatMovedField: View {
    let title: String
    @Binding var text: String
    let account: Account
    /// Whether the row is saving, which holds the field as the balance's is.
    let isSaving: Bool
    /// Called on Return and when the field is left.
    let onEnd: () -> Void

    @Environment(LibraryStore.self) private var library
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Metrics.s) {
            Text(verbatim: title)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
            Spacer(minLength: Metrics.s)
            OutlinedAmountField(title: title, text: $text, currency: account.currency, isFocused: $isFocused)
                .onSubmit(onEnd)
                .disabled(!library.canEdit || isSaving)
                .onChange(of: isFocused) { _, focused in
                    if !focused { onEnd() }
                }
        }
        .padding(.leading, Metrics.m)
        .padding(.bottom, Metrics.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(account.name), \(title.lowercased())"))
    }
}
