import Foundation
import Model

/// A journal import in progress: the journal as read and the mapping, held
/// as an `ImportProfile` with the `ledger` layout (IMPORT.md, "Ledger journals").
///
/// Ledger accounts go to library accounts, a whole subtree at once:
/// `matches.accounts` maps a ledger account (and everything below it) to
/// a library account, and `ledger.ignore` leaves one out. Accounts nothing
/// is set for are grouped (`Assets:Broker:Directa` with its `Cash` and
/// holdings) and matched to the library's accounts by name, or proposed as
/// new ones. Commodities are currencies, instruments (`matches.instruments`,
/// else by ticker or name, else new) or ignored.
///
/// ``preview(against:until:)`` turns the journal into valuations, prices and
/// FX rates and compares them with the library like any import, so applying
/// the preview works as for a spreadsheet, and importing the same journal
/// again changes nothing.
public struct LedgerImportSession: Sendable {
    public let journal: LedgerJournal
    /// The mapping. Its `ledger` section and `matches` change with the helpers below.
    public var profile: ImportProfile

    /// A session with a saved profile, or a new mapping the importer proposes.
    public init(journal: LedgerJournal, profile: ImportProfile? = nil) {
        self.journal = journal
        var profile = profile ?? ImportProfile(id: "ledger", name: "Journal", layout: .ledger)
        profile.layout = .ledger
        self.profile = profile
    }

    /// The profile's `ledger` section; an empty section is left out.
    public var settings: LedgerImportSettings {
        get { profile.ledger ?? LedgerImportSettings() }
        set { profile.ledger = newValue == LedgerImportSettings() ? nil : newValue }
    }

    // MARK: - Accounts

    /// Sends a ledger account and its subaccounts to a library account
    /// (existing, or new with an ID not in the library).
    public mutating func map(account: String, to id: AccountID) {
        forget(account: account)
        profile.matches.accounts[account] = id
    }

    /// Leaves a ledger account and its subaccounts out.
    public mutating func ignore(account: String) {
        forget(account: account)
        settings.ignore.append(account)
    }

    /// Forgets what was set on a ledger account: it goes where its parent
    /// goes, or where the importer proposes.
    public mutating func resetAccount(_ account: String) {
        forget(account: account)
    }

    private mutating func forget(account: String) {
        let key = LedgerMapper.key(account)
        for name in profile.matches.accounts.keys where LedgerMapper.key(name) == key {
            profile.matches.accounts[name] = nil
        }
        settings.ignore.removeAll { LedgerMapper.key($0) == key }
    }

    /// Marks an income, expense or other account (and its subaccounts) as
    /// returns (`true`), money in or out (`false`), or as its name suggests (`nil`).
    public mutating func setReturns(_ isReturns: Bool?, for account: String) {
        let key = LedgerMapper.key(account)
        settings.returns.removeAll { LedgerMapper.key($0) == key }
        settings.flows.removeAll { LedgerMapper.key($0) == key }
        switch isReturns {
        case true?: settings.returns.append(account)
        case false?: settings.flows.append(account)
        case nil: break
        }
    }

    /// The accounts that count toward net worth; empty for the defaults.
    public mutating func setRoots(_ roots: [String]) {
        settings.roots = roots == LedgerImportSettings.defaultRoots ? [] : roots
    }

    // MARK: - Commodities

    /// Makes a commodity an instrument (existing, or new with an ID not in the library).
    public mutating func map(commodity: String, to id: InstrumentID) {
        resetCommodity(commodity)
        profile.matches.instruments[commodity] = id
    }

    /// Leaves a commodity out.
    public mutating func ignore(commodity: String) {
        resetCommodity(commodity)
        settings.ignoreCommodities.append(commodity)
    }

    /// Forgets what was set on a commodity: the importer proposes again.
    public mutating func resetCommodity(_ commodity: String) {
        profile.matches.instruments[commodity] = nil
        settings.ignoreCommodities.removeAll { $0 == commodity }
    }

