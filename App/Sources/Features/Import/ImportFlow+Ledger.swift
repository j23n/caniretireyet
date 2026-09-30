import Foundation
import Importer
import Model

/// What a ledger account's picker in the Accounts step can choose.
enum LedgerAccountChoice: Hashable, Sendable {
    /// Where its parent goes, or what the importer proposes.
    case proposed
    /// An account of the library, or a new one another ledger account has.
    case account(AccountID)
    /// A new library account of its own.
    case newAccount
    /// Left out: money moving to it counts as taken out.
    case ignore
}

/// What a commodity's picker in the Commodities step can choose.
enum LedgerCommodityChoice: Hashable, Sendable {
    /// Cash in its currency, the instrument it matched, or a new one.
    case proposed
    case instrument(InstrumentID)
    /// A new instrument of its own.
    case newInstrument
    case ignore
}

/// One choice in a picker.
struct LedgerChoiceOption<Choice: Hashable & Sendable>: Hashable, Sendable, Identifiable {
    var choice: Choice
    var title: String
    var id: Choice { choice }
}

/// Names for the journal import's options.
enum LedgerChoices {
    static let frequencies = LedgerSnapshotFrequency.knownValues

    static func frequencyName(_ frequency: LedgerSnapshotFrequency) -> String {
        switch frequency {
        case .quarter: "Quarter ends"
        case .activity: "Every date with a posting"
        default: "Month ends"
        }
    }
}

/// The journal import's steps (IMPORT.md, "Ledger journals"): Files (in
/// the File step), Accounts (ledger accounts to library accounts, and
/// returns), Commodities (to currencies and instruments). Preview and Done
/// are the spreadsheet import's.
extension ImportFlow {
    /// Whether the files are ledger journals.
    var isLedger: Bool { ledger != nil }

    /// The journal import's latest preview, with its account and commodity rows.
    var ledgerResult: LedgerImportPreview? { ledger?.result }

    /// The saved ledger profiles, best fit first.
    var ledgerProfileFits: [LedgerProfileFit] {
        ledger?.profileFits(Array(library.importProfiles.values)) ?? []
    }

    // MARK: Accounts

    /// Assets and liabilities, as a tree in name order.
    var ledgerNetWorthRows: [LedgerAccountRow] {
        ledgerResult?.accounts.filter(\.role.isNetWorth) ?? []
    }

    /// Income, expenses, equity and the rest, as a tree in name order.
    var ledgerOtherRows: [LedgerAccountRow] {
        ledgerResult?.accounts.filter { !$0.role.isNetWorth } ?? []
    }

    /// The picker's value for an account: what's set on it, else `.proposed`.
    func ledgerChoice(for row: LedgerAccountRow) -> LedgerAccountChoice {
        guard row.source == .explicit else { return .proposed }
        switch row.mapping {
        case .account(let id): return .account(id)
        case .ignored: return .ignore
        default: return .proposed
        }
    }

    /// Where an account goes now, e.g. "Directa (same name)", "New: Visa",
    /// "Directa, as Broker", "Left out".
    func ledgerTargetSummary(_ row: LedgerAccountRow) -> String {
        let how: String? = switch row.source {
        case .matched: "same name"
        case .inherited(let parent): "as \(parent.split(separator: ":").last.map(String.init) ?? parent)"
        default: nil
        }
        let target: String = switch row.mapping {
        case .account(let id):
            (preview?.newAccounts.contains { $0.account.id == id } == true ? "New: " : "") + accountName(id)
        case .ignored: "Left out"
        case .split: "Split: its subaccounts go to their own accounts"
        case .returns: "Returns"
        case .flow: "Money in or out"
        }
        return how.map { "\(target) (\($0))" } ?? target
    }

    /// The choices for an account: as proposed, the library's accounts, new
    /// ones, a new one of its own, or left out.
    func ledgerAccountOptions(for row: LedgerAccountRow) -> [LedgerChoiceOption<LedgerAccountChoice>] {
        let proposed = row.source == .explicit ? "As proposed" : "As proposed: \(ledgerTargetSummary(row))"
        var options = [LedgerChoiceOption(choice: LedgerAccountChoice.proposed, title: proposed)]
        options += accountChoices.map { LedgerChoiceOption(choice: .account($0.id), title: $0.name) }
        for proposal in preview?.newAccounts ?? [] where library.accounts[proposal.account.id] == nil {
            options.append(LedgerChoiceOption(choice: .account(proposal.account.id),
                                              title: "New: \(proposal.account.name)"))
        }
        if case .account(let id) = ledgerChoice(for: row), !options.contains(where: { $0.choice == .account(id) }) {
            options.append(LedgerChoiceOption(choice: .account(id), title: accountName(id)))
        }
        options.append(LedgerChoiceOption(choice: .newAccount, title: "New account"))
        options.append(LedgerChoiceOption(choice: .ignore, title: "Leave out"))
        return options
    }

