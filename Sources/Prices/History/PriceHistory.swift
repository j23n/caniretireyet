import Foundation
import Model

/// Where a price came from when it isn't the instrument's own provider
/// answering for its own symbol: a metal's past price from Yahoo Finance's
/// gold futures (`GC=F`), or a coin's prices from before CoinGecko's free
/// year from Yahoo Finance's `ETH-EUR` pair. Also names the source of each
/// stretch of a filled history ("CoinGecko · ethereum").
public struct QuoteOrigin: Hashable, Sendable, CustomStringConvertible {
    /// The source written on the price record, e.g. `yahoo`.
    public var source: DataSource
    /// The service's display name, e.g. "Yahoo Finance".
    public var service: String
    /// The symbol that was asked for, e.g. `GC=F`.
    public var symbol: String
    /// A word for the price list when the value comes from a stand-in for
    /// the instrument's own source, e.g. `history`: "Yahoo Finance · GC=F
    /// (history)". `nil` for the instrument's own source.
    public var note: String?

    public init(source: DataSource, service: String, symbol: String, note: String? = nil) {
        self.source = source
        self.service = service
        self.symbol = symbol
        self.note = note
    }

    /// "Yahoo Finance · GC=F (history)".
    public var description: String {
        "\(service) · \(symbol)" + (note.map { " (\($0))" } ?? "")
    }

    /// The note a stand-in source carries in the price list.
    public static let historyNote = "history"
}

/// Past prices of one symbol over a range of dates, as one request returned
/// them: a value per trading day (per calendar day for crypto), or per month
/// for a long range of month ends.
public struct PriceHistory: Hashable, Sendable {
    /// How far apart the values are.
    public enum Spacing: Hashable, Sendable {
        /// A value per trading day.
        case daily
        /// A value per month: the month's last close, observed on its last day.
        case monthly
    }

    /// One quote per day (or month), sorted by ``Quote/observedOn``.
    public private(set) var quotes: [Quote]
    public var spacing: Spacing
    /// Where the values come from, set by the history route that fetched them.
    public var origin: QuoteOrigin?

    /// How many days before a date a daily value may be and still count for
    /// it: a weekend, or a weekend and a holiday or two.
    public static let dailyTolerance = 7

    /// A history of `quotes`, sorted by day; of several quotes on one day,
    /// the last one given wins (Yahoo sometimes repeats today's bar with the
    /// live price).
    public init(quotes: [Quote], spacing: Spacing = .daily, origin: QuoteOrigin? = nil) {
        var byDay: [CalendarDate: Quote] = [:]
        for quote in quotes { byDay[quote.observedOn] = quote }
        self.quotes = byDay.values.sorted { $0.observedOn < $1.observedOn }
        self.spacing = spacing
        self.origin = origin
    }

    /// This history standing in for another source's: its origin noted as
    /// ``QuoteOrigin/historyNote``, and each quote per `unit` when given
    /// (troy ounces for metal futures).
    public func standingIn(unit: InstrumentUnit? = nil) -> PriceHistory {
        var copy = self
        copy.origin?.note = QuoteOrigin.historyNote
        if let unit {
            copy.quotes = quotes.map { quote in
                var quote = quote
                quote.unit = unit
                return quote
            }
        }
        return copy
    }

    /// The latest quote on or before `date` that counts for it: at most
    /// ``dailyTolerance`` days older in a daily series (Friday's close for a
    /// Sunday), or the one of the same month in a monthly series. `nil` if
    /// there's none, e.g. before the symbol was listed or in a gap in the data.
    public func quote(onOrBefore date: CalendarDate) -> Quote? {
        guard let index = quotes.lastIndex(onOrBefore: date, date: \.observedOn) else { return nil }
        let quote = quotes[index]
        switch spacing {
        case .daily: return quote.observedOn.days(to: date) <= Self.dailyTolerance ? quote : nil
        case .monthly: return quote.observedOn.yearMonth == date.yearMonth ? quote : nil
        }
    }
}

/// Past FX rates of one currency pair over a range of dates, as one request
/// returned them. A long range can come back thinned out to weekly rates.
public struct FXHistory: Hashable, Sendable {
    /// Rates sorted by the day they were published for.
    public private(set) var rates: [FXObservation]

    public init(rates: [FXObservation]) {
        var byDay: [CalendarDate: FXObservation] = [:]
        for rate in rates { byDay[rate.observedOn] = rate }
        self.rates = byDay.values.sorted { $0.observedOn < $1.observedOn }
    }

    /// Whether the rates are about a week apart rather than a working day:
    /// the typical gap between them is four days or more.
    public var isWeekly: Bool {
        guard rates.count > 2 else { return false }
        let gaps = zip(rates, rates.dropFirst()).map { $0.observedOn.days(to: $1.observedOn) }.sorted()
        return gaps[gaps.count / 2] >= 4
    }

    /// How many days before a date a rate may be: a week for daily rates
    /// (weekends, TARGET holidays), two for weekly ones.
    public var tolerance: Int { isWeekly ? 14 : PriceHistory.dailyTolerance }

    /// The latest rate on or before `date`, at most ``tolerance`` days older.
    public func rate(onOrBefore date: CalendarDate) -> FXObservation? {
        guard let index = rates.lastIndex(onOrBefore: date, date: \.observedOn) else { return nil }
        let rate = rates[index]
        return rate.observedOn.days(to: date) <= tolerance ? rate : nil
    }
}

/// The dates a history is fetched for.
public struct HistoryRange: Hashable, Sendable {
    /// The earliest day a value may come from (the first date wanted, less
    /// the lookback for weekends and holidays).
    public var from: CalendarDate
    /// The last date a value is wanted on.
    public var through: CalendarDate
    /// Whether every date wanted is the last day of its month, so a monthly
    /// series will do for a long range.
    public var monthEndsOnly: Bool
    /// Today, for providers whose history reaches back a limited time.
    public var today: CalendarDate

    public init(from: CalendarDate, through: CalendarDate, monthEndsOnly: Bool = false, today: CalendarDate) {
        self.from = from
        self.through = through
        self.monthEndsOnly = monthEndsOnly
        self.today = today
    }
}

/// One way to find an instrument's past prices: a symbol at a service that
/// answers a range of dates in one request. An instrument's provider lists
/// its routes best first (``InstrumentPriceProvider/historyRoutes(symbol:currency:today:)``),
/// and each is tried for the dates the ones before it didn't fill.
public struct HistoryRoute: Sendable {
    /// What it is, for messages: "Yahoo Finance · GC=F", "CoinGecko · ethereum".
    public var name: String
    /// The earliest date it has values for, when it's limited: CoinGecko's
    /// free API only has the last 365 days. `nil` when there's no known limit.
    public var earliest: CalendarDate?
    /// Why dates before ``earliest`` aren't covered, as a sentence.
    public var limitReason: String?
    /// Fetches the values over a range in one request (or a few, e.g. a
    /// search for the symbol first). The result names where it came from.
    public var fetch: @Sendable (HistoryRange) async throws -> PriceHistory

    public init(name: String, earliest: CalendarDate? = nil, limitReason: String? = nil,
                fetch: @escaping @Sendable (HistoryRange) async throws -> PriceHistory) {
        self.name = name
        self.earliest = earliest
        self.limitReason = limitReason
        self.fetch = fetch
    }

    /// Whether the route can have a value for `date`.
    public func covers(_ date: CalendarDate) -> Bool {
        earliest.map { date >= $0 } ?? true
    }
}
