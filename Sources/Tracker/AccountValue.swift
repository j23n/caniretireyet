import Foundation
import Model

/// Why a value couldn't be computed completely. Missing data is reported,
/// never counted as zero.
public enum ValuationProblem: Hashable, Sendable, CustomStringConvertible {
    /// The account is open on the date but has no valuation on or before it.
    case noValuation(account: AccountID)
    /// A position's instrument has no price on or before the date.
    case missingPrice(account: AccountID, instrument: InstrumentID)
    /// No FX rate (direct, inverse or crossed) converts `from` to `to` on or before the date.
    case missingFX(account: AccountID, from: CurrencyCode, to: CurrencyCode)

    /// The account the problem concerns.
    public var account: AccountID {
        switch self {
        case .noValuation(let account), .missingPrice(let account, _), .missingFX(let account, _, _): account
        }
    }

    public var description: String {
        switch self {
        case .noValuation(let account):
            "\(account): no valuation on or before the date"
        case .missingPrice(let account, let instrument):
            "\(account): no price for \(instrument)"
        case .missingFX(let account, let from, let to):
            "\(account): no FX rate from \(from) to \(to)"
        }
    }
}

/// One part of an account's value: its balance, its cash, or one position.
public struct ValueComponent: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case balance
        case cash
        case position(InstrumentID)
    }

    public let kind: Kind
    /// Positions: the quantity held.
    public let quantity: Decimal?
    /// Positions: the price used (the latest on or before the date).
    public let price: PriceRecord?
    /// The amount in `currency`: the balance, the cash, or quantity × price.
    /// `nil` when the price is missing.
    public let amount: Decimal?
    /// The currency of `amount`: the account's for balances and cash, the
    /// price's for positions. `nil` when the price is missing.
    public let currency: CurrencyCode?
    /// The conversion to the value's currency (``AccountValue/currency``,
    /// normally the base currency); `nil` when none was needed or none was found.
    public let fx: FXQuote?
    /// The value in the value's currency (normally the base currency), or
    /// `nil` if it couldn't be computed.
    public let value: Decimal?
}

/// An account's value on a date, with how it was computed and anything missing.
public struct AccountValue: Hashable, Sendable {
    /// Where the account stands on the date.
    public enum Status: Hashable, Sendable {
        /// Before `opened`: the account doesn't count.
        case notOpenYet
        /// After `closed`: the account doesn't count.
        case closed
        /// Open, but no valuation on or before the date.
        case noValuation
        /// Open and valued (possibly with missing prices or rates).
        case valued
    }

    public let account: AccountID
    public let date: CalendarDate
    /// The currency the value is in: the base currency, or the account's
    /// own from ``Valuator/value(of:on:in:)`` with ``ValueCurrency/account``.
    public let currency: CurrencyCode
    public let status: Status
    /// The valuation carried forward to the date, if any.
    public let valuation: Valuation?
    public let components: [ValueComponent]
    public let problems: [ValuationProblem]

    /// Whether the account counts on the date (it's between opened and closed).
    public var isOpen: Bool {
        status == .valued || status == .noValuation
    }

    /// Whether the value is fully known.
    public var isComplete: Bool {
        problems.isEmpty
    }

    /// The value in ``currency`` (normally the base currency), or `nil` if
    /// anything is missing. Zero for an account that doesn't count on the date.
    public var value: Decimal? {
        isComplete ? knownValue : nil
    }

    /// The sum of the components that could be valued. Equals ``value``
    /// when nothing is missing.
    public var knownValue: Decimal {
        components.reduce(0) { $0 + ($1.value ?? 0) }
    }
}

/// Net worth on a date: the sum over the accounts that count.
public struct NetWorth: Hashable, Sendable {
    public let date: CalendarDate
    /// The base currency.
    public let currency: CurrencyCode
    /// The accounts that count on the date, sorted by ID.
    public let accounts: [AccountValue]

    /// The sum of what could be valued. Check ``isComplete`` before
    /// presenting it as exact.
    public var total: Decimal {
        accounts.reduce(0) { $0 + $1.knownValue }
    }

    /// Everything missing, across accounts.
    public var problems: [ValuationProblem] {
        accounts.flatMap(\.problems)
    }

    /// Whether every account was valued completely.
    public var isComplete: Bool {
        accounts.allSatisfy(\.isComplete)
    }
}
