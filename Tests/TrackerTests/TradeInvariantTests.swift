import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Invariant B9: trades close cleanly (docs/TRADES.md). Selling everything
/// leaves no quantity and no purchase cost; what an account is worth, less
/// the money put into it, is its realised and unrealised gains and its
/// income; and a negative quantity, more sold than held, always comes with
/// an `oversold` issue.
struct TradeInvariantTests {
    /// A made-up broker's trades from a seed: deposits, buys and sales of
    /// two funds, dividends, a fee now and then, a withdrawal, and at the
    /// end every holding sold. With `oversell`, now and then a sale of more
    /// than is held.
    private func trades(seed: UInt64, oversell: Bool = false) -> Library {
        var random = SeededRandom(seed: seed)
        var library = Library(accounts: [
            Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2025-01-01",
                    valuation: .trades),
        ], instruments: [
            Instrument(id: "alpha", name: "Alpha", kind: .etf, currency: .eur, unit: .share,
                       assetClasses: .single(.equity)),
            Instrument(id: "beta", name: "Beta", kind: .etf, currency: .eur, unit: .share,
                       assetClasses: .single(.bonds)),
        ])
        var held: [InstrumentID: Decimal] = ["alpha": 0, "beta": 0]
        var prices: [InstrumentID: Decimal] = ["alpha": 100, "beta": 50]
        var day: CalendarDate = "2025-01-02"
        func add(_ trade: Trade) { library.upsert(trade) }
        for step in 0..<60 {
            day = day.adding(days: 1 + random.next(below: 4))
            for instrument in ["alpha", "beta"] as [InstrumentID] {
                // A price a day, moving by up to 3% in cents.
                let move = Decimal(Int(random.next(below: 601)) - 300) / 10000
                prices[instrument] = ((prices[instrument] ?? 0) * (1 + move)).rounded(2)
                library.upsert(PriceRecord(instrument: instrument, date: day, price: prices[instrument] ?? 0,
                                           currency: .eur))
            }
            let instrument: InstrumentID = random.next(below: 2) == 0 ? "alpha" : "beta"
            let price = prices[instrument] ?? 0
            let id = TradeID("t\(step)")
            switch random.next(below: 10) {
            case 0, 1:
                add(Trade(account: "broker", date: day, id: id, type: .deposit,
                          amount: Decimal(500 + 100 * random.next(below: 10))))
            case 2, 3, 4:
                let quantity = Decimal(1 + random.next(below: 8))
                add(Trade(account: "broker", date: day, id: id, type: .buy, instrument: instrument,
                          quantity: quantity, price: price, fees: Decimal(random.next(below: 3))))
                held[instrument, default: 0] += quantity
            case 5, 6:
                let holding = held[instrument] ?? 0
                let quantity = oversell && random.next(below: 3) == 0
                    ? holding + 2 : Decimal(random.next(below: 4))
                guard quantity > 0, quantity <= holding || oversell else { continue }
                add(Trade(account: "broker", date: day, id: id, type: .sell, instrument: instrument,
                          quantity: quantity, price: price, fees: 1,
                          tax: (quantity * price / 100).rounded(2)))
                held[instrument, default: 0] -= quantity
            case 7:
                add(Trade(account: "broker", date: day, id: id, type: .dividend, instrument: instrument,
                          amount: Decimal(10 + random.next(below: 40)), tax: 2))
            case 8:
                add(Trade(account: "broker", date: day, id: id, type: .fee, fees: Decimal(1 + random.next(below: 5))))
            default:
                add(Trade(account: "broker", date: day, id: id, type: .withdrawal,
                          amount: -Decimal(50 * (1 + random.next(below: 4)))))
            }
        }
        day = day.adding(days: 1)
        for (instrument, quantity) in held.sorted(by: { $0.key < $1.key }) where quantity > 0 {
            add(Trade(account: "broker", date: day, id: TradeID("close-\(instrument)"), type: .sell,
                      instrument: instrument, quantity: quantity, price: prices[instrument] ?? 0, fees: 1))
        }
        return library
    }

    /// What `account` is worth on `date`, less the money put into it, and
    /// its realised and unrealised gains and income, in its currency, from
    /// its ledger (docs/TRADES.md): worth is the trades' cash and the
    /// holdings at the day's prices; money put in is the deposits less the
    /// withdrawals, what was paid from or into outside it, and the cost of
    /// the holdings that came in (openings, transfers in) less that of
    /// those that went out; income is what dividends, interest, fees and
    /// taxes on their own brought in or took, and the fees and tax of
    /// trades that moved units without money, less the tax on sales, which
    /// a realised gain is before.
    private func gains(of account: AccountID, on date: CalendarDate, valuator: Valuator) throws
        -> (worthLessPutIn: Decimal, gains: Decimal) {
        let ledger = try #require(valuator.ledger(for: account))
        let details = try #require(valuator.accounts[account])
        var cash: Decimal = 0
        var putIn: Decimal = 0
        var realised: Decimal = 0
        var income: Decimal = 0
        for entry in ledger.entries(after: nil, through: date) {
            let trade = entry.trade
            cash += try #require(entry.cashEffect)
            putIn += entry.externalFlow ?? 0
            switch trade.type {
            case .deposit, .withdrawal:
                putIn += try #require(entry.amount)
            case .opening, .transferIn:
                putIn += try #require(entry.cost)
                income += try #require(entry.amount)
            case .transferOut:
                putIn -= try #require(entry.cost)
                income += try #require(entry.amount)
            case .sell:
                realised += try #require(entry.realizedGain)
                income -= trade.tax ?? 0
            case .buy:
                break
            default:
                income += try #require(entry.amount)
            }
        }
        var worth = cash
        var unrealised: Decimal = 0
        for position in ledger.positions(on: date) {
            let value = try #require(valuator.marketValue(of: position.quantity, of: position.instrument,
                                                          in: details.currency, on: date))
            worth += value
            unrealised += value - (try #require(position.costBasis))
        }
        return (worth - putIn, realised + unrealised + income)
    }

    @Test(arguments: 0..<12)
    func gainsAreTheWorthLessTheMoneyPutIn(_ seed: Int) throws {
        let library = trades(seed: UInt64(seed))
        let valuator = Valuator(library: library)
        let ledger = try #require(valuator.ledger(for: "broker"))
        #expect(ledger.issues.isEmpty)
        for date in Set(ledger.entries.map(\.date)).sorted() {
            let result = try gains(of: "broker", on: date, valuator: valuator)
            #expect(same(result.worthLessPutIn, result.gains), "\(date)")
        }
    }

    @Test(arguments: 0..<12)
    func sellingEverythingLeavesNothing(_ seed: Int) throws {
        let valuator = Valuator(library: trades(seed: UInt64(seed)))
        let ledger = try #require(valuator.ledger(for: "broker"))
        let last = try #require(ledger.entries.last?.date)
        #expect(ledger.positions(on: last).isEmpty)
        for instrument in ["alpha", "beta"] as [InstrumentID] {
            guard let final = ledger.entries.last(where: { $0.trade.instrument == instrument && $0.quantityAfter != nil })
            else { continue }
            #expect(final.quantityAfter == 0, "\(instrument)")
            #expect(final.costAfter == 0, "\(instrument)")
        }
        #expect(valuator.holdings(of: "broker", on: last).isEmpty)
    }

    @Test(arguments: 0..<12)
    func aNegativeQuantityComesWithAnIssue(_ seed: Int) throws {
        let valuator = Valuator(library: trades(seed: UInt64(seed), oversell: true))
        let ledger = try #require(valuator.ledger(for: "broker"))
        let issues = valuator.tradeIssues(for: "broker").filter { $0.kind == .oversold }
        for entry in ledger.entries {
            guard let quantity = entry.quantityAfter, quantity < 0, let instrument = entry.trade.instrument else {
                continue
            }
            #expect(issues.contains { $0.instrument == instrument && $0.date <= entry.date },
                    "\(instrument) \(entry.date)")
        }
        for date in Set(ledger.entries.map(\.date)).sorted() {
            for position in ledger.positions(on: date) where position.quantity < 0 {
                #expect(issues.contains { $0.instrument == position.instrument && $0.date <= date })
            }
        }
    }

    /// The example library's three accounts that record trades: Directa,
    /// whose statements record its cash and a sale in July, the gold coins
    /// bought from the current account, and the crypto wallet.
    @Test(arguments: ["directa", "gold-coins", "ledger-wallet"] as [AccountID])
    func theExampleLibrarysTradesCloseCleanly(_ account: AccountID) throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let ledger = try #require(valuator.ledger(for: account))
        #expect(!ledger.entries.contains { ($0.quantityAfter ?? 0) < 0 })
        #expect(valuator.tradeIssues(for: account).filter { $0.kind == .oversold }.isEmpty)
        for date in Windows.checkIns(valuator) {
            let result = try gains(of: account, on: date, valuator: valuator)
            #expect(same(result.worthLessPutIn, result.gains), "\(date)")
        }
    }
}

/// SplitMix64: the same numbers for the same seed on every platform.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number from 0 to `bound` − 1.
    mutating func next(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }
}
