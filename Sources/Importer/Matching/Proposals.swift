import Model

/// How a name in the file was linked to an account or instrument.
public struct NameMatch: Hashable, Sendable {
    public enum Method: String, Hashable, Sendable {
        /// The profile gives the ID: a column's or the constants' `account` or `instrument`.
        case profile
        /// A match remembered in the profile's `matches`.
        case remembered
        /// The name, ID or ticker of an existing account or instrument, ignoring case and accents.
        case existing
        /// Nothing matched: a new account or instrument is proposed.
        case new
    }

    /// The name as written in the file (a header or a cell), or the ID the profile gives.
    public var name: String
    /// Set when the name stands for an account.
    public var account: AccountID?
    /// Set when the name stands for an instrument.
    public var instrument: InstrumentID?
    public var method: Method

    public init(name: String, account: AccountID? = nil, instrument: InstrumentID? = nil, method: Method) {
        self.name = name
        self.account = account
        self.instrument = instrument
        self.method = method
    }
}

/// A new account for names the library doesn't know. Edit its kind,
/// currency or name before applying (not its ID), or reject it to skip its records.
public struct AccountProposal: Hashable, Sendable {
    public var account: Account
    /// The names in the file it stands for.
    public var names: [String]
    /// Whether applying creates it (default `true`).
    public var isAccepted = true
}

/// A new instrument for names the library doesn't know. Edit it before
/// applying (not its ID), or reject it to skip its records.
public struct InstrumentProposal: Hashable, Sendable {
    public var instrument: Instrument
    public var names: [String]
    public var isAccepted = true
}

/// A change to an account's lifecycle that the file suggests.
public struct AccountChangeProposal: Hashable, Sendable, CustomStringConvertible {
    public enum Change: Hashable, Sendable {
        /// Its values stop before the file's last date: close it the day
        /// after its last value.
        case close(on: CalendarDate)
        /// The file has values from before the day it was opened: open it
        /// on the first of them.
        case openEarlier(on: CalendarDate)
        /// The file has trades for an account that records balances or
        /// holdings: make it record trades (`"valuation": "trades"`), so its
        /// holdings come from its trades. Rejected, its trades are left out.
        case recordTrades
    }

    public var account: AccountID
    public var change: Change
    /// Whether applying makes the change. The importer proposes closings
    /// and switches to trades unaccepted, so they happen only when chosen
    /// (an account updated less often than the file isn't closed); earlier
    /// openings are accepted.
    public var isAccepted: Bool

    public init(account: AccountID, change: Change, isAccepted: Bool = true) {
        self.account = account
        self.change = change
        self.isAccepted = isAccepted
    }

    public var description: String {
        switch change {
        case .close(let date): "Close \(account) on \(date)"
        case .openEarlier(let date): "Open \(account) on \(date)"
        case .recordTrades: "Record trades in \(account)"
        }
    }

    /// Whether this is a proposal to make the account record trades.
    public var recordsTrades: Bool {
        change == .recordTrades
    }
}
