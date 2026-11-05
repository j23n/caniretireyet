import Foundation
import Model

/// What truly happened to a simulated household's money over some days
/// (``HouseholdTruth/totals(after:through:)``), in euros, counted from its
/// events rather than from its balances:
/// `change == saved + startedWith + markets`,
/// `savedFromPay == cameIn - tax - spent` and
/// `saved == savedFromPay + oneOffs`.
public struct HouseholdTotals: Hashable, Sendable {
    /// Pay and bonuses into the current account, after the employer's withholding.
    public var pay: Decimal = 0
    /// The employer's contributions to the pension fund.
    public var pension: Decimal = 0
    /// Tax paid from the household's accounts: the yearly bill.
    public var tax: Decimal = 0
    /// Spending by debit and by card, less refunds, the mortgage's interest
    /// and what the car lost in value.
    public var spent: Decimal = 0
    /// The inheritance: saved, but neither came in nor spent.
    public var oneOffs: Decimal = 0
    /// Money from outside that a new account held when it opened.
    public var startedWith: Decimal = 0
    /// Interest, dividends, prices, exchange rates, fees and the fund's
    /// return: every account's change less the money that moved into it.
    public var markets: Decimal = 0
    /// Net worth's change.
    public var change: Decimal = 0

    public init() {}

    /// What came in before tax: pay and the pension contributions
    /// (`WhatMoved.Pay.cameIn`).
    public var cameIn: Decimal { pay + pension }

    /// What came in after tax (`SavingsRate.income`).
    public var afterTax: Decimal { cameIn - tax }

    /// What the pay saved: what came in after tax, less what was spent
    /// (`SavingsRate.savedFromPay`).
    public var savedFromPay: Decimal { afterTax - spent }

    /// What was saved: what the pay saved and the one-offs
    /// (`SavingsRate.saved`).
    public var saved: Decimal { savedFromPay + oneOffs }

    public static func + (lhs: HouseholdTotals, rhs: HouseholdTotals) -> HouseholdTotals {
        var sum = lhs
        sum.pay += rhs.pay
        sum.pension += rhs.pension
        sum.tax += rhs.tax
        sum.spent += rhs.spent
        sum.oneOffs += rhs.oneOffs
        sum.startedWith += rhs.startedWith
        sum.markets += rhs.markets
        sum.change += rhs.change
        return sum
    }
}

/// One line of a simulated bank statement: an event as the current
/// account's, a savings account's or the second savings account's bank
/// writes it, with the class a careful person would confirm for it.
public struct HouseholdLine: Hashable, Sendable {
    public var account: AccountID
    public var date: CalendarDate
    /// Money in positive, money out negative.
    public var amount: Decimal
    /// The bank's text.
    public var text: String
    /// What the line truly is.
    public var statementClass: StatementClass
    /// For a transfer, the household's account on the other side.
    public var otherAccount: AccountID?
    /// The event it comes from.
    public var event: Int

    public init(account: AccountID, date: CalendarDate, amount: Decimal, text: String,
                statementClass: StatementClass, otherAccount: AccountID? = nil, event: Int) {
        self.account = account
        self.date = date
        self.amount = amount
        self.text = text
        self.statementClass = statementClass
        self.otherAccount = otherAccount
        self.event = event
    }
}

/// The money in and out a cash or savings account's lines add up to over
/// some days, as a careful person's statement records them.
public struct HouseholdMoneyInOut: Hashable, Sendable {
    public var moneyIn: Decimal = 0
    /// Spending and tax, less refunds.
    public var moneyOut: Decimal = 0
    public var oneOff: Decimal = 0
    public var tax: Decimal = 0
    public var interest: Decimal = 0

    public init() {}

    mutating func add(_ line: HouseholdLine) {
        switch line.statementClass {
        case .income: moneyIn += line.amount
        case .spending: moneyOut -= line.amount
        case .tax:
            moneyOut -= line.amount
            tax -= line.amount
        case .oneOff: oneOff += line.amount
        case .interest: interest += line.amount
        default: break
        }
    }
}
