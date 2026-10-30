import Importer
import Model
import SwiftUI
import Tracker

/// One line of a month (UI.md, "A month's lines"): the bank's text, its
/// amount and date, and what it is, chosen from buttons. Money moved asks
/// to which of your accounts: it's saved at once, not spent. The same can
/// go to the month's other lines with the same words and be remembered for
/// the next statement. A note, *Remove Line* for a line listed twice (or
/// *Restore Line*), and *Confirm*, which checks it.
struct MonthLineEditor: View {
    let line: BankLine
    let month: AccountMonth
    let account: Account
    /// Closes the editor, after a change is saved.
    let done: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @State private var edit: MonthLineEdit
    @State private var errorMessage: String?
    @FocusState private var isEditingNote: Bool

    init(line: BankLine, month: AccountMonth, account: Account, done: @escaping () -> Void) {
        self.line = line
        self.month = month
        self.account = account
        self.done = done
        _edit = State(initialValue: MonthLineEdit(line))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            header
            classButtons
            if edit.statementClass == .transfer {
                otherAccountPicker
            }
            similarToggles
            TextField("Note (optional)", text: $edit.note, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isEditingNote)
                .typedFieldOutline(isFocused: isEditingNote)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Palette.critical)
            }
            HStack(spacing: Metrics.s) {
                Button(line.isRemoved ? "Restore Line" : "Remove Line", role: line.isRemoved ? nil : .destructive) {
                    toggleRemoved()
                }
                Spacer(minLength: Metrics.s)
                Button(line.isConfirmed ? "Save" : "Confirm") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(line.isRemoved)
            }
            .disabled(!library.canEdit)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.text.isEmpty ? "No text" : line.text)
                    .font(.headline)
                    .privacySensitiveInFeedback()
                Spacer(minLength: Metrics.s)
                AmountText(line.amount, currency: account.currency, precision: .cents, signed: true)
                    .font(.title3.bold())
            }
            Text("\(AmountFormat.mediumDate(line.date, locale: locale)) · \(account.name)")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
            if !line.isConfirmed, !line.isRemoved {
                Text("Suggested by the import: check it, or choose what it is.")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    private var classButtons: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text("What is it?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.secondaryInk)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Metrics.s), count: 3),
                      spacing: Metrics.s) {
                ForEach(MonthText.classes(recordsInterest: account.kind.recordsInterest), id: \.self) { kind in
                    classButton(kind)
                }
            }
        }
    }

    private func classButton(_ kind: StatementClass) -> some View {
        let isChosen = edit.statementClass == kind
        return Button {
            edit.statementClass = kind
        } label: {
            Text(MonthText.kind(kind, other: nil))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(isChosen ? Palette.accentDeep : Palette.ink)
                .background(isChosen ? Palette.accent.opacity(0.15) : Palette.card,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isChosen ? Palette.accent : Palette.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private var otherAccountPicker: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Picker("To which account?", selection: $edit.other) {
                Text("Not one of mine").tag(AccountID?.none)
                ForEach(otherAccounts) { other in
                    Text(other.name).tag(AccountID?.some(other.id))
                }
            }
            .personalControl()
            Text(movedNote)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var movedNote: String {
        guard let other = edit.other, let name = library.library.accounts[other]?.name else {
            return "Moved between your own accounts: neither came in nor spent."
        }
        return "Not spent. This counts as saved right away, even before \(name) shows the money."
    }

    /// Every other open account money can move to, by name.
    private var otherAccounts: [Account] {
        library.library.accounts.values
            .filter { $0.id != account.id && ($0.isOpen(on: line.date) || $0.id == line.otherAccount) }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    @ViewBuilder
    private var similarToggles: some View {
        let similar = similarCount
        let phrase = edit.phrase.trimmingCharacters(in: .whitespaces)
        if !phrase.isEmpty, similar > 0 || library.library.statementProfile(for: account.id) != nil {
            VStack(alignment: .leading, spacing: Metrics.s) {
                if similar > 0 {
                    Toggle(isOn: $edit.appliesToSimilar) {
                        Text("The same for the other \(Wording.count(similar, "line")) from “\(phrase)”")
                            .privacySensitiveInFeedback()
                    }
                }
                if library.library.statementProfile(for: account.id) != nil {
                    Toggle(isOn: $edit.remembers) {
                        Text("Remember it for every line from “\(phrase)” in the next statements")
                            .privacySensitiveInFeedback()
                    }
                }
            }
        }
    }

    /// The month's other lines with the line's words that aren't checked yet.
    private var similarCount: Int {
        library.library.lines(of: account.id, matching: edit.phrase, after: month.from, through: month.through)
            .filter { $0.key != line.key && !$0.isConfirmed }
            .count
    }

    // MARK: Saving

    private func save() {
        let edit = self.edit
        let month = self.month
        let line = self.line
        do {
            try library.update { edit.apply(to: line, in: month, library: &$0) }
            done()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }

    private func toggleRemoved() {
        var changed = line
        changed.removed = line.isRemoved ? nil : true
        do {
            try library.update { $0.save([changed]) }
            done()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}