    /// Sends a ledger account (with its subaccounts) where chosen.
    mutating func setLedgerAccount(_ name: String, to choice: LedgerAccountChoice) {
        var newID: AccountID?
        if choice == .newAccount {
            // Unique among the library's and the other new accounts (its own proposal can keep its ID).
            let row = ledgerResult?.account(name)
            var own: AccountID?
            if case .account(let id)? = row?.mapping { own = id }
            let taken = Array(library.accounts.keys) + (preview?.newAccounts.map(\.account.id) ?? []).filter { $0 != own }
                + (ledger.map { Array($0.session.profile.matches.accounts.values) } ?? [])
            newID = AccountID.make(from: row?.suggestedAccountName ?? name, existing: taken)
        }
        editLedger { ledger in
            switch choice {
            case .proposed: ledger.session.resetAccount(name)
            case .account(let id): ledger.session.map(account: name, to: id)
            case .newAccount: if let newID { ledger.session.map(account: name, to: newID) }
            case .ignore: ledger.session.ignore(account: name)
            }
        }
    }

    /// Marks an income or expense account (with its subaccounts) as returns or not.
    mutating func setLedgerReturns(_ isReturns: Bool, for name: String) {
        editLedger { $0.session.setReturns(isReturns, for: name) }
    }

    /// E.g. "Assets:Broker:Directa · 12 postings · 1.063 EUR, 15 VWCE.MI".
    func ledgerDetail(_ row: LedgerAccountRow, locale: Locale = .current) -> String {
        var parts = [row.name]
        if row.postings > 0 { parts.append(row.postings == 1 ? "1 posting" : "\(row.postings) postings") }
        if !row.balance.isEmpty {
            parts.append(row.balance.prefix(3).map {
                "\(AmountFormat.number($0.quantity, maxDigits: 8, locale: locale)) \($0.commodity)"
            }.joined(separator: ", ") + (row.balance.count > 3 ? ", …" : ""))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Commodities

    var ledgerCommodityRows: [LedgerCommodityRow] {
        ledgerResult?.commodities ?? []
    }

    func ledgerCommodityChoice(for row: LedgerCommodityRow) -> LedgerCommodityChoice {
        guard row.source == .explicit else { return .proposed }
        switch row.mapping {
        case .instrument(let id): return .instrument(id)
        case .ignored: return .ignore
        case .currency: return .proposed
        }
    }

    /// What a commodity is now, e.g. "Cash in EUR", "Vanguard FTSE All-World (matched)", "New: BTC".
    func ledgerCommoditySummary(_ row: LedgerCommodityRow) -> String {
        switch row.mapping {
        case .currency(let code): return "Cash in \(code.rawValue)"
        case .ignored: return "Left out"
        case .instrument(let id):
            if preview?.newInstruments.contains(where: { $0.instrument.id == id }) == true {
                return "New: \(instrumentName(id))"
            }
            return instrumentName(id) + (row.source == .matched ? " (matched)" : "")
        }
    }

    func ledgerCommodityOptions(for row: LedgerCommodityRow) -> [LedgerChoiceOption<LedgerCommodityChoice>] {
        let proposed = row.source == .explicit ? "As proposed" : "As proposed: \(ledgerCommoditySummary(row))"
        var options = [LedgerChoiceOption(choice: LedgerCommodityChoice.proposed, title: proposed)]
        options += instrumentChoices.map { LedgerChoiceOption(choice: .instrument($0.id), title: $0.name) }
        for proposal in preview?.newInstruments ?? [] where library.instruments[proposal.instrument.id] == nil {
            options.append(LedgerChoiceOption(choice: .instrument(proposal.instrument.id),
                                              title: "New: \(proposal.instrument.name)"))
        }
        if case .instrument(let id) = ledgerCommodityChoice(for: row),
           !options.contains(where: { $0.choice == .instrument(id) }) {
            options.append(LedgerChoiceOption(choice: .instrument(id), title: instrumentName(id)))
        }
        options.append(LedgerChoiceOption(choice: .newInstrument, title: "New instrument"))
        options.append(LedgerChoiceOption(choice: .ignore, title: "Leave out"))
        return options
    }

    mutating func setLedgerCommodity(_ symbol: String, to choice: LedgerCommodityChoice) {
        var newID: InstrumentID?
        if choice == .newInstrument {
            let taken = Array(library.instruments.keys) + (preview?.newInstruments.map(\.instrument.id) ?? [])
            newID = InstrumentID.make(from: symbol.isEmpty ? "commodity" : symbol, existing: taken)
        }
        editLedger { ledger in
            switch choice {
            case .proposed: ledger.session.resetCommodity(symbol)
            case .instrument(let id): ledger.session.map(commodity: symbol, to: id)
            case .newInstrument: if let newID { ledger.session.map(commodity: symbol, to: newID) }
            case .ignore: ledger.session.ignore(commodity: symbol)
            }
        }
    }

    // MARK: Options

    var ledgerFrequency: LedgerSnapshotFrequency {
        ledger?.session.settings.effectiveFrequency ?? .month
    }

    mutating func setLedgerFrequency(_ frequency: LedgerSnapshotFrequency) {
        editLedger { $0.session.setFrequency(frequency) }
    }

    var ledgerRecordsTransactionPrices: Bool {
        ledger?.session.settings.effectiveTransactionPrices ?? true
    }

    mutating func setLedgerTransactionPrices(_ recorded: Bool) {
        editLedger { $0.session.setTransactionPrices(recorded) }
    }

    /// What couldn't be valued or converted, for the Preview step.
    var ledgerNotes: [String] {
        ledgerResult?.notes.map(\.description) ?? []
    }
}
