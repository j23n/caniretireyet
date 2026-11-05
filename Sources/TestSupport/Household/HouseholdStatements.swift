import Foundation
import Model

/// The bank statements of a simulated household's current account and
/// savings accounts, as their banks export them.
extension Household {
    /// The accounts with a bank statement, in a fixed order.
    public var statementAccounts: [AccountID] {
        accounts.filter(HouseholdState.hasStatement)
    }

    /// The statement lines of `account` in `year`, in the order the bank lists them.
    public func statementLines(of account: AccountID, year: Int, truth: HouseholdTruth? = nil) -> [HouseholdLine] {
        (truth ?? self.truth).lines.filter { $0.account == account && $0.date.year == year }
    }

    /// `account`'s statement for `year`, a CSV file with a header and a
    /// row a line: `Date,Description,Amount,Balance`, ISO dates, amounts
    /// with two decimals, and the balance after each line. Empty without lines.
    public func statementCSV(of account: AccountID, year: Int, truth: HouseholdTruth? = nil) -> String {
        let truth = truth ?? self.truth
        var rows = ["Date,Description,Amount,Balance"]
        var day: CalendarDate?
        var balance: Decimal = 0
        for line in statementLines(of: account, year: year, truth: truth) {
            if line.date != day {
                day = line.date
                balance = truth.value(of: account, on: line.date.adding(days: -1))
            }
            balance += line.amount
            rows.append("\(line.date),\(line.text),\(Self.csvAmount(line.amount)),\(Self.csvAmount(balance))")
        }
        return rows.count > 1 ? rows.joined(separator: "\n") + "\n" : ""
    }

    /// `amount` with two decimals and a point, e.g. `-1500.00`.
    static func csvAmount(_ amount: Decimal) -> String {
        let cents = NSDecimalNumber(decimal: (amount * 100).rounded(scale: 0)).int64Value
        let whole = abs(cents) / 100
        let fraction = abs(cents) % 100
        return "\(cents < 0 ? "-" : "")\(whole).\(fraction < 10 ? "0" : "")\(fraction)"
    }
}
