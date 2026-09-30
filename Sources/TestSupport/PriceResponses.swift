import Foundation
import Model

/// Builds responses of the price services in their exact formats, for tests
/// that need a long series (a year of daily closes) rather than a short
/// recorded one. The build environment can't reach the services, so the
/// formats follow the recorded fixtures in `Tests/PricesTests/Fixtures`;
/// the numbers are made up.
public enum PriceResponses {
    /// A Yahoo Finance chart response (`v8/finance/chart/<symbol>`): one bar
    /// per entry of `bars`, at `hour`:00 on its day in the exchange's time
    /// zone, each close written as the float32-precision double Yahoo sends
    /// (`3488.449951171875`), `null` for a day without a close.
    public static func yahooChart(
        symbol: String, currency: String, exchangeName: String = "CMX", instrumentType: String = "FUTURE",
        timeZone: String = "America/New_York", priceHint: Int = 2, granularity: String = "1d", hour: Int = 0,
        bars: [(day: CalendarDate, close: Decimal?)]
    ) -> String {
        let zone = TimeZone(identifier: timeZone)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let instants = bars.map { bar in
            calendar.date(from: DateComponents(year: bar.day.year, month: bar.day.month, day: bar.day.day, hour: hour))!
        }
        let timestamps = instants.map { String(Int($0.timeIntervalSince1970)) }
        let closes = bars.map { bar in bar.close.map(float32) ?? "null" }
        let last = instants.last ?? Date(timeIntervalSince1970: 0)
        let offset = zone.secondsFromGMT(for: last)
        return #"{"chart":{"result":[{"meta":{"currency":"\#(currency)","symbol":"\#(symbol)","exchangeName":"\#(exchangeName)","#
            + #""instrumentType":"\#(instrumentType)","gmtoffset":\#(offset),"timezone":"\#(zone.abbreviation(for: last) ?? "UTC")","#
            + #""exchangeTimezoneName":"\#(timeZone)","priceHint":\#(priceHint),"dataGranularity":"\#(granularity)","#
            + #""range":"","validRanges":["1d","5d","1mo","3mo","6mo","1y","2y","5y","10y","ytd","max"]},"#
            + #""timestamp":[\#(timestamps.joined(separator: ","))],"#
            + #""indicators":{"quote":[{"close":[\#(closes.joined(separator: ","))]}]}}],"error":null}}"#
    }

    /// Every weekday from `start` through `end`, less `holidays`.
    public static func weekdays(from start: CalendarDate, through end: CalendarDate,
                                except holidays: Set<CalendarDate> = []) -> [CalendarDate] {
        var days: [CalendarDate] = []
        var day = start
        while day <= end {
            // 1970-01-01 was a Thursday, so 2 and 3 days after one are a Saturday and a Sunday.
            let weekday = ((day.daysSinceEpoch % 7) + 7) % 7
            if weekday != 2, weekday != 3, !holidays.contains(day) { days.append(day) }
            day = day.adding(days: 1)
        }
        return days
    }

    /// A CoinGecko `coins/{id}/market_chart/range` response: `[ms, price]`
    /// points, with market caps and volumes alongside as CoinGecko sends them.
    public static func coinGeckoMarketChart(_ points: [(instant: Date, price: Decimal)]) -> String {
        func series(_ scale: Decimal) -> String {
            points.map { "[\(Int64($0.instant.timeIntervalSince1970 * 1000)),\(($0.price * scale).description)]" }
                .joined(separator: ",")
        }
        return #"{"prices":[\#(series(1))],"market_caps":[\#(series(120_000_000))],"#
            + #""total_volumes":[\#(series(9_000_000))]}"#
    }

    /// Midnight UTC at the start of `day`.
    public static func midnightUTC(_ day: CalendarDate) -> Date {
        Date(timeIntervalSince1970: TimeInterval(day.daysSinceEpoch) * 86_400)
    }

    /// `value` as Yahoo writes a close: the float32 nearest to it, printed as a double.
    static func float32(_ value: Decimal) -> String {
        let single = Float((value as NSDecimalNumber).doubleValue)
        return "\(Double(single))"
    }
}
