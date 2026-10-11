import Foundation
import Model

extension Baseline {
    /// The start value as each of the five percentiles, then each year-end
    /// after the start with its p10, p25, p50, p75 and p90, by date.
    public var percentileKnots: [(date: CalendarDate, bands: [Decimal])] {
        var knots = [(date: start.date, bands: Array(repeating: start.value, count: 5))]
        for year in years {
            guard let end = YearMonth(year: year.year, month: 12)?.lastDay, end > start.date else { continue }
            knots.append((date: end, bands: [year.p10, year.p25, year.p50, year.p75, year.p90]))
        }
        return knots.sorted { $0.date < $1.date }
    }

    /// p10, p25, p50, p75 and p90 on `date`, from the start through the last
    /// year-end; `nil` outside them (PROGRESS.md, "On track"). Between the
    /// start and the year-ends, the median is interpolated by days, and the
    /// spread around it grows as the futures' does, with the square root of
    /// time: each percentile's distance from the median is interpolated in
    /// its square. From the start, where the futures haven't spread yet, a
    /// month into the year the band is √(1/12), about 29%, as wide as at the
    /// year's end.
    public func percentiles(on date: CalendarDate) -> [Double]? {
        let knots = percentileKnots.map { (date: $0.date, bands: $0.bands.map(\.doubleValue)) }
        guard date >= start.date, let after = knots.firstIndex(where: { $0.date >= date }) else { return nil }
        if after == 0 || knots[after].date == date { return knots[after].bands }
        let from = knots[after - 1]
        let to = knots[after]
        let t = Double(from.date.days(to: date)) / Double(max(1, from.date.days(to: to.date)))
        let median = from.bands[2] + (to.bands[2] - from.bands[2]) * t
        return zip(from.bands, to.bands).map { (first, last) -> Double in
            let fromMedian = first - from.bands[2]
            let toMedian = last - to.bands[2]
            // On opposite sides of the median at the two ends: linearly.
            guard fromMedian * toMedian >= 0 else { return median + fromMedian + (toMedian - fromMedian) * t }
            let spread = (fromMedian * fromMedian * (1 - t) + toMedian * toMedian * t).squareRoot()
            return fromMedian + toMedian < 0 ? median - spread : median + spread
        }
    }
}

/// Whether you're ahead of, on or behind plan (PROGRESS.md, "On track"):
/// where an amount is among a baseline's futures, not against its median,
/// which someone exactly on track is below in half of them.
public enum BaselineStanding: Hashable, Sendable {
    case ahead
    case onPlan
    case behind

    /// Above this percentile, as it's said in whole numbers, is ahead.
    public static let upper = 75.0
    /// Below this percentile, as it's said in whole numbers, is behind.
    public static let lower = 25.0
    /// Within this share of the median is on plan wherever the percentiles
    /// are: a plan with little volatility, such as one in cash, has futures
    /// so close together that a few euros would otherwise be ahead or behind.
    public static let tolerance = 0.01

    /// From the percentile (0...100 within the 10–90 band, ``percentile(of:in:)``;
    /// `nil` outside it), whether you're below or above the band, and
    /// whether you're within ``tolerance`` of the median.
    public init(percentile: Double?, isBelowTenth: Bool, isAboveNinetieth: Bool, isNearMedian: Bool) {
        // As the percentile is said: "more than in 25 of its 100 futures" is on plan.
        let said = percentile?.rounded()
        if isNearMedian {
            self = .onPlan
        } else if isAboveNinetieth {
            self = .ahead
        } else if isBelowTenth {
            self = .behind
        } else if let said, said > Self.upper {
            self = .ahead
        } else if let said, said < Self.lower {
            self = .behind
        } else {
            self = .onPlan
        }
    }

    /// The standing of `value` among `bands`: p10, p25, p50, p75 and p90.
    public init(of value: Double, in bands: [Double]) {
        self.init(percentile: Self.percentile(of: value, in: bands),
                  isBelowTenth: bands.first.map { value < $0 } ?? false,
                  isAboveNinetieth: bands.last.map { value > $0 } ?? false,
                  isNearMedian: bands.count == 5 && Self.isNear(value, median: bands[2]))
    }

    /// Whether `value` is within ``tolerance`` of `median`.
    public static func isNear(_ value: Double, median: Double) -> Bool {
        abs(value - median) <= tolerance * abs(median)
    }

    /// The percentile of `value` among p10, p25, p50, p75 and p90 (`bands`),
    /// linearly between them; `nil` outside the 10–90 band. A value on
    /// percentiles that are equal, as a plan without volatility has, is at
    /// the middle of their levels: on all five, the 50th.
    public static func percentile(of value: Double, in bands: [Double]) -> Double? {
        let levels = [10.0, 25, 50, 75, 90]
        guard bands.count == levels.count, let low = bands.first, let high = bands.last, value >= low, value <= high
        else { return nil }
        if let first = bands.firstIndex(of: value), let last = bands.lastIndex(of: value) {
            return (levels[first] + levels[last]) / 2
        }
        // Not on a band, so strictly between two that differ.
        for index in 1..<bands.count where value < bands[index] {
            let share = (value - bands[index - 1]) / (bands[index] - bands[index - 1])
            return levels[index - 1] + (levels[index] - levels[index - 1]) * share
        }
        return nil
    }
}
