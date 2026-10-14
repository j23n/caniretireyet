import Foundation
import Model
import Tracker

/// The bank statements a check-in starts with (UI.md, "Statements first"):
/// the accounts a statement can fill in, and which of them have a value
/// from an import on the check-in's date.
///
/// Importing writes those values into the library, and the check-in
/// follows the library (``CheckInDraft/rebase(onto:)``): a row with
/// nothing typed is filled in from the imported value, as "Imported".
struct CheckInStatements: Hashable, Sendable {
    /// One account a statement fills in.
    struct Account: Identifiable, Hashable, Sendable {
        var id: AccountID
        var name: String
        /// The day of its last value before the check-in.
        var last: CalendarDate?
        /// Whether an import gave it a value on the check-in's date.
        var isImported: Bool
    }

    /// The check-in's date.
    var date: CalendarDate
    /// The accounts whose statements were imported with a saved profile,
    /// and any other account with a value imported on the date, in the
    /// check-in's order. Accounts that open after the date are left out.
    var accounts: [Account]

    /// How many of ``accounts`` have a value imported on the date.
    var importedCount: Int { accounts.count(where: \.isImported) }

    /// Whether the check-in opens with the card that asks for the
    /// statements first: there are accounts a statement fills in, none is
    /// imported yet, and the card wasn't put away (`dismissed`).
    func showsStart(dismissed: Bool) -> Bool {
        !dismissed && !accounts.isEmpty && importedCount == 0
    }

    /// The statements of `draft`'s rows in `library`.
    static func make(draft: CheckInDraft, library: Library) -> CheckInStatements {
        let profiled = Set(library.importProfiles.values.filter { $0.layout == .statement }
            .compactMap(\.constants.account))
        let accounts = draft.rows.compactMap { row -> Account? in
            guard !row.opensLater, let account = library.accounts[row.account] else { return nil }
            let valuations = library.valuations(for: row.account)
            let imported = valuations.contains { $0.date == draft.date && $0.source == .import }
            guard imported || profiled.contains(row.account) else { return nil }
            return Account(id: row.account, name: account.name, last: valuations.last { $0.date < draft.date }?.date,
                           isImported: imported)
        }
        return CheckInStatements(date: draft.date, accounts: accounts)
    }

    // MARK: Wording

    /// "Start with September's statements".
    func startTitle(locale: Locale = .current) -> String {
        "Start with " + AmountFormat.monthName(date, locale: locale) + "'s statements"
    }

    static let startMessage = "Your bank's CSV fills in each account's balance and what came in and went out. "
        + "You type only the rest."

    /// What an account's line says: "Imported", "Last value 31 Aug", or
    /// "No value yet".
    static func status(of account: Account, locale: Locale = .current) -> String {
        if account.isImported { return "Imported" }
        guard let last = account.last else { return "No value yet" }
        return "Last value " + AmountFormat.shortDate(last, locale: locale)
    }

    /// "2 of 3 imported", under the section's header.
    var progress: String {
        "\(importedCount) of \(accounts.count) imported"
    }
}

/// A check-in's statements chosen with *Add Statements…*, imported in a
/// sheet over the check-in.
struct CheckInStatementImport: Identifiable, Hashable {
    let id = UUID()
    var files: [URL]
    /// The check-in's date, which the statements cover through.
    var date: CalendarDate
}
