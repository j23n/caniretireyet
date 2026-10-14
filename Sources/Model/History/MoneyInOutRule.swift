import Foundation

/// The money in and out of one valuation that summaries count (PROGRESS.md,
/// "Money in and out"), in the account's currency.
public struct CountedMoneyInOut: Hashable, Sendable {
    public var moneyIn: Decimal
    public var moneyOut: Decimal
    /// The one-off; zero without one, or with a negative one.
    public var oneOff: Decimal
    /// The tax; zero without it, and on a tax pot, whose tax is what moved
    /// into it.
    public var tax: Decimal

    public init(moneyIn: Decimal, moneyOut: Decimal, oneOff: Decimal = 0, tax: Decimal = 0) {
        self.moneyIn = moneyIn
        self.moneyOut = moneyOut
        self.oneOff = oneOff
        self.tax = tax
    }
}

extension Valuation {
    /// The rule for which money in and out counts, the one place it's
    /// written: what this valuation counts on an account of `kind`, and why
    /// what it records doesn't count otherwise ("records only money in;
    /// record both, or neither"), for the library's checks.
    ///
    /// Money in and out count when the kind records them
    /// (``AccountKind/recordsMoneyInOut``) and both are there, neither
    /// negative. The one-off counts with them, unless it's negative, and so
    /// does the tax, except on a tax pot, whose tax is what moved into it.
    public func moneyInOut(on kind: AccountKind) -> (counted: CountedMoneyInOut?, notCounted: [String]) {
        var notCounted: [String] = []
        guard kind.recordsMoneyInOut else {
            if hasMoneyInOut {
                notCounted.append("records money in or out, but only cash and savings accounts and tax pots do")
            }
            if tax != nil { notCounted.append("records tax, but only cash and savings accounts do") }
            if oneOff != nil { notCounted.append("records a one-off, but only cash and savings accounts do") }
            return (nil, notCounted)
        }
        if kind == .taxPot, tax != nil {
            notCounted.append("records tax, but a tax pot's tax is what moved into it")
        }
        guard let moneyIn, let moneyOut else {
            if hasMoneyInOut {
                notCounted.append("records only money \(self.moneyIn == nil ? "out" : "in"); record both, or neither")
            }
            if tax != nil, kind != .taxPot { notCounted.append("records tax without both money in and out") }
            if oneOff != nil { notCounted.append("records a one-off without both money in and out") }
            return (nil, notCounted)
        }
        if let oneOff, oneOff < 0 {
            notCounted.append("has a negative one-off, an amount without a sign")
        }
        guard moneyIn >= 0, moneyOut >= 0 else {
            notCounted.append("has negative money in or out; both are amounts without a sign")
            return (nil, notCounted)
        }
        let counted = CountedMoneyInOut(moneyIn: moneyIn, moneyOut: moneyOut, oneOff: max(oneOff ?? 0, 0),
                                        tax: kind == .taxPot ? 0 : tax ?? 0)
        return (counted, notCounted)
    }
}
