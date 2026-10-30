import Foundation
import Model

/// The bank lines of a cash, savings or tax-pot account between two of its
/// values (docs/IMPORT.md, "Lines"), and whether they add up: the balance
/// before, plus every line that counts, is the balance after. A value
/// changed later carries forward, since the next stretch starts from it.
public struct LineStretch: Hashable, Sendable {
    public var account: AccountID
    /// The date of the value the stretch starts after; `nil` before the
    /// account's first value.
    public var from: CalendarDate?
    /// The date of the value it ends on; `nil` for the lines after the
    /// account's last value.
    public var through: CalendarDate?
    /// The balance it starts from: the value on ``from``'s.
    public var opening: Decimal?
    /// The balance it ends on: the value on ``through``'s.
    public var closing: Decimal?
    /// Its lines, removed ones too, sorted by key.
    public var lines: [BankLine]
    /// What its lines that count add to money in and out (``Model/LineAmounts``).
    public var amounts: LineAmounts

    public init(account: AccountID, from: CalendarDate?, through: CalendarDate?, opening: Decimal?,
                closing: Decimal?, lines: [BankLine], amounts: LineAmounts) {
        self.account = account
        self.from = from
        self.through = through
        self.opening = opening
        self.closing = closing
        self.lines = lines
        self.amounts = amounts
    }

    /// The lines that count: those not removed.
    public var countedLines: [BankLine] { lines.filter { !$0.isRemoved } }

    /// Everything the lines that count moved, money in positive.
    public var total: Decimal { countedLines.reduce(Decimal(0)) { $0 + $1.amount } }

    /// What moved to and from your other accounts: the transfers.
    public var moved: Decimal {
        countedLines.filter { $0.statementClass == .transfer }.reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// What was spent: money out less the tax in it (``Model/LineAmounts/spent``).
    public var spent: Decimal { amounts.spent }

    /// The balance the lines lead to: ``opening`` plus ``total``. `nil`
    /// without an opening balance.
    public var expectedClosing: Decimal? { opening.map { $0 + total } }

    /// The closing balance less the one the lines lead to: a line missing,
    /// one twice, or a balance typed wrong. `nil` when either is unknown.
    public var difference: Decimal? {
        guard let closing, let expectedClosing else { return nil }
        return closing - expectedClosing
    }

    /// Whether the stretch adds up: the lines lead to the closing balance.
    public var addsUp: Bool { difference == 0 }
}

extension Library {
    /// An account's bank lines between each two of its values, oldest
    /// first (``LineStretch``): one for each value with lines since the
    /// value before, one before the first value when lines come before it,
    /// and one after the last value for the lines after it. Empty for an
    /// account without lines.
    public func lineStretches(of account: AccountID) -> [LineStretch] {
        let lines = lines(for: account)
        guard !lines.isEmpty, let details = accounts[account] else { return [] }
        let recordsInterest = details.kind.recordsInterest
        let values = valuations(for: account)
        var stretches: [LineStretch] = []
        var previous: Valuation?
        let ends: [Valuation?] = values.map { $0 } + [nil]
        for value in ends {
            let inside = lines.filter { line in
                (previous.map { line.date > $0.date } ?? true) && (value.map { line.date <= $0.date } ?? true)
            }
            defer { previous = value }
            guard !inside.isEmpty else { continue }
            let amounts = inside.reduce(LineAmounts()) { $0 + $1.amounts(recordsInterest: recordsInterest) }
            stretches.append(LineStretch(account: account, from: previous?.date, through: value?.date,
                                         opening: previous?.amountForLines, closing: value?.amountForLines,
                                         lines: inside, amounts: amounts))
        }
        return stretches
    }

    /// Writes the money in and out of `account`'s values from their bank
    /// lines (docs/IMPORT.md, "Lines"), after a line is changed: each value
    /// that records money in and out, whose stretch of lines since the
    /// value before adds up, gets their sums, as a statement's import
    /// counts them. Money out below zero, more paid back than spent, is 0.
    /// A tax pot records no tax: a bill paid from it is its money out.
    /// Values without lines or without money in and out are left as they
    /// are, and so is a value whose stretch doesn't add up, such as one
    /// whose money in and out were typed for a longer period than the
    /// lines cover. A value keeps its source, which says where its balance
    /// came from.
    public mutating func countLines(of account: AccountID) {
        guard let kind = accounts[account]?.kind else { return }
        for stretch in lineStretches(of: account) {
            guard stretch.addsUp, let through = stretch.through,
                  var value = valuations(for: account).first(where: { $0.date == through }), value.hasMoneyInOut
            else { continue }
            let amounts = stretch.amounts
            value.moneyIn = amounts.moneyIn
            value.moneyOut = max(amounts.moneyOut, 0)
            value.oneOff = amounts.oneOff != 0 ? amounts.oneOff : nil
            value.tax = amounts.tax != 0 && kind != .taxPot ? amounts.tax : nil
            if kind.recordsInterest { value.interest = amounts.interest != 0 ? amounts.interest : nil }
            upsert(value)
        }
    }
}

extension Valuation {
    /// The balance bank lines are checked against: the balance, else the cash.
    fileprivate var amountForLines: Decimal? { balance ?? cash }
}
