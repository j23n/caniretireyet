import Foundation
import Glance
import Importer
import Model
import Storage
import Tracker

/// What an import did, for the Done step.
struct ImportReceipt: Hashable, Sendable {
    var fileName: String
    /// Records added, filled in, overwritten, kept (of which undecided),
    /// already there, and left out (rejected accounts or instruments).
    var added: Int
    var updated: Int
    var overwritten: Int
    var kept: Int
    var undecided: Int
    /// The library's trades removed: those the trades made from quantities
    /// replace and no longer make.
    var removed: Int
    var identical: Int
    var skipped: Int
    /// Later values whose automatic new money was worked out again.
    var recomputedFlows: Int
    /// Names of the accounts created and closed, and the instruments created.
    var createdAccounts: [String]
    var closedAccounts: [String]
    var createdInstruments: [String]
    /// The IDs of the instruments created, for the Done step's offer to find
    /// their price sources.
    var createdInstrumentIDs: [InstrumentID]
    /// Names of the accounts that now record trades, and how many trades were written.
    var tradesAccounts: [String]
    var trades: Int
    /// How many library files the import wrote: month, account and instrument files.
    var changedFileCount: Int
    /// The instruments held in the valuations of the months the import
    /// changed, for the Done step's offer to fill in their past prices.
    var importedInstruments: Set<InstrumentID>
    /// The copy of those files taken before writing; `nil` for a library
    /// without files (previews), which can't be undone.
    var backup: Backup?
    var isUndone = false
    /// What undoing did, once it's undone.
    var undoReport: UndoReport?
    /// The profile saved from this import.
    var savedProfile: ImportProfileID?
    /// Bank statements: "Imported 26 months for 3 accounts".
    var summary: String?
    /// Bank statements: what was saved this year with the import applied.
    var savings: ImportSavings?
    /// Bank statements: what the import remembered for next time, when
    /// Remember was on.
    var remembered: [ImportRemembered] = []

    /// What `result` did. The accounts and instruments it names are in its
    /// library: it created them or found them there.
    init(fileName: String, result: ImportResult) {
        self.fileName = fileName
        added = result.added
        updated = result.updated
        overwritten = result.overwritten
        kept = result.kept
        undecided = result.undecided
        removed = result.removed
        identical = result.identical
        skipped = result.skipped
        recomputedFlows = result.recomputedFlows.count
        let accounts = result.library.accounts
        createdAccounts = result.createdAccounts.map { accounts[$0]?.name ?? $0.rawValue }
        closedAccounts = result.closedAccounts.map { accounts[$0]?.name ?? $0.rawValue }
        createdInstruments = result.createdInstruments.map { result.library.instruments[$0]?.name ?? $0.rawValue }
        createdInstrumentIDs = result.createdInstruments
        tradesAccounts = result.tradesAccounts.map { accounts[$0]?.name ?? $0.rawValue }
        trades = result.tradesWritten
        changedFileCount = result.changedMonths.count + result.changedAccounts.count
            + result.createdInstruments.count
        importedInstruments = Set(result.changedMonths.flatMap { month in
            (result.library.months[month]?.valuations ?? []).flatMap { $0.positions.map(\.instrument) }
                + (result.library.months[month]?.trades ?? []).compactMap(\.instrument)
        })
    }

    /// Whether the import wrote anything.
    var hasChanges: Bool { changedFileCount > 0 }

    /// Whether Undo import can run.
    var canUndo: Bool {
        hasChanges && !isUndone && backup != nil
    }

    /// What undoing couldn't undo because it changed after the import, in
    /// plain words; empty when everything was undone.
    var undoNotes: [String] {
        guard let undoReport else { return [] }
        if undoReport.restoredWholesale {
            return ["The backup didn't record what the import wrote, so its files were put back as they were, "
                + "over any later edits."]
        }
        return undoReport.keptChanges.map(\.summary)
    }
}

/// What was saved in the year of a statements' import, with it applied, as
/// Trends counts it (Tracker's `Valuator.savingsRate(from:through:)` over
/// the whole library), for Done's sentence.
struct ImportSavings: Hashable, Sendable {
    var year: Int
    /// Whether the import ends before the year does.
    var isSoFar: Bool
    var saved: Decimal
    /// What came in, after tax.
    var cameIn: Decimal
    var rate: Decimal
    var currency: CurrencyCode

    /// The savings from the first day of `through`'s year through it in
    /// `library`; `nil` when nothing came in.
    init?(library: Library, through: CalendarDate) {
        let valuator = Tracker.Valuator(library: library)
        guard let savings = valuator.savingsRate(from: CalendarDate.firstDay(ofYear: through.year), through: through),
              let rate = savings.rate else { return nil }
        year = through.year
        isSoFar = through < CalendarDate.lastDay(ofYear: through.year)
        saved = savings.saved
        cameIn = savings.income
        self.rate = rate
        currency = library.settings.baseCurrency
    }

