import Foundation
import Model

/// The accounts and instruments of a simulated household (``Household``),
/// all made up.
public enum HouseholdAccount {
    /// The current account: pay comes in, spending, bills and transfers go out.
    public static let current: AccountID = "current"
    /// A savings account that earns interest.
    public static let savings: AccountID = "savings"
    /// A credit card, paid off each month from the current account.
    public static let card: AccountID = "card"
    /// A broker that records trades.
    public static let broker: AccountID = "broker"
    /// A pension fund the employer pays into.
    public static let pension: AccountID = "pension"
    /// The mortgage on the home (the home itself isn't tracked).
    public static let mortgage: AccountID = "mortgage"
    /// A car, worth nothing until it's bought.
    public static let car: AccountID = "car"
    /// A second savings account, opened during the run with money from outside.
    public static let online: AccountID = "online"

    /// An ETF priced in euros.
    public static let etf: InstrumentID = "world-etf"
    /// A stock priced in dollars.
    public static let stock: InstrumentID = "us-stock"
}

/// One true event in a simulated household's life (``HouseholdSimulator``):
/// what happened to its money on a day, with every amount, in euros.
public struct HouseholdEvent: Hashable, Sendable, CustomStringConvertible {
    /// The event's number in the list the simulator made. It stays the same
    /// when other events are removed, so trade IDs and statement texts do too.
    public var id: Int
    public var date: CalendarDate
    public var kind: Kind

    public init(id: Int, date: CalendarDate, kind: Kind) {
        self.id = id
        self.date = date
        self.kind = kind
    }

    public enum Kind: Hashable, Sendable {
        /// Pay after the employer's withholding, into the current account,
        /// with the text the bank writes for its payer.
        case pay(Decimal, payer: String)
        /// A bonus, after withholding, into the current account.
        case bonus(Decimal, payer: String)
        /// The employer's contribution to the pension fund.
        case pensionContribution(Decimal)
        /// What the pension fund's investments did: market.
        case fundReturn(Decimal)
        /// Spending paid by debit from the current account, at a merchant.
        case spend(Decimal, merchant: String)
        /// A refund of spending, into the current account.
        case refund(Decimal, merchant: String)
        /// A purchase on the credit card.
        case cardSpend(Decimal, merchant: String)
        /// A refund onto the credit card.
        case cardRefund(Decimal, merchant: String)
        /// The card's bill, paid from the current account.
        case cardBill(Decimal)
        /// Money moved from the current account to the savings account.
        case toSavings(Decimal)
        /// Money moved from the savings account to the current account.
        case fromSavings(Decimal)
        /// Interest credited to the savings account: market.
        case interest(Decimal)
        /// Money moved from the current account to the broker.
        case deposit(Decimal)
        /// A buy paid from the broker's cash: `amount` is what it cost, fees included.
        case buy(InstrumentID, quantity: Decimal, price: Decimal, amount: Decimal, fees: Decimal)
        /// A sale into the broker's cash: `amount` is what it brought, after fees.
        case sell(InstrumentID, quantity: Decimal, price: Decimal, amount: Decimal, fees: Decimal)
        /// A dividend paid into the broker's cash: market.
        case dividend(InstrumentID, Decimal)
        /// The mortgage's payment from the current account: the principal
        /// lowers what's owed, the interest is spent.
        case mortgagePayment(principal: Decimal, interest: Decimal)
        /// The yearly income tax bill, paid from the current account.
        case taxBill(Decimal)
        /// An inheritance into the current account: neither income nor spending.
        case inheritance(Decimal)
        /// A car bought from the current account.
        case buyCar(Decimal)
        /// What the car lost in value over a month: spent.
        case carLoss(Decimal)
        /// The car sold, its proceeds into the current account; what it was
        /// worth beyond them is spent.
        case sellCar(Decimal)
        /// The second savings account opens, holding money from outside
        /// that was never tracked: neither income nor spending.
        case openOnline(Decimal)
        /// Money moved from the current account to the second savings account.
        case toOnline(Decimal)
        /// Interest credited to the second savings account: market.
        case onlineInterest(Decimal)
    }

    public var description: String {
        "\(date) #\(id) \(kind)"
    }
}

extension HouseholdEvent.Kind: CustomStringConvertible {
    public var description: String {
        switch self {
        case .pay(let amount, let payer): "pay \(amount) from \(payer)"
        case .bonus(let amount, let payer): "bonus \(amount) from \(payer)"
        case .pensionContribution(let amount): "pension contribution \(amount)"
        case .fundReturn(let amount): "fund return \(amount)"
        case .spend(let amount, let merchant): "spend \(amount) at \(merchant)"
        case .refund(let amount, let merchant): "refund \(amount) from \(merchant)"
        case .cardSpend(let amount, let merchant): "card spend \(amount) at \(merchant)"
        case .cardRefund(let amount, let merchant): "card refund \(amount) from \(merchant)"
        case .cardBill(let amount): "card bill \(amount)"
        case .toSavings(let amount): "to savings \(amount)"
        case .fromSavings(let amount): "from savings \(amount)"
        case .interest(let amount): "savings interest \(amount)"
        case .deposit(let amount): "deposit to broker \(amount)"
        case .buy(let instrument, let quantity, let price, let amount, let fees):
            "buy \(quantity) \(instrument) at \(price) for \(amount) (fees \(fees))"
        case .sell(let instrument, let quantity, let price, let amount, let fees):
            "sell \(quantity) \(instrument) at \(price) for \(amount) (fees \(fees))"
        case .dividend(let instrument, let amount): "dividend \(amount) on \(instrument)"
        case .mortgagePayment(let principal, let interest): "mortgage \(principal) principal, \(interest) interest"
        case .taxBill(let amount): "tax bill \(amount)"
        case .inheritance(let amount): "inheritance \(amount)"
        case .buyCar(let amount): "buy car \(amount)"
        case .carLoss(let amount): "car loses \(amount)"
        case .sellCar(let amount): "sell car for \(amount)"
        case .openOnline(let amount): "open online savings with \(amount) from outside"
        case .toOnline(let amount): "to online savings \(amount)"
        case .onlineInterest(let amount): "online savings interest \(amount)"
        }
    }
}
