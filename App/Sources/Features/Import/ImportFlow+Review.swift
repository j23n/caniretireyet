import Foundation
import Glance
import Importer
import Model

// Bank statements' Review (UI.md, "Import"): every file together, its
// subtitle, the values the files disagree with, the accounts the import
// changes, and the balances before a file's first line it still needs.

/// A value of the library that a statement's differs from, on Review: its
/// balance by the file and by the library, and which is kept.
struct ImportReviewConflict: Identifiable, Hashable, Sendable {
    var key: ImportRecordKey
    var id: ImportRecordKey { key }
    /// "Girokonto, 30 Sep 2025".
    var title: String
    /// The balances, when both have one.
    var incoming: Decimal?
    var existing: Decimal?
    /// Both records' values written out, when their balances are the same
    /// or missing: another field differs.
    var incomingText: String
    var existingText: String
    var currency: CurrencyCode
    /// Whether the library's value came from an earlier import rather than
    /// a check-in.
    var existingIsImported: Bool
    /// Whether the account has other values in the files' days, and the
    /// files agree with each of them.
    var othersAgree: Bool
    var resolution: ConflictPolicy

    /// Whether the file's value is used: Use the File's. Undecided keeps
    /// the library's, as Keep Mine does.
    var usesFile: Bool { resolution == .overwrite }

    /// "your check-in", or "an earlier import".
    private var mine: String { existingIsImported ? "an earlier import" : "your check-in" }

    private func amount(_ value: Decimal, locale: Locale) -> String {
        AmountFormat.amount(value, currency: currency, precision: .cents, locale: locale)
    }

    /// The values, when the balances differ: (the file's, the library's).
    private func values(locale: Locale) -> (file: String, mine: String) {
        if let incoming, let existing, incoming != existing {
            return (amount(incoming, locale: locale), amount(existing, locale: locale))
        }
        return (incomingText, existingText)
    }

    /// The Mac's first line: "Girokonto, 30 Sep 2025: the file says
    /// €8,420.00, your check-in says €8,500.00".
    func headline(locale: Locale = .current) -> AmountSentence {
        let values = values(locale: locale)
        return "\(title): the file says \(amount: values.file), \(mine) says \(amount: values.mine)"
    }

    /// The Mac's second line: "Your check-in is €80.00 higher. Every other
    /// month agrees with what you entered."; `nil` when there's nothing to say.
    func detail(locale: Locale = .current) -> AmountSentence? {
        var sentence = AmountSentence()
        if let incoming, let existing, incoming != existing {
            let difference = existing - incoming
            let who = existingIsImported ? "The earlier import" : "Your check-in"
            sentence = "\(who) is \(amount: amount(abs(difference), locale: locale)) "
                + AmountSentence(difference > 0 ? "higher." : "lower.")
        }
        if othersAgree {
            if !sentence.isEmpty { sentence.append(words: " ") }
            sentence.append(words: existingIsImported ? "Every other month agrees with the library."
                : "Every other month agrees with what you entered.")
        }
        return sentence.isEmpty ? nil : sentence
    }

    /// The iPhone's sentence under the title: "The file says €8,420.00.
    /// Your check-in says €8,500.00."
    func compactSentence(locale: Locale = .current) -> AmountSentence {
        let values = values(locale: locale)
        let who = existingIsImported ? "An earlier import" : "Your check-in"
        return "The file says \(amount: values.file). \(who) says \(amount: values.mine)."
    }
}

/// An account the statements change, a row of Review's Accounts.
struct ImportReviewAccount: Identifiable, Hashable, Sendable {
    var account: AccountID
    var id: AccountID { account }
    var name: String
    /// Created by the import, or without values before it.
    var isNew: Bool
    /// The months the import writes a value in.
    var months: Int
    /// Values the library keeps where the files differ.
    var kept: Int
    /// No file is its statement: its values come from money moved to or from it.
    var fromTransfers: Bool
    /// Its balance on Review's last day, with the import, and how it
    /// changed since the end of the year before; `nil` when unknown.
    var balance: Decimal?
    var change: Decimal?
    var currency: CurrencyCode

    /// "21 · 1 kept as yours", "2 · from transfers".
    var monthsText: String {
        var parts = ["\(months)"]
        if kept > 0 { parts.append("\(kept) kept as yours") }
        if fromTransfers { parts.append("from transfers") }
        return parts.joined(separator: " · ")
    }
}

/// A statement whose balance before its first line Review asks for.
struct ImportReviewOpeningBalance: Identifiable, Hashable, Sendable {
    /// The batch's file.
    var file: Int
    var id: Int { file }
    var fileName: String
    var accountName: String
    /// Whether it's still needed: the file's balances can't be worked out yet.
    var isNeeded: Bool
    /// The balance given.
    var balance: Decimal?

