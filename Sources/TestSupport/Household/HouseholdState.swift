import Foundation
import Model

/// The opening position of a simulated household on its first check-in.
public struct HouseholdOpening: Hashable, Sendable {
    /// A holding at the broker, with what it cost.
    public struct Holding: Hashable, Sendable {
        public var quantity: Decimal
        public var cost: Decimal

        public init(quantity: Decimal, cost: Decimal) {
            self.quantity = quantity
            self.cost = cost
        }
    }

    /// Every balance account's balance, in euros (debts negative).
    public var balances: [AccountID: Decimal]
    /// The broker's cash.
    public var brokerCash: Decimal
    /// What the broker holds.
    public var holdings: [InstrumentID: Holding]

    public init(balances: [AccountID: Decimal], brokerCash: Decimal, holdings: [InstrumentID: Holding]) {
        self.balances = balances
        self.brokerCash = brokerCash
        self.holdings = holdings
    }
}

/// A household's money at the end of a day, and what each event does to
/// it: the one place the events' meaning is written. The simulator plays
/// events on it as it makes them, and the truth plays them again.
struct HouseholdState {
    /// Every balance account's balance, in euros (debts negative).
    var balances: [AccountID: Decimal]
    var brokerCash: Decimal
    var holdings: [InstrumentID: Decimal]

    init(_ opening: HouseholdOpening) {
        balances = opening.balances
        brokerCash = opening.brokerCash
        holdings = opening.holdings.mapValues(\.quantity)
    }

    subscript(account: AccountID) -> Decimal {
        get { balances[account] ?? 0 }
        set { balances[account] = newValue }
    }

    /// What one event did: the money that moved into each account from
    /// outside it, what it counts as, and its statement lines.
    struct Effect {
        var flows: [AccountID: Decimal] = [:]
        var totals = HouseholdTotals()
        var lines: [HouseholdLine] = []
    }

    /// Applies `event` and says what it did.
    mutating func apply(_ event: HouseholdEvent) -> Effect {
        typealias A = HouseholdAccount
        var effect = Effect()
        func move(_ amount: Decimal, _ account: AccountID) {
            if account == A.broker { brokerCash += amount } else { self[account] += amount }
            effect.flows[account, default: 0] += amount
        }
        func line(_ account: AccountID, _ amount: Decimal, _ text: String, _ statementClass: StatementClass,
                  other: AccountID? = nil) {
            effect.lines.append(HouseholdLine(account: account, date: event.date, amount: amount, text: text,
                                              statementClass: statementClass, otherAccount: other,
                                              event: event.id))
        }
        func transfer(_ amount: Decimal, from: AccountID, to: AccountID, out: String, in text: String) {
            move(-amount, from)
            move(amount, to)
            if HouseholdState.hasStatement(from) { line(from, -amount, out, .transfer, other: to) }
            if HouseholdState.hasStatement(to) { line(to, amount, text, .transfer, other: from) }
        }

        switch event.kind {
        case .pay(let amount), .bonus(let amount):
            move(amount, A.current)
            effect.totals.pay += amount
            line(A.current, amount, "Salary Northwind Example Ltd", .income)
        case .pensionContribution(let amount):
            move(amount, A.pension)
            effect.totals.pension += amount
        case .fundReturn(let amount):
            self[A.pension] += amount
        case .spend(let amount, let merchant):
            move(-amount, A.current)
            effect.totals.spent += amount
            line(A.current, -amount, "Debit card \(merchant)", .spending)
        case .refund(let amount, let merchant):
            move(amount, A.current)
            effect.totals.spent -= amount
            line(A.current, amount, "Refund \(merchant)", .spending)
        case .cardSpend(let amount, _):
            move(-amount, A.card)
            effect.totals.spent += amount
        case .cardRefund(let amount, _):
            move(amount, A.card)
            effect.totals.spent -= amount
        case .cardBill(let amount):
            transfer(amount, from: A.current, to: A.card, out: "Harbor Visa repayment", in: "")
            // Paying the card is money out of the current account (IMPORT.md, "Classes").
            effect.lines[effect.lines.count - 1].statementClass = .spending
        case .toSavings(let amount):
            transfer(amount, from: A.current, to: A.savings, out: "Transfer to Rainy Day Savings",
                     in: "Transfer from Everyday Account")
        case .fromSavings(let amount):
            transfer(amount, from: A.savings, to: A.current, out: "Transfer to Everyday Account",
                     in: "Transfer from Rainy Day Savings")
        case .interest(let amount):
            self[A.savings] += amount
            line(A.savings, amount, "Interest paid", .interest)
        case .deposit(let amount):
            transfer(amount, from: A.current, to: A.broker, out: "Transfer to Lighthouse Invest", in: "")
        case .buy(let instrument, let quantity, _, let amount, _):
            brokerCash -= amount
            holdings[instrument, default: 0] += quantity
        case .sell(let instrument, let quantity, _, let amount, _):
            brokerCash += amount
            holdings[instrument, default: 0] -= quantity
        case .dividend(_, let amount):
            brokerCash += amount
        case .mortgagePayment(let principal, let interest):
            move(-(principal + interest), A.current)
            move(principal, A.mortgage)
            effect.totals.spent += interest
            line(A.current, -(principal + interest), "Home Mortgage payment", .spending, other: A.mortgage)
        case .taxBill(let amount):
            move(-amount, A.current)
            effect.totals.tax += amount
            line(A.current, -amount, "Income tax payment", .tax)
        case .inheritance(let amount):
            move(amount, A.current)
            effect.totals.oneOffs += amount
            line(A.current, amount, "Estate of J. Example", .oneOff)
        case .buyCar(let amount):
            transfer(amount, from: A.current, to: A.car, out: "Bayside Motors", in: "")
        case .carLoss(let amount):
            move(-amount, A.car)
            effect.totals.spent += amount
        case .sellCar(let amount):
            let worth = self[A.car]
            transfer(amount, from: A.car, to: A.current, out: "", in: "Car sale private buyer")
            // What it was worth beyond what it brought was spent.
            move(amount - worth, A.car)
            effect.totals.spent += worth - amount
        case .openOnline(let amount):
            move(amount, A.online)
            effect.totals.startedWith += amount
        case .toOnline(let amount):
            transfer(amount, from: A.current, to: A.online, out: "Transfer to Online Saver",
                     in: "Transfer from Everyday Account")
        case .onlineInterest(let amount):
            self[A.online] += amount
            line(A.online, amount, "Interest paid", .interest)
        }
        return effect
    }

    /// Whether the account has a bank statement: the current account and
    /// the two savings accounts.
    static func hasStatement(_ account: AccountID) -> Bool {
        [HouseholdAccount.current, HouseholdAccount.savings, HouseholdAccount.online].contains(account)
    }

    /// What every account is worth in euros on `date`, the broker at the day's prices.
    func values(on date: CalendarDate, markets: HouseholdMarkets) -> [AccountID: Decimal] {
        var values = balances
        values[HouseholdAccount.broker] = holdings.keys.sorted().reduce(brokerCash) { total, instrument in
            total + markets.value(of: holdings[instrument] ?? 0, instrument, on: date)
        }
        return values
    }
}
