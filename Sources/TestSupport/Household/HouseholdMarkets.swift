import Foundation
import Model

/// The markets a simulated household (``Household``) invests in: each day's
/// price of its ETF (in euros) and its dollar stock, and the euro's rate in
/// dollars, from the household's first check-in through its last day.
public struct HouseholdMarkets: Hashable, Sendable {
    /// The first day, index 0.
    public let start: CalendarDate
    /// The ETF's price each day, in euros.
    public var etf: [Decimal]
    /// The stock's price each day, in dollars.
    public var stock: [Decimal]
    /// Dollars per euro each day (1 EUR = rate × USD, as the ECB writes it).
    public var usdPerEUR: [Decimal]

    public init(start: CalendarDate, etf: [Decimal], stock: [Decimal], usdPerEUR: [Decimal]) {
        self.start = start
        self.etf = etf
        self.stock = stock
        self.usdPerEUR = usdPerEUR
    }

    /// Random walks over `days` days after `start`, from `rng`: the ETF about
    /// +3 basis points a day with a spread of 100, the stock +4 with 150, and
    /// the rate with a spread of 30. Prices are in cents, the rate in four
    /// decimals, so every amount is a plain decimal.
    public static func random(start: CalendarDate, days: Int, using rng: inout HouseholdRandom) -> HouseholdMarkets {
        var etf = [rng.amount(cents: 5000...15000)]
        var stock = [rng.amount(cents: 8000...30000)]
        var rate = [Decimal(rng.int(in: 10500...12000)) / 10000]
        for _ in 0..<days {
            etf.append(step(etf[etf.count - 1], basisPoints: 3 + rng.bell() / 10, scale: 2, floor: 1))
            stock.append(step(stock[stock.count - 1], basisPoints: 4 + rng.bell() * 3 / 20, scale: 2, floor: 1))
            rate.append(step(rate[rate.count - 1], basisPoints: rng.bell() * 3 / 100, scale: 4, floor: d("0.5")))
        }
        return HouseholdMarkets(start: start, etf: etf, stock: stock, usdPerEUR: rate)
    }

    private static func step(_ value: Decimal, basisPoints: Int, scale: Int, floor: Decimal) -> Decimal {
        max(floor, (value * Decimal(10000 + basisPoints) / 10000).rounded(scale: scale))
    }

    private func index(_ date: CalendarDate) -> Int {
        min(max(start.days(to: date), 0), etf.count - 1)
    }

    /// An instrument's price on `date`, in its own currency.
    public func price(of instrument: InstrumentID, on date: CalendarDate) -> Decimal {
        instrument == HouseholdAccount.stock ? stock[index(date)] : etf[index(date)]
    }

    /// The instrument's currency.
    public static func currency(of instrument: InstrumentID) -> CurrencyCode {
        instrument == HouseholdAccount.stock ? .usd : .eur
    }

    /// Dollars per euro on `date`.
    public func rate(on date: CalendarDate) -> Decimal {
        usdPerEUR[index(date)]
    }

    /// `quantity` of `instrument` in euros on `date`, not rounded: the
    /// dollar amount divided by the rate, as converting it at that rate does.
    public func value(of quantity: Decimal, _ instrument: InstrumentID, on date: CalendarDate) -> Decimal {
        if quantity == 0 { return 0 }
        let amount = quantity * price(of: instrument, on: date)
        return instrument == HouseholdAccount.stock ? amount / rate(on: date) : amount
    }
}