    /// What the field is for, or why it's needed.
    var explanation: String {
        isNeeded
            ? "\(fileName) has no balance column, and its balance doesn't follow on from \(accountName)'s values. "
                + "Give the balance before its first line, as the statement shows it."
            : "The balance \(accountName) had before the first line of \(fileName), which its values are worked "
                + "out from."
    }
}

extension ImportFlow {
    // MARK: Subtitle

    /// "26 months for 3 accounts, Jan 2024 to Sep 2025. Nothing is saved
    /// until you import."; `compact` (the iPhone) leaves the dates out.
    func reviewSubtitle(compact: Bool = false, locale: Locale = .current) -> String {
        let counts = planned.map { Self.importedCounts($0, into: library) } ?? (months: 0, accounts: 0)
        let what = counts.months == 0 ? "Nothing changes yet"
            : "\(Wording.count(counts.months, "month")) for \(Wording.count(counts.accounts, "account"))"
        var range = ""
        if !compact, let period = reviewPeriod {
            let from = GlanceText.shortMonthAndYear(period.from, locale: locale)
            let through = GlanceText.shortMonthAndYear(period.through, locale: locale)
            range = from == through ? ", \(from)" : ", \(from) to \(through)"
        }
        return "\(what)\(range). Nothing is saved until you import."
    }

    /// The months a result writes, and the accounts whose values or
    /// account file it changes in `before`: what Review's subtitle and
    /// Done's title count.
    static func importedCounts(_ result: ImportResult, into before: Library) -> (months: Int, accounts: Int) {
        var accounts = Set(result.changedAccounts)
        for month in result.changedMonths {
            let old = Dictionary(grouping: before.months[month]?.valuations ?? [], by: \.account)
            let new = Dictionary(grouping: result.library.months[month]?.valuations ?? [], by: \.account)
            for account in Set(old.keys).union(new.keys) where old[account] != new[account] {
                accounts.insert(account)
            }
            let oldTrades = Dictionary(grouping: before.months[month]?.trades ?? [], by: \.account)
            let newTrades = Dictionary(grouping: result.library.months[month]?.trades ?? [], by: \.account)
            for account in Set(oldTrades.keys).union(newTrades.keys) where oldTrades[account] != newTrades[account] {
                accounts.insert(account)
            }
        }
        return (result.changedMonths.count, accounts.count)
    }

    /// "Imported 26 months for 3 accounts", for Done; "Nothing changed".
    static func importedTitle(_ result: ImportResult, into before: Library) -> String {
        let counts = importedCounts(result, into: before)
        if counts.months == 0 { return "Nothing changed" }
        return "Imported \(Wording.count(counts.months, "month")) for \(Wording.count(counts.accounts, "account"))"
    }

    // MARK: Conflicts

    /// Every value of the statements that differs from the library's, in
    /// the order the files are imported.
    func reviewConflicts(locale: Locale = .current) -> [ImportReviewConflict] {
        let previews = self.previews.map(\.preview)
        let records = previews.flatMap(\.records)
        return previews.flatMap(\.conflicts).map { record in
            let account = record.imported.key.account
            let existing = record.existing.flatMap(Self.valuation)
            let incoming = Self.valuation(of: record.incoming)
            let others = records.filter { other in
                other.imported.key.account == account && other.imported.key.isValuation
                    && other.existing != nil && other.id != record.id
            }
            return ImportReviewConflict(
                key: record.id, title: title(of: record.id, locale: locale), incoming: incoming?.balance,
                existing: existing?.balance, incomingText: describe(record.incoming, locale: locale),
                existingText: record.existing.map { describe($0, locale: locale) } ?? "—",
                currency: account.map(currency(of:)) ?? library.settings.baseCurrency,
                existingIsImported: existing?.source == .import,
                othersAgree: !others.isEmpty && !others.contains { $0.status == .conflict },
                resolution: record.resolution)
        }
    }

    /// Keeps the library's value (Keep Mine) or uses the file's, for one
    /// conflict and those decided with it. The others keep what they were.
    mutating func setReviewResolution(usesFile: Bool, for key: ImportRecordKey) {
        let rows = reviewConflicts()
        let keys = previews.lazy.map(\.preview).first { preview in
            preview.conflicts.contains { $0.id == key }
        }?.conflicts(decidedWith: key) ?? [key]
        editDecisions { decisions in
            // Decided one by one from now on: the others keep what each file's policy gave them.
            if decisions.conflictPolicy != .ask {
                for row in rows { decisions.resolutions[row.key] = row.resolution }
                decisions.conflictPolicy = .ask
            }
            for key in keys { decisions.resolutions[key] = usesFile ? .overwrite : .keep }
        }
    }

    private static func valuation(of record: LibraryRecord) -> Valuation? {
        if case .valuation(let valuation) = record { valuation } else { nil }
    }

