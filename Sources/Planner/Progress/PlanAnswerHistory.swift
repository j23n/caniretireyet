import Foundation
import Model

/// The answer recorded at each check-in (Trends' *Time to retirement*),
/// with markers where the plan or the app's calculations changed, so a move
/// caused by markets and savings can be told from one caused by editing the
/// plan.
public struct PlanAnswerHistory: Hashable, Sendable {
    /// Why the answer may have moved for reasons other than your money.
    public enum Change: String, Hashable, Sendable, CaseIterable {
        /// The plan's inputs changed (`planHash`).
        case plan
        /// The app's calculations changed (`engine`).
        case engine
    }

    public struct Marker: Hashable, Sendable, Identifiable {
        public var date: CalendarDate
        public var changes: [Change]

        public var id: CalendarDate { date }
    }

    /// The answers recorded at check-ins, oldest first.
    public var points: [Headline]
    public var markers: [Marker]

    /// - Parameter headlines: a plan's, by date (``Library/headlines(for:)``).
    public init(_ headlines: [Headline]) {
        points = headlines
        var markers: [Marker] = []
        for (previous, next) in zip(headlines, headlines.dropFirst()) {
            var changes: [Change] = []
            if previous.planHash != next.planHash { changes.append(.plan) }
            if previous.engine != next.engine { changes.append(.engine) }
            if !changes.isEmpty { markers.append(Marker(date: next.date, changes: changes)) }
        }
        self.markers = markers
    }

    /// The answers recorded on or after `start` (all of them when `nil`).
    public func since(_ start: CalendarDate?) -> PlanAnswerHistory {
        guard let start else { return self }
        return PlanAnswerHistory(points.filter { $0.date >= start })
    }

    /// The latest recorded earliest age.
    public var latestAge: Int? { points.last?.earliestAge }

    /// How the earliest age moved since the first check-in that had one:
    /// negative is earlier (good). `nil` with fewer than two.
    public var change: (years: Int, since: CalendarDate)? {
        guard let latest = points.last, let latestAge = latest.earliestAge,
              let first = points.first(where: { $0.earliestAge != nil }), first.date < latest.date,
              let firstAge = first.earliestAge
        else { return nil }
        return (latestAge - firstAge, first.date)
    }

    /// The check-ins that recorded a pace age (``Headline/paceAge``).
    public var pacePoints: [Headline] { points.filter { $0.paceAge != nil } }

    /// The check-ins that recorded a coast age (``Headline/coastAge``).
    public var coastPoints: [Headline] { points.filter { $0.coastAge != nil } }

    /// The range of ages to chart, the earliest, pace and coast ages, with a little room.
    public var ageRange: ClosedRange<Int> {
        let ages = points.compactMap(\.earliestAge) + points.compactMap(\.paceAge) + points.compactMap(\.coastAge)
        guard let low = ages.min(), let high = ages.max() else { return 50...60 }
        return (low - 2)...(high + 2)
    }
}