    /// "In 2025 so far you saved €12,300 of the €41,350 that came in after
    /// tax: a savings rate of 30%."
    func sentence(locale: Locale = .current) -> AmountSentence {
        func amount(_ value: Decimal) -> String {
            AmountFormat.amount(value, currency: currency, precision: .whole, locale: locale)
        }
        let when = "In \(year)\(isSoFar ? " so far" : "")"
        guard saved >= 0 else {
            return "\(when) you spent \(amount: amount(-saved)) more than the \(amount: amount(cameIn)) that came in "
                + "after tax."
        }
        let percent = AmountFormat.percent(rate, digits: 0, locale: locale)
        return "\(when) you saved \(amount: amount(saved)) of the \(amount: amount(cameIn)) that came in after tax: "
            + "a savings rate of \(percent)."
    }
}

/// One thing a statements' import remembered for next time, on Done:
/// "How export (3).csv is read" for "its bank's next statement".
struct ImportRemembered: Hashable, Sendable, Identifiable {
    var title: String
    /// What it applies to.
    var scope: String
    var id: String

    init(title: String, scope: String, id: String? = nil) {
        self.title = title
        self.scope = scope
        self.id = id ?? title
    }

    /// What saving `profiles` remembers that `before` didn't: how each
    /// file with a new profile is read, each rule no statement profile
    /// had, and each line's answer its profile didn't have ("Notaio Bianchi
    /// was a one-off" in "Mar 2025"). `fileNames` names the batch's files
    /// by ID; `after` names the accounts moves go to.
    static func list(_ profiles: [StatementBatch.RememberedProfile], fileNames: [Int: String], before: Library,
                     after: Library, locale: Locale = .current) -> [ImportRemembered] {
        var items: [ImportRemembered] = []
        for profile in profiles where profile.isNew {
            guard let first = profile.files.first, let name = fileNames[first] else { continue }
            items.append(ImportRemembered(title: "How \(name) is read", scope: "its bank's next statement"))
        }
        let known = Set(before.importProfiles.values.filter { $0.layout == .statement }.flatMap(\.rules).map(Key.init))
        var listed = Set<Key>()
        for rule in profiles.flatMap(\.profile.rules) {
            let key = Key(rule)
            guard !known.contains(key), !listed.contains(key) else { continue }
            listed.insert(key)
            if let account = rule.account {
                let name = after.accounts[account]?.name ?? account.rawValue
                items.append(ImportRemembered(title: "\(rule.match) moves to \(name)", scope: "every month"))
            } else {
                items.append(ImportRemembered(title: "\(rule.match) \(Self.words(for: rule.statementClass))",
                                              scope: "every account"))
            }
        }
        for profile in profiles {
            let had = Set(before.importProfiles[profile.profile.id]?.answers ?? [])
            for answer in profile.profile.answers where !had.contains(answer) {
                let sender = StatementWords.sender(of: answer.match)
                let title = "\(sender.isEmpty ? answer.match : sender) \(Self.pastWords(for: answer.statementClass))"
                let month = GlanceText.shortMonthAndYear(answer.date, locale: locale)
                items.append(ImportRemembered(title: title, scope: month, id: "\(title) \(answer.date)"))
            }
        }
        return items
    }

    /// "was income", "was a one-off", "moved between your accounts".
    static func pastWords(for statementClass: StatementClass) -> String {
        switch statementClass {
        case .income: "was income"
        case .spending: "was spending"
        case .oneOff: "was a one-off"
        case .tax: "was tax"
        case .transfer: "moved between your accounts"
        case .interest: "was interest"
        case .ignore: "was left out"
        default: "was \(statementClass.rawValue)"
        }
    }

    /// "is income", "is a one-off", "moves between your accounts".
    static func words(for statementClass: StatementClass) -> String {
        switch statementClass {
        case .income: "is income"
        case .spending: "is spending"
        case .oneOff: "is a one-off"
        case .tax: "is tax"
        case .transfer: "moves between your accounts"
        case .interest: "is interest"
        case .ignore: "is left out"
        default: "is \(statementClass.rawValue)"
        }
    }

    /// A rule by its words, ignoring case, its class and its account.
    private struct Key: Hashable {
        var match: String
        var statementClass: StatementClass
        var account: AccountID?

        init(_ rule: StatementRule) {
            match = rule.match.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            statementClass = rule.statementClass
            account = rule.account
        }
    }
}