    /// An account's currency, the base currency for one that isn't known.
    func currency(of account: AccountID) -> CurrencyCode {
        library.accounts[account]?.currency ?? planned?.library.accounts[account]?.currency
            ?? library.settings.baseCurrency
    }

    // MARK: Accounts

    /// The last day the statements cover: the day Accounts' balances are on.
    var reviewDay: CalendarDate? { reviewPeriod?.through }

    /// "Balance, 30 Sep", with the year when it isn't this one.
    func reviewBalanceHeader(today: CalendarDate = .today(), locale: Locale = .current) -> String {
        guard let day = reviewDay else { return "Balance" }
        return "Balance, \(AmountFormat.shortDate(day, relativeTo: today, locale: locale))"
    }

    /// "Accounts on 30 Sep", the iPhone's header.
    func reviewAccountsHeader(today: CalendarDate = .today(), locale: Locale = .current) -> String {
        guard let day = reviewDay else { return "Accounts" }
        return "Accounts on \(AmountFormat.shortDate(day, relativeTo: today, locale: locale))"
    }

    /// "Since Jan 2025": the change since the end of the year before.
    func reviewSinceHeader(locale: Locale = .current) -> String {
        guard let day = reviewDay else { return "Change" }
        return "Since \(GlanceText.shortMonthAndYear(CalendarDate.firstDay(ofYear: day.year), locale: locale))"
    }

    /// The accounts the statements give values to, in the order of their
    /// files, then the accounts without a file by name.
    var reviewAccounts: [ImportReviewAccount] {
        guard let planned, let day = reviewDay else { return [] }
        let fileAccounts = previews.compactMap { statementAccount(ofFile: $0.file) }
        var order: [AccountID] = []
        for account in fileAccounts where !order.contains(account) { order.append(account) }
        var byAccount: [AccountID: [ImportRecordPreview]] = [:]
        for record in previews.flatMap(\.preview.records) where record.imported.key.isValuation {
            if let account = record.imported.key.account { byAccount[account, default: []].append(record) }
        }
        let after = planned.library
        let others = byAccount.keys.filter { !order.contains($0) }
            .sorted { (after.accounts[$0]?.name ?? $0.rawValue, $0) < (after.accounts[$1]?.name ?? $1.rawValue, $1) }
        let yearEnd = CalendarDate.firstDay(ofYear: day.year).adding(days: -1)
        return (order + others).compactMap { account in
            let records = byAccount[account] ?? []
            let written = records.filter { record in
                record.status == .new || record.status == .updated
                    || (record.status == .conflict && record.resolution == .overwrite)
            }
            let kept = records.filter { $0.status == .conflict && $0.resolution != .overwrite }.count
            let isNew = planned.createdAccounts.contains(account) || library.valuations(for: account).isEmpty
            guard !written.isEmpty || kept > 0 || isNew, after.accounts[account] != nil else { return nil }
            let values = after.valuations(for: account)
            let balance = values.last { $0.date <= day }?.balance
            let opened = after.accounts[account]?.opened ?? day
            let start = values.last { $0.date <= yearEnd }?.balance ?? (opened > yearEnd || isNew ? 0 : nil)
            return ImportReviewAccount(
                account: account, name: after.accounts[account]?.name ?? accountName(account), isNew: isNew,
                months: Set(written.map(\.imported.key.date.yearMonth)).count, kept: kept,
                fromTransfers: !fileAccounts.contains(account), balance: balance,
                change: balance.flatMap { balance in start.map { balance - $0 } }, currency: currency(of: account))
        }
    }

    // MARK: Balance before the first line

    /// The statements whose balance before their first line Review asks
    /// for: those that need it, and those it was given for, so a mistyped
    /// one can be corrected.
    var reviewOpeningBalances: [ImportReviewOpeningBalance] {
        batchFiles.compactMap { file in
            let isNeeded = batchPreview(of: file)?.issues.contains(where: \.asksForOpeningBalance) ?? false
            let balance = file.session.statementOpeningBalance
            guard isNeeded || balance != nil else { return nil }
            return ImportReviewOpeningBalance(file: file.id, fileName: file.name,
                                              accountName: file.account.map(accountName) ?? "its account",
                                              isNeeded: isNeeded, balance: balance)
        }
    }

    /// Gives the balance before the first line of the batch's file `id`,
    /// or takes it away.
    mutating func setStatementOpeningBalance(_ balance: Decimal?, forFile id: Int) {
        editSession(ofFile: id) { $0.statementOpeningBalance = balance }
    }

    // MARK: Done

    /// Whether the steps along the top and the bar at the bottom show:
    /// not on a bank statement's Done, which is a page of its own.
    var showsImportBars: Bool {
        !(step == .done && layout == .statement)
    }
}

private extension ImportRecordKey {
    var isValuation: Bool {
        if case .valuation = self { true } else { false }
    }
}
