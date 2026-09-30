import Model

/// Something wrong with an account's trades, found when they're applied
/// (``TradeLedger/issues``, ``Valuator/tradeIssues(for:)``). The trade is
/// still applied as far as it can be: nothing is dropped silently.
public struct TradeIssue: Hashable, Sendable, CustomStringConvertible {
    /// What kind of problem it is.
    public struct Kind: OpenEnum {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        /// The record on its own is missing something or gets it wrong
        /// (``Model/Trade/problems``).
        public static let invalidTrade: Kind = "invalidTrade"
        /// A sell or transfer out of more units than the account held.
        public static let oversold: Kind = "oversold"
        /// An opening or transfer in without a cost: the instrument's
        /// purchase cost is unknown until the position is closed.
        public static let unknownCost: Kind = "unknownCost"
        /// No FX rate on or before the trade date converts the price into
        /// the account's currency, so the cash effect is unknown.
        public static let missingFX: Kind = "missingFX"
        /// A split of an instrument the account doesn't hold.
        public static let splitNotHeld: Kind = "splitNotHeld"
        /// Trades of an account that doesn't record trades; they're left out.
        public static let notTradesAccount: Kind = "notTradesAccount"
        /// A trade before the account's `opened` date or after `closed`.
        public static let outsideAccountDates: Kind = "outsideAccountDates"
        /// A valuation of a trades account with a balance, which isn't used.
        public static let balanceIgnored: Kind = "balanceIgnored"
        /// A valuation lists positions that differ from the trades'.
        public static let reconciliation: Kind = "reconciliation"

        public static let knownValues: [Kind] = [
            .invalidTrade, .oversold, .unknownCost, .missingFX, .splitNotHeld, .notTradesAccount,
            .outsideAccountDates, .balanceIgnored, .reconciliation,
        ]
    }

    public let kind: Kind
    public let severity: TradeProblem.Severity
    public let account: AccountID
    /// The trade concerned, if one is.
    public let trade: TradeKey?
    /// The instrument concerned, if one is.
    public let instrument: InstrumentID?
    /// The date concerned: the trade's or the valuation's.
    public let date: CalendarDate
    /// What's wrong, in plain words.
    public let message: String

    public init(_ kind: Kind, _ severity: TradeProblem.Severity, account: AccountID, trade: TradeKey? = nil,
                instrument: InstrumentID? = nil, date: CalendarDate, message: String) {
        self.kind = kind
        self.severity = severity
        self.account = account
        self.trade = trade
        self.instrument = instrument
        self.date = date
        self.message = message
    }

    /// `2026-03-12 directa: message`
    public var description: String { "\(date) \(account): \(message)" }
}