    // MARK: - Options

    public mutating func setFrequency(_ frequency: LedgerSnapshotFrequency) {
        settings.frequency = frequency == .month ? nil : frequency
    }

    /// Whether `@` prices on transactions become price records too.
    public mutating func setTransactionPrices(_ recorded: Bool) {
        settings.transactionPrices = recorded ? nil : false
    }

    // MARK: - Preview

    /// What importing the journal would do: its valuations (one per library
    /// account and snapshot date, with flows and purchase costs), prices and
    /// FX rates compared with the library, the accounts and instruments to
    /// create, closings, and notes. Records dated after `until` (normally
    /// today) are left out. Nothing is written.
    public func preview(against library: Library, until: CalendarDate? = nil) -> LedgerImportPreview {
        let settings = self.settings
        let mapper = LedgerMapper(journal: journal, library: library, settings: settings, matches: profile.matches)
        var builder = LedgerSnapshotBuilder(journal: journal, mapper: mapper, library: library, settings: settings,
                                            until: until)
        builder.build()

        let resolution = profile.effectiveOnConflict
        let records = builder.records.sorted { $0.key < $1.key }.map { record in
            let existing = library.record(for: record.key)
            let outcome = RecordMerge.evaluate(record, existing: existing)
            return ImportRecordPreview(imported: record, status: outcome.status, existing: existing,
                                       incoming: outcome.overwritten, cells: [], resolution: resolution)
        }
        var preview = ImportPreview(records: records, conflictPolicy: resolution, firstDate: journal.firstDate,
                                    lastDate: journal.lastDate)
        let usedAccounts = Set(records.compactMap(\.imported.key.account))
        preview.newAccounts = mapper.newAccounts.values.filter { usedAccounts.contains($0.id) }
            .sorted { $0.id < $1.id }
            .map { AccountProposal(account: $0, names: mapper.newAccountNames[$0.id] ?? []) }
        let usedInstruments = Set(records.flatMap { record in
            record.imported.positions.map(\.instrument) + [record.imported.key.instrument].compactMap { $0 }
        })
        preview.newInstruments = mapper.newInstruments.values.filter { usedInstruments.contains($0.id) }
            .sorted { $0.id < $1.id }
            .map { InstrumentProposal(instrument: $0, names: mapper.newInstrumentNames[$0.id] ?? []) }
        preview.accountChanges = accountChanges(builder, records: records, library: library, mapper: mapper)

        let accounts = mapper.rows
        let commodities = mapper.commodityRows
        for row in accounts where row.isGroupHead {
            guard case .account(let id) = row.mapping else { continue }
            preview.nameMatches.append(NameMatch(name: row.name, account: id, method: Self.method(row.source)))
        }
        for row in commodities {
            guard case .instrument(let id) = row.mapping else { continue }
            let method: NameMatch.Method = switch row.source {
            case .explicit: .remembered
            case .new: .new
            default: .existing
            }
            preview.nameMatches.append(NameMatch(name: row.symbol, instrument: id, method: method))
        }
        return LedgerImportPreview(preview: preview, accounts: accounts, commodities: commodities,
                                   notes: builder.notes)
    }

    private static func method(_ source: LedgerAccountRow.Source) -> NameMatch.Method {
        switch source {
        case .explicit, .inherited: .remembered
        case .new: .new
        default: .existing
        }
    }

