import Foundation
import Importer
import Model

/// Ledger-cli and hledger journal files, by extension.
enum LedgerFiles {
    static let extensions: Set<String> = ["ledger", "journal", "hledger", "j", "dat"]

    static func isJournal(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

/// A journal import in progress (IMPORT.md, "Ledger journals"): the files
/// chosen, what the app may read, the journal as read, and the mapping.
/// ``ImportFlow`` holds one while the Import screen imports journals, and
/// makes its preview the import's preview.
struct LedgerImportState: Sendable {
    /// The files chosen, in the order given.
    var roots: [URL]
    /// Files and folders the app may read: the chosen files, and folders
    /// granted for their includes.
    var grants: [URL]
    var journal: LedgerJournal
    /// The mapping, a ledger `ImportProfile`.
    var session: LedgerImportSession
    /// Records after this day are left out (today).
    var until: CalendarDate
    /// The latest preview, from ``refresh(against:)``.
    private(set) var result: LedgerImportPreview?

    init(roots: [URL], grants: [URL], journal: LedgerJournal, profile: ImportProfile?,
         until: CalendarDate = .today()) {
        self.roots = roots
        self.grants = grants
        self.journal = journal
        session = LedgerImportSession(journal: journal, profile: profile)
        self.until = until
    }

    /// Makes the preview again against `library`.
    mutating func refresh(against library: Library) {
        result = session.preview(against: library, until: until)
    }

    /// E.g. `main.journal`, or `2023.journal and 1 more`.
    var fileName: String {
        guard let first = roots.first?.lastPathComponent else { return "Journal" }
        return roots.count == 1 ? first : "\(first) and \(roots.count - 1) more"
    }

    /// E.g. "20 transactions, 1 Jan 2024 – 30 Apr 2024".
    func summary(locale: Locale = .current) -> String {
        let count = journal.transactions.count
        var text = count == 1 ? "1 transaction" : "\(count) transactions"
        if let first = journal.firstDate, let last = journal.lastDate {
            text += ", \(AmountFormat.mediumDate(first, locale: locale)) – \(AmountFormat.mediumDate(last, locale: locale))"
        }
        return text
    }

    /// The saved ledger profiles, those that know most of the journal's
    /// accounts first.
    func profileFits(_ profiles: [ImportProfile]) -> [LedgerProfileFit] {
        LedgerProfileFit.rank(journal, profiles: profiles)
    }
}

/// How well a saved ledger profile fits a journal: how many of its accounts
/// the profile names (mapped or ignored).
struct LedgerProfileFit: Hashable, Sendable, Identifiable {
    var profile: ImportProfile
    var known: Int
    var id: ImportProfileID { profile.id }

    /// Whether it's worth using right away.
    var fits: Bool { known > 0 }

    /// E.g. "Knows 5 of the journal's accounts".
    var summary: String {
        switch known {
        case 0: "Knows none of the journal's accounts"
        case 1: "Knows 1 of the journal's accounts"
        default: "Knows \(known) of the journal's accounts"
        }
    }

    static func rank(_ journal: LedgerJournal, profiles: [ImportProfile]) -> [LedgerProfileFit] {
        let accounts = Set(journal.accounts.map { $0.lowercased() })
        return profiles.filter(\.isLedger).map { profile in
            let named = Array(profile.matches.accounts.keys) + (profile.ledger?.ignore ?? [])
            return LedgerProfileFit(profile: profile, known: Set(named.map { $0.lowercased() })
                .filter(accounts.contains).count)
        }.sorted { lhs, rhs in
            if lhs.known != rhs.known { return lhs.known > rhs.known }
            return (lhs.profile.name, lhs.profile.id) < (rhs.profile.name, rhs.profile.id)
        }
    }
}
