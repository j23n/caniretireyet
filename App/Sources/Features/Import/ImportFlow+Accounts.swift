import Foundation
import Importer
import Model

/// What a name in the file is matched to.
enum NameTarget: Hashable, Sendable {
    case account(AccountID)
    case instrument(InstrumentID)
    /// A new account or instrument, proposed for this name.
    case new
    /// Not imported: the column the name heads is ignored (wide layout).
    case ignore
}

/// One choice in a name's picker.
struct NameOption: Hashable, Sendable, Identifiable {
    var target: NameTarget
    var title: String
    var id: NameTarget { target }
}

/// A name in the file (a header or a cell) and what it's matched to, for
/// the Accounts step.
struct ImportNameRow: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case account
        case instrument
    }

    var kind: Kind
    /// The name as written in the file.
    var name: String
    var id: String { "\(kind.rawValue):\(name)" }
    var method: NameMatch.Method
    var target: NameTarget
    /// What it stands for, e.g. "Conto Fineco" or "New account".
    var summary: String
    /// Whether the match can be changed here; a column or constant that
    /// gives the ID is changed in Columns.
    var isEditable: Bool
    var options: [NameOption]

    /// How it was matched, e.g. "Same name", "Remembered".
    var methodTitle: String {
        switch method {
        case .profile: "Set in Columns"
        case .remembered: "Remembered"
        case .existing: "Same name"
        case .new: "Not in the library"
        }
    }
}

/// The Accounts step: names matched to accounts and instruments, the new
/// ones to create, proposed closings, and the note on debts.
extension ImportFlow {
    /// Every name in the file, accounts first, in the order the file has them.
    var nameRows: [ImportNameRow] {
        guard let preview, let session else { return [] }
        var rows: [ImportNameRow] = []
        var seen = Set<String>()
        let accounts = preview.nameMatches.filter { $0.account != nil }
        let instruments = preview.nameMatches.filter { $0.account == nil && $0.instrument != nil }
        for match in accounts + instruments {
            let kind: ImportNameRow.Kind = match.account != nil ? .account : .instrument
            guard seen.insert("\(kind.rawValue):\(match.name)").inserted else { continue }
            let remembered = kind == .account
                ? Self.remembered(match.name, in: session.profile.matches.accounts).map(\.rawValue)
                : Self.remembered(match.name, in: session.profile.matches.instruments).map(\.rawValue)
            let matchedID = match.account?.rawValue ?? match.instrument?.rawValue ?? ""
            let target: NameTarget
            if let remembered {
                target = kind == .account ? .account(AccountID(remembered)) : .instrument(InstrumentID(remembered))
            } else if match.method == .new {
                target = .new
            } else {
                target = kind == .account ? .account(AccountID(matchedID)) : .instrument(InstrumentID(matchedID))
            }
            let canBeNew = match.method == .new || remembered != nil
            let summary: String
            switch target {
            case .account(let id): summary = accountName(id)
            case .instrument(let id): summary = instrumentName(id)
            case .new: summary = kind == .account ? "New account" : "New instrument"
            case .ignore: summary = "Ignored"
            }
            var options = nameOptions(kind: kind, ownID: target == .new ? matchedID : nil, canBeNew: canBeNew)
            if !columns(headed: match.name).isEmpty {
                options.append(NameOption(target: .ignore, title: "Ignore the column"))
            }
            rows.append(ImportNameRow(
                kind: kind, name: match.name, method: match.method, target: target, summary: summary,
                isEditable: match.method != .profile, options: options))
        }
        return rows
    }

    /// The choices for a name: the library's accounts (or instruments),
    /// other names' new ones, and a new one of its own.
    private func nameOptions(kind: ImportNameRow.Kind, ownID: String?, canBeNew: Bool) -> [NameOption] {
        var options: [NameOption] = []
        switch kind {
        case .account:
            options = accountChoices.map { NameOption(target: .account($0.id), title: $0.name) }
            options += (preview?.newAccounts ?? []).filter { $0.account.id.rawValue != ownID }.map {
                NameOption(target: .account($0.account.id), title: "New: \($0.account.name)")
            }
            if canBeNew { options.append(NameOption(target: .new, title: "New account")) }
        case .instrument:
            options = instrumentChoices.map { NameOption(target: .instrument($0.id), title: $0.name) }
            options += (preview?.newInstruments ?? []).filter { $0.instrument.id.rawValue != ownID }.map {
                NameOption(target: .instrument($0.instrument.id), title: "New: \($0.instrument.name)")
            }
            if canBeNew { options.append(NameOption(target: .new, title: "New instrument")) }
        }
        return options
    }

