import Foundation

// Value axes beyond ``AmountScale``'s basics, without SwiftUI so they can be
// tested on Linux: headroom for marker labels, a projection's axis that the
// 10–90% band doesn't set, and a relative axis for when amounts are hidden.

extension AmountScale {
    /// The scale with `points` of room above its top, in a plot `plotHeight`
    /// points high: the rows of marker labels go there, never over the data
    /// or above the chart. The ticks stay where they were.
    func reservingTop(points: Double, plotHeight: Double) -> AmountScale {
        guard points > 0, plotHeight > points else { return self }
        let fraction = min(points / plotHeight, 0.4)
        let top = domain.upperBound
        let raised = domain.lowerBound + (top - domain.lowerBound) / (1 - fraction)
        var scale = self
        scale.domain = domain.lowerBound...raised
        scale.headroom = top...raised
        return scale
    }

    /// The top of the data: where the headroom starts, or the domain's top.
    var dataTop: Double {
        headroom?.lowerBound ?? domain.upperBound
    }

    /// Ticks as multiples of `base` (`0`, `0,5×`, `1×`, `2×`) over the same
    /// span as the amount ticks, for when amounts are hidden (UI.md,
    /// "Privacy"): the chart keeps a meaningful axis without revealing an
    /// amount. Empty when `base` isn't positive.
    func relativeTicks(base: Double, locale: Locale = .current) -> [RelativeTick] {
        guard base > 0, base.isFinite, let first = ticks.first, let last = ticks.last else { return [] }
        let low = Swift.min(first, 0) / base
        let high = Swift.max(last, dataTop * 0.999) / base
        guard high > low else { return [] }
        let candidates = [0.05, 0.1, 0.2, 0.25, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1_000]
        let step = candidates.first { step in
            Int((high / step).rounded(.down)) - Int((low / step).rounded(.up)) + 1 <= 5
        } ?? candidates[candidates.count - 1]
        var result: [RelativeTick] = []
        var index = Int((low / step).rounded(.up))
        while Double(index) * step <= high + step * 1e-9 {
            let multiple = Double(index) * step
            result.append(RelativeTick(value: multiple * base, label: Self.multipleLabel(multiple, locale: locale)))
            index += 1
        }
        return result
    }

    /// `0`, `0,5×`, `1×`, `−0,5×`.
    static func multipleLabel(_ multiple: Double, locale: Locale = .current) -> String {
        guard abs(multiple) > 1e-9 else { return "0" }
        let number = multiple.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        return AmountFormat.typographicMinus(number + "×")
    }
}

/// A tick of a relative axis: where it is, in amounts, and its label.
struct RelativeTick: Hashable, Sendable {
    var value: Double
    var label: String
}

/// The value axis of a projection, with or without history before it
/// (UI.md, "Charts"): it fits the history, the median and the 25–75% band,
/// so they fill the chart. The 10–90% band may run off the top, where it's
/// cut at the chart's edge (``clamped(_:)``) and the legend says so
/// (``clipsBand``). Room for `markerRows` rows of labels is kept above the data.
struct ProjectionScale: Hashable, Sendable {
    var scale: AmountScale
    /// Whether the 10–90% band runs off the top somewhere.
    var clipsBand: Bool

    init(history: [Double], fan: [FanPoint], markerHeadroom: Double = 0, plotHeight: Double = 200) {
        let values = history + fan.flatMap { [$0.p25, $0.p50, $0.p75] }
        var scale = AmountScale(values: values)
        if markerHeadroom > 0 {
            scale = scale.reservingTop(points: markerHeadroom, plotHeight: plotHeight)
        }
        self.scale = scale
        clipsBand = fan.contains { $0.p90 > scale.domain.upperBound || $0.p10 < scale.domain.lowerBound }
    }

    /// The point with every percentile kept inside the domain, so the bands
    /// are cut at the chart's edge instead of drawn past it.
    func clamped(_ point: FanPoint) -> FanPoint {
        let range = scale.domain
        func clamp(_ value: Double) -> Double { Swift.min(Swift.max(value, range.lowerBound), range.upperBound) }
        return FanPoint(date: point.date, p10: clamp(point.p10), p25: clamp(point.p25), p50: clamp(point.p50),
                        p75: clamp(point.p75), p90: clamp(point.p90))
    }
}
