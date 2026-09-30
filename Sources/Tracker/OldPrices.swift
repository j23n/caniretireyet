import Model

/// A position valued with a price much older than the value's date: gold
/// coins valued at a month end with the price they were bought at years
/// before, because no later price is recorded.
public struct OldPrice: Hashable, Sendable {
    /// The date of the value.
    public let date: CalendarDate
    public let account: AccountID
    public let instrument: InstrumentID
    /// The date of the price used.
    public let priceDate: CalendarDate

    public init(date: CalendarDate, account: AccountID, instrument: InstrumentID, priceDate: CalendarDate) {
        self.date = date
        self.account = account
        self.instrument = instrument
        self.priceDate = priceDate
    }

    /// Days from the price to the value.
    public var age: Int { priceDate.days(to: date) }
}

/// What a chart says about its old prices: how many of its values use one,
/// and for which instruments.
public struct OldPriceSummary: Hashable, Sendable {
    /// The dates whose value uses an old price, sorted.
    public let dates: [CalendarDate]
    /// The instruments with old prices, sorted.
    public let instruments: [InstrumentID]
    /// The oldest price's age in days.
    public let oldestAge: Int

    /// The summary of `prices`; `nil` when there are none.
    public init?(_ prices: [OldPrice]) {
        guard !prices.isEmpty else { return nil }
        dates = Set(prices.map(\.date)).sorted()
        instruments = Set(prices.map(\.instrument)).sorted()
        oldestAge = prices.map(\.age).max() ?? 0
    }
}

extension Valuator {
    /// How many days older than a value its price may be before a chart
    /// points it out.
    public static let oldPriceDays = 31

    /// The positions of `account` valued on `dates` with a price more than
    /// `maxAge` days older than the date.
    public func oldPrices(of account: AccountID, on dates: [CalendarDate],
                          maxAge: Int = oldPriceDays) -> [OldPrice] {
        dates.flatMap { date in value(of: account, on: date).map { oldPrices(in: $0, maxAge: maxAge) } ?? [] }
    }

    /// The positions of the accounts in `scope` valued on `dates` with a
    /// price more than `maxAge` days older than the date.
    public func oldPrices(in scope: NetWorthScope, on dates: [CalendarDate],
                          maxAge: Int = oldPriceDays) -> [OldPrice] {
        dates.flatMap { date in total(on: date, in: scope).accounts.flatMap { oldPrices(in: $0, maxAge: maxAge) } }
    }

    private func oldPrices(in value: AccountValue, maxAge: Int) -> [OldPrice] {
        value.components.compactMap { component in
            guard case .position(let instrument) = component.kind, let quantity = component.quantity, quantity != 0,
                  let price = component.price, price.date.days(to: value.date) > maxAge
            else { return nil }
            return OldPrice(date: value.date, account: value.account, instrument: instrument, priceDate: price.date)
        }
    }
}
