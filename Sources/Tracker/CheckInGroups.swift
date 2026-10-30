import Foundation
import Model

/// A check-in's accounts by what each needs (docs/UI.md, "Check-in"):
///
/// - **Money in and out:** the cash and savings accounts and tax pots,
///   each with its month (``AccountMonth``), imported from a CSV or typed.
/// - **Investments:** the trades accounts, each with its month
///   (``BrokerageMonth``).
/// - **Values you type:** the other accounts that take typed values
///   (``TypedCheckInAccount``), such as a pension fund, a home or a car.
/// - **Others:** the rest, valued from their files.
public struct CheckInGroups: Hashable, Sendable {
    public var date: CalendarDate
    /// The check-in before, where the months start; `nil` before the first.
    public var from: CalendarDate?
    public var money: [AccountMonth]
    public var investments: [BrokerageMonth]
    public var typed: [TypedCheckInAccount]
    public var others: [AccountID]

    public init(date: CalendarDate, from: CalendarDate?, money: [AccountMonth], investments: [BrokerageMonth],
                typed: [TypedCheckInAccount], others: [AccountID]) {
        self.date = date
        self.from = from
        self.money = money
        self.investments = investments
        self.typed = typed
        self.others = others
    }

    /// How many accounts of the first three groups need nothing more.
    public var doneCount: Int {
        money.count { $0.status.isDone } + investments.count { $0.status.isDone } + typed.count { $0.isDone }
    }

    /// How many accounts the first three groups list.
    public var count: Int { money.count + investments.count + typed.count }
}

/// An account whose value you type, in a check-in: its latest value, and
/// for one that loses value its estimate on the check-in's date.
public struct TypedCheckInAccount: Hashable, Sendable, Identifiable {
    public var account: AccountID
    /// Its latest value on or before the check-in's date.
    public var last: Valuation?
    /// For a belongings account with a depreciation, without a value on
    /// the check-in's date: its value then, estimated from ``last``
    /// (docs/ACCOUNTS.md, `depreciation`).
    public var estimate: Decimal?
    /// Whether it has a value after the check-in before.
    public var isUpdated: Bool

    public init(account: AccountID, last: Valuation?, estimate: Decimal?, isUpdated: Bool) {
        self.account = account
        self.last = last
        self.estimate = estimate
        self.isUpdated = isUpdated
    }

    public var id: AccountID { account }

    /// Whether it needs nothing more: it has a value since the check-in
    /// before, or an estimate the check-in keeps unless you type over it.
    public var isDone: Bool { isUpdated || estimate != nil }

    /// What the estimate lost since the last value: lost value, neither
    /// spent nor saved. `nil` without an estimate.
    public var lost: Decimal? {
        guard let estimate, let balance = last?.balance else { return nil }
        return balance - estimate
    }
}

extension Library {
    /// The money accounts' month up to `date` (``MoneyMonth``): it starts
    /// at their latest value before `date`, and it's checked in when one
    /// has a value on `date`.
    public func moneyMonth(through date: CalendarDate) -> MoneyMonth {
        let money = accounts.values.filter { $0.kind.recordsMoneyInOut && $0.valuationMode == .balance }
        let dates = Set(money.flatMap { valuations(for: $0.id).map(\.date) })
        let previous = dates.filter { $0 < date }.max()
        let months = moneyMonthAccounts(after: previous, through: date).compactMap {
            accountMonth(of: $0.id, through: date)
        }
        return MoneyMonth(from: previous, through: date, isCheckedIn: dates.contains(date), accounts: months)
    }
}

extension Valuator {
    /// The accounts of a check-in on `date` in `library`, by what each
    /// needs (``CheckInGroups``). The months start at the money accounts'
    /// check-in before, else at the check-in before.
    public func checkInGroups(on date: CalendarDate, in library: Library) -> CheckInGroups {
        let moneyMonth = library.moneyMonth(through: date)
        let from = moneyMonth.from ?? previousCheckIn(before: date)
        let investments = brokerageMonths(after: from, through: date, in: library)
        var listed = Set(moneyMonth.accounts.map(\.account)).union(investments.map(\.account))
        let open = library.accounts.values
            .filter { $0.isOpen(on: date) && !listed.contains($0.id) && !$0.recordsTrades }
            .sorted { ($0.group, $0.name.lowercased(), $0.id) < ($1.group, $1.name.lowercased(), $1.id) }
        var typed: [TypedCheckInAccount] = []
        for account in open where account.acceptsTypedValues {
            typed.append(typedAccount(account, on: date, after: from))
            listed.insert(account.id)
        }
        let others = open.filter { !listed.contains($0.id) && emptySince(of: $0.id, on: date) == nil }.map(\.id)
        return CheckInGroups(date: date, from: from, money: moneyMonth.accounts, investments: investments,
                             typed: typed, others: others)
    }

    private func typedAccount(_ account: Account, on date: CalendarDate,
                              after from: CalendarDate?) -> TypedCheckInAccount {
        let last = latestValuation(for: account.id, onOrBefore: date)
        var estimate: Decimal?
        if account.lossOfValue != nil, let last, last.date < date, let balance = last.balance {
            estimate = account.estimated(balance, from: last.date, on: date)
        }
        var isUpdated = false
        if let last {
            isUpdated = from.map { last.date > $0 } ?? true
        }
        return TypedCheckInAccount(account: account.id, last: last, estimate: estimate, isUpdated: isUpdated)
    }
}
