import Foundation

// Rules about trades that need nothing but the trades themselves: the order
// they're applied in, what a single record is missing, and the quantities
// they leave. Costs, cash and FX are worked out in Tracker (`TradeLedger`).

extension Sequence where Element == Trade {
    /// The trades in the order they're applied: by date; within a day by
    /// ``TradeType/processingRank`` (a split first, buys before sells), then
    /// by account and ID. The file order (by key) puts a day's trades in ID
    /// order, which is random, so it says nothing about which came first.
    public func inProcessingOrder() -> [Trade] {
        sorted { lhs, rhs in
            (lhs.date, lhs.type.processingRank, lhs.account, lhs.id)
                < (rhs.date, rhs.type.processingRank, rhs.account, rhs.id)
        }
    }
}

// MARK: - Checking one record

/// Something wrong with one trade record, found without looking at other
/// trades (``Trade/problems``).
public struct TradeProblem: Hashable, Sendable, CustomStringConvertible {
    public enum Severity: String, Hashable, Sendable {
        /// The trade can't be applied as it is (a buy without a price or an
        /// amount): it's applied as far as possible and reported.
        case error
        /// The trade is applied, but something looks wrong (a positive
        /// amount on a withdrawal, a field its type doesn't use).
        case warning
    }

    public var severity: Severity
    /// The field concerned, e.g. `"price"`, if one is.
    public var field: String?
    /// What's wrong, in plain words.
    public var message: String

    public init(_ severity: Severity, field: String? = nil, _ message: String) {
        self.severity = severity
        self.field = field
        self.message = message
    }

    public var description: String { message }
}

extension Trade {
    /// What's wrong with this record on its own: fields its type needs
    /// that are missing, values out of range, signs that contradict the
    /// type, and fields its type doesn't use. Empty when it looks right.
    /// Problems that need the account's other trades (selling more than is
    /// held) are found when the trades are applied.
    public var problems: [TradeProblem] {
        var problems: [TradeProblem] = []
        func error(_ field: String?, _ message: String) { problems.append(TradeProblem(.error, field: field, message)) }
        func warning(_ field: String?, _ message: String) {
            problems.append(TradeProblem(.warning, field: field, message))
        }
        let name = type.isKnown ? "A \(type.rawValue)" : "A trade"

        guard type.isKnown else {
            warning("type", "The type \"\(type.rawValue)\" isn't known to this version of the app, so the trade is "
                + "left out of holdings and cash.")
            return problems
        }

        // Ranges.
        if let quantity, quantity <= 0 {
            error("quantity", "The quantity must be positive; the type says whether units come in or go out.")
        }
        if let fees, fees < 0 { error("fees", "Fees must be positive (they're taken from the amount).") }
        if let tax, tax < 0 { error("tax", "Tax withheld must be positive (it's taken from the amount).") }
        if let ratio, ratio <= 0 { error("ratio", "A split's ratio must be positive, e.g. 2 for a 2-for-1 split.") }
        if let cost, cost < 0 { error("cost", "The purchase cost can't be negative.") }
        if let price, price < 0 { error("price", "The price can't be negative.") }

        // What each type needs.
        let hasGross = quantity != nil && price != nil
        switch type {
        case .buy, .sell:
            if instrument == nil { error("instrument", "\(name) needs an instrument.") }
            if quantity == nil { error("quantity", "\(name) needs a quantity.") }
            if price == nil && amount == nil { error("price", "\(name) needs a price or an amount.") }
        case .dividend:
            if amount == nil && !hasGross {
                error("amount", "A dividend needs an amount (or a quantity and the dividend per unit as price).")
            }
        case .interest:
            if amount == nil && !hasGross { error("amount", "Interest needs an amount.") }
        case .fee:
            if amount == nil && fees == nil { error("amount", "A fee needs an amount.") }
        case .tax:
            if amount == nil && tax == nil { error("amount", "A tax needs an amount.") }
        case .deposit, .withdrawal:
            if amount == nil { error("amount", "\(name) needs an amount.") }
        case .transferIn, .transferOut, .opening:
            if instrument == nil { error("instrument", "\(name) needs an instrument.") }
            if quantity == nil { error("quantity", "\(name) needs a quantity.") }
        case .split:
            if instrument == nil { error("instrument", "A split needs an instrument.") }
            if ratio == nil { error("ratio", "A split needs a ratio, e.g. 2 for a 2-for-1 split.") }
        default:
            break
        }

        // Signs: amount is the signed cash effect.
        if let amount {
            switch type {
            case .buy where amount > 0:
                warning("amount", "A buy's amount is the cash it took, so it should be negative.")
            case .deposit where amount < 0:
                warning("amount", "A deposit's amount should be positive; money out is a withdrawal.")
            case .withdrawal where amount > 0:
                warning("amount", "A withdrawal's amount is the cash taken out, so it should be negative.")
            default:
                break
            }
        }

        // Fields the type doesn't use.
        if ratio != nil && type != .split { warning("ratio", "Only a split uses a ratio; it's ignored.") }
        if cost != nil && type != .transferIn && type != .opening && type != .transferOut {
            warning("cost", "\(name)'s cost comes from its amount; the cost field is ignored.")
        }
        if type == .split, quantity != nil || amount != nil {
            warning(nil, "A split only uses its instrument and ratio; quantity and amount are ignored.")
        }
        return problems
    }
}

// MARK: - Quantities

/// The quantity held of each instrument, folded from an account's trades
/// in processing order (``Swift/Sequence/inProcessingOrder()``): buys,
/// transfers in and openings add units, sells and transfers out take them
/// away, and splits multiply them. Other types don't change quantities.
///
/// Quantities can go negative when a trade takes away more than is held:
/// ``apply(_:)`` returns the shortfall so it can be reported, and the
/// quantity shows the impossible state rather than hiding it.
public struct HeldQuantities: Hashable, Sendable {
    /// Every instrument a trade touched, including those back at zero.
    public private(set) var quantities: [InstrumentID: Decimal] = [:]

    public init() {}

    /// The quantities after applying `trades` (in processing order).
    public init(_ trades: some Sequence<Trade>) {
        for trade in trades.inProcessingOrder() { apply(trade) }
    }

    /// The quantity of `instrument`; zero if no trade touched it.
    public subscript(instrument: InstrumentID) -> Decimal {
        quantities[instrument] ?? 0
    }

    /// The instruments with a quantity other than zero.
    public var held: [InstrumentID: Decimal] {
        quantities.filter { $0.value != 0 }
    }

    /// Applies one trade. Returns how much it took away beyond what was
    /// held (a sell or transfer out of more than the quantity), or `nil`.
    /// A trade without its instrument, quantity or ratio changes nothing.
    @discardableResult
    public mutating func apply(_ trade: Trade) -> Decimal? {
        guard trade.type.changesHoldings, let instrument = trade.instrument else { return nil }
        let before = self[instrument]
        if trade.type == .split {
            guard let ratio = trade.ratio, ratio > 0 else { return nil }
            quantities[instrument] = before * ratio
            return nil
        }
        guard let quantity = trade.quantity, quantity > 0 else { return nil }
        if trade.type.addsUnits {
            quantities[instrument] = before + quantity
            return nil
        }
        quantities[instrument] = before - quantity
        return quantity > max(before, 0) ? quantity - max(before, 0) : nil
    }
}
