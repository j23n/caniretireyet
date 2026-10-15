import Model

/// What was decided about a preview's proposals and conflicts, kept apart
/// from the preview so it survives the preview being made again after the
/// mapping changes: the app's choices on Accounts and Review, or the
/// command line's flags.
public struct ImportDecisions: Hashable, Sendable {
    /// Changes to proposed accounts, by ID.
    public var accounts: [AccountID: ProposalEdit<AccountKind>] = [:]
    /// Changes to proposed instruments, by ID.
    public var instruments: [InstrumentID: ProposalEdit<InstrumentKind>] = [:]
    /// Proposed account changes accepted (`true`) or rejected (`false`).
    public var accountChanges: [AccountChangeKey: Bool] = [:]
    /// The policy for every conflict; `nil` keeps the profile's.
    public var conflictPolicy: ConflictPolicy?
    /// Conflicts decided one by one, used while the policy is `ask`.
    public var resolutions: [ImportRecordKey: ConflictPolicy] = [:]
    /// Whether every proposed account, instrument, closing or switch to
    /// recording trades not decided above is accepted; `nil` keeps the
    /// preview's. A statement's purchase and sale (their `statementRow`)
    /// stay as the preview has them: the line's answer asked for them.
    public var acceptsNewAccounts: Bool?
    public var acceptsNewInstruments: Bool?
    public var acceptsClosings: Bool?
    public var acceptsTradesMode: Bool?

    public init(acceptsNewAccounts: Bool? = nil, acceptsNewInstruments: Bool? = nil, acceptsClosings: Bool? = nil,
                acceptsTradesMode: Bool? = nil) {
        self.acceptsNewAccounts = acceptsNewAccounts
        self.acceptsNewInstruments = acceptsNewInstruments
        self.acceptsClosings = acceptsClosings
        self.acceptsTradesMode = acceptsTradesMode
    }

    /// `preview` with these decisions applied.
    public func applied(to preview: ImportPreview) -> ImportPreview {
        var preview = preview
        for index in preview.newAccounts.indices {
            if preview.newAccounts[index].statementRow == nil, let accepted = acceptsNewAccounts {
                preview.newAccounts[index].isAccepted = accepted
            }
            guard let edit = accounts[preview.newAccounts[index].account.id] else { continue }
            var account = preview.newAccounts[index].account
            if let name = edit.name { account.name = name }
            if let kind = edit.kind { account.kind = kind }
            if let currency = edit.currency { account.currency = currency }
            preview.newAccounts[index].account = account
            if let accepted = edit.isAccepted { preview.newAccounts[index].isAccepted = accepted }
        }
        for index in preview.newInstruments.indices {
            if let accepted = acceptsNewInstruments { preview.newInstruments[index].isAccepted = accepted }
            guard let edit = instruments[preview.newInstruments[index].instrument.id] else { continue }
            var instrument = preview.newInstruments[index].instrument
            if let name = edit.name { instrument.name = name }
            if let kind = edit.kind, kind != instrument.kind { instrument = instrument.changingKind(to: kind) }
            if let currency = edit.currency { instrument.currency = currency }
            preview.newInstruments[index].instrument = instrument
            if let accepted = edit.isAccepted { preview.newInstruments[index].isAccepted = accepted }
        }
        for index in preview.accountChanges.indices {
            let change = preview.accountChanges[index]
            switch change.change {
            case .close where change.statementRow == nil:
                if let accepted = acceptsClosings { preview.accountChanges[index].isAccepted = accepted }
            case .recordTrades:
                if let accepted = acceptsTradesMode { preview.accountChanges[index].isAccepted = accepted }
            default:
                break
            }
            if let accepted = accountChanges[AccountChangeKey(change)] {
                preview.accountChanges[index].isAccepted = accepted
            }
        }
        let policy = conflictPolicy ?? preview.conflictPolicy
        for index in preview.records.indices where preview.records[index].status == .conflict {
            preview.records[index].resolution = policy == .ask
                ? resolutions[preview.records[index].id] ?? .ask
                : policy
        }
        return preview
    }
}

/// Changes to a proposed account or instrument. Fields left `nil` keep the
/// proposal's.
public struct ProposalEdit<Kind: Hashable & Sendable>: Hashable, Sendable {
    public var name: String?
    public var kind: Kind?
    public var currency: CurrencyCode?
    public var isAccepted: Bool?

    public init(name: String? = nil, kind: Kind? = nil, currency: CurrencyCode? = nil, isAccepted: Bool? = nil) {
        self.name = name
        self.kind = kind
        self.currency = currency
        self.isAccepted = isAccepted
    }
}

/// A proposed account change by account and kind of change (its date can
/// move when the mapping changes).
public struct AccountChangeKey: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case close, openEarlier, recordTrades
    }

    public var account: AccountID
    public var kind: Kind

    public init(_ proposal: AccountChangeProposal) {
        account = proposal.account
        kind = switch proposal.change {
        case .close: .close
        case .openEarlier: .openEarlier
        case .recordTrades: .recordTrades
        }
    }
}

private extension Instrument {
    /// The instrument with another kind, and the asset class and unit that
    /// usually go with it (``InstrumentKind/usualAssetClass(name:)``: a metal
    /// is gold, weighed in grams, unless its name says another metal). A
    /// crypto instrument keeps its unit.
    func changingKind(to kind: InstrumentKind) -> Instrument {
        var instrument = self
        instrument.kind = kind
        instrument.assetClasses = .single(kind.usualAssetClass(name: name))
        if let unit = kind.usualUnit { instrument.unit = unit }
        return instrument
    }
}