    /// Closing accounts whose balance reaches zero and stays there, and
    /// opening earlier the ones the journal has postings in before they opened.
    private func accountChanges(_ builder: LedgerSnapshotBuilder, records: [ImportRecordPreview], library: Library,
                                mapper: LedgerMapper) -> [AccountChangeProposal] {
        let imported = Set(records.map(\.imported.key))
        var changes: [AccountChangeProposal] = []
        for (id, date) in builder.closings.sorted(by: { $0.key < $1.key }) {
            guard let account = library.accounts[id] ?? mapper.newAccounts[id], account.closed == nil else { continue }
            let later = library.valuations(for: id).contains { valuation in
                valuation.date > date && !imported.contains(.valuation(valuation.key))
                    && ((valuation.balance ?? 0) != 0 || (valuation.cash ?? 0) != 0
                        || valuation.positions.contains { $0.quantity != 0 })
            }
            if !later { changes.append(AccountChangeProposal(account: id, change: .close(on: date))) }
        }
        for (id, first) in builder.firstPostings.sorted(by: { $0.key < $1.key }) {
            if let account = library.accounts[id], first < account.opened {
                changes.append(AccountChangeProposal(account: id, change: .openEarlier(on: first)))
            }
        }
        return changes.sorted { $0.account < $1.account }
    }

    // MARK: - Profile

    /// The mapping as a profile to save in `imports/<id>.json`, so the next
    /// import of the journal is one step: every library account and
    /// instrument the preview used that exists in `library` (pass the library
    /// after the import) is remembered in `matches`, and returns accounts
    /// found by name are written out.
    ///
    /// Proposed new accounts that were declined in `preview.preview`
    /// (``AccountProposal/isAccepted`` false) and aren't in `library` are
    /// added to `ledger.ignore`, the ledger accounts heading them, so the
    /// next import leaves them out instead of proposing them again.
    public func makeProfile(id: ImportProfileID, name: String, from preview: LedgerImportPreview,
                            library: Library) -> ImportProfile {
        var session = self
        session.profile.id = id
        session.profile.name = name
        let explicit = Set(profile.matches.accounts.keys.map(LedgerMapper.key))
        let declined = Set(preview.preview.newAccounts.filter { !$0.isAccepted }.map(\.account.id))
        for row in preview.accounts where row.role.isNetWorth && row.isGroupHead {
            guard case .account(let account) = row.mapping else { continue }
            if declined.contains(account), library.accounts[account] == nil {
                session.ignore(account: row.name)
                continue
            }
            guard library.accounts[account] != nil, !explicit.contains(LedgerMapper.key(row.name)) else { continue }
            session.profile.matches.accounts[row.name] = account
        }
        for row in preview.commodities {
            guard case .instrument(let instrument) = row.mapping, library.instruments[instrument] != nil,
                  row.source != .explicit else { continue }
            session.profile.matches.instruments[row.symbol] = instrument
        }
        let returns = Dictionary(preview.accounts.map { ($0.name, $0.mapping == .returns) }, uniquingKeysWith: { a, _ in a })
        for row in preview.accounts where !row.role.isNetWorth && row.source == .byName {
            let isReturns = row.mapping == .returns
            let parent = LedgerMapper.parent(of: row.name).flatMap { returns[$0] } ?? false
            if isReturns != parent { session.setReturns(isReturns, for: row.name) }
        }
        return session.profile
    }
}

/// What importing a journal would do (``LedgerImportSession/preview(against:until:)``).
public struct LedgerImportPreview: Hashable, Sendable {
    /// The records, proposals and changes, as for any import: apply it with
    /// ``ImportPreview/apply(to:)``.
    public var preview: ImportPreview
    /// Every ledger account, sorted by name, with its role and where it goes.
    public var accounts: [LedgerAccountRow]
    /// Every commodity held in a net-worth account, and what it is.
    public var commodities: [LedgerCommodityRow]
    /// What couldn't be valued or converted, and what was left out.
    public var notes: [LedgerDiagnostic]

    public init(preview: ImportPreview, accounts: [LedgerAccountRow], commodities: [LedgerCommodityRow],
                notes: [LedgerDiagnostic]) {
        self.preview = preview
        self.accounts = accounts
        self.commodities = commodities
        self.notes = notes
    }

    /// The row of a ledger account.
    public func account(_ name: String) -> LedgerAccountRow? {
        accounts.first { $0.name == name }
    }

    /// The row of a commodity.
    public func commodity(_ symbol: String) -> LedgerCommodityRow? {
        commodities.first { $0.symbol == symbol }
    }
}