    /// Matches a name to an account or instrument, remembered in the
    /// mapping (and in the profile, if saved); `.new` forgets the match, and
    /// `.ignore` ignores the column the name heads.
    mutating func match(_ row: ImportNameRow, to target: NameTarget) {
        guard row.isEditable, target != row.target else { return }
        let name = row.name
        if target == .ignore {
            for column in columns(headed: name) { setUse(.ignore, forColumn: column) }
            return
        }
        editSession { session in
            switch (row.kind, target) {
            case (.account, .account(let id)):
                session.match(account: name, to: id)
            case (.instrument, .instrument(let id)):
                session.match(instrument: name, to: id)
            case (.account, .new):
                for key in session.profile.matches.accounts.keys where Self.fold(key) == Self.fold(name) {
                    session.profile.matches.accounts[key] = nil
                }
            case (.instrument, .new):
                for key in session.profile.matches.instruments.keys where Self.fold(key) == Self.fold(name) {
                    session.profile.matches.instruments[key] = nil
                }
            default:
                break
            }
        }
    }

    /// Wide layout: the imported columns whose header is `name`.
    private func columns(headed name: String) -> [Int] {
        guard layout != .long else { return [] }
        return columnRows.filter { $0.header == name && $0.isValue }.map(\.column)
    }

    /// The remembered match for a name: exactly, then ignoring case and accents.
    private static func remembered<ID>(_ name: String, in matches: [String: ID]) -> ID? {
        if let id = matches[name] { return id }
        let folded = fold(name)
        return matches.keys.sorted().first { fold($0) == folded }.flatMap { matches[$0] }
    }

    /// A name without case, accents or surrounding spaces.
    static func fold(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    // MARK: New accounts and instruments

    /// Changes a proposed account (name, kind, currency, or whether it's created).
    mutating func editNewAccount(_ id: AccountID, _ change: (inout ProposalEdit<AccountKind>) -> Void) {
        editDecisions { decisions in
            var edit = decisions.accounts[id] ?? ProposalEdit()
            change(&edit)
            decisions.accounts[id] = edit
        }
    }

    /// Changes a proposed instrument (name, kind, currency, or whether it's created).
    mutating func editNewInstrument(_ id: InstrumentID, _ change: (inout ProposalEdit<InstrumentKind>) -> Void) {
        editDecisions { decisions in
            var edit = decisions.instruments[id] ?? ProposalEdit()
            change(&edit)
            decisions.instruments[id] = edit
        }
    }

    /// Accepts or rejects every proposed account and instrument.
    mutating func acceptAllNew(_ accepted: Bool) {
        let accounts = preview?.newAccounts.map(\.account.id) ?? []
        let instruments = preview?.newInstruments.map(\.instrument.id) ?? []
        editDecisions { decisions in
            for id in accounts { decisions.accounts[id, default: ProposalEdit()].isAccepted = accepted }
            for id in instruments { decisions.instruments[id, default: ProposalEdit()].isAccepted = accepted }
        }
    }

    // MARK: Account changes

    /// Accepts or rejects a proposed closing or earlier opening.
    mutating func setAccepted(_ accepted: Bool, for change: AccountChangeProposal) {
        editDecisions { $0.accountChanges[AccountChangeKey(change)] = accepted }
    }

    /// E.g. "Close Old bank on 1 Oct 2026", "Open Directa on 31 Jan 2024".
    func title(of change: AccountChangeProposal, locale: Locale = .current) -> String {
        let name = accountName(change.account)
        switch change.change {
        case .close(let date):
            return "Close \(name) on \(AmountFormat.mediumDate(date, locale: locale))"
        case .openEarlier(let date):
            return "Open \(name) earlier, on \(AmountFormat.mediumDate(date, locale: locale))"
        }
    }

    /// Why a change is proposed.
    func reason(for change: AccountChangeProposal) -> String {
        switch change.change {
        case .close: "Its values stop before the file's last date."
        case .openEarlier: "The file has values from before the day it was opened."
        }
    }

    // MARK: Debts

    /// Notes such as "“Mutuo”: positive amounts were read as debts (12 values)."
    var debtNotes: [String] {
        (preview?.issues ?? []).filter { issue in
            if case .positiveDebts = issue.kind { true } else { false }
        }.map(\.description)
    }

    /// Whether the file has balances of debt accounts, so its sign setting matters.
    var hasDebts: Bool {
        guard let preview else { return false }
        let debtAccounts = Set(library.accounts.values.filter(\.kind.isLiability).map(\.id))
            .union(preview.newAccounts.filter(\.account.kind.isLiability).map(\.account.id))
        return preview.records.contains { record in
            record.imported.balance != nil && record.imported.key.account.map { debtAccounts.contains($0) } == true
        }
    }
}
