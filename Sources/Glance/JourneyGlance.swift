import Foundation
import Model
import Tracker

/// The way to retiring so far, for the notes that remind you of it (UI.md,
/// "Notifications") and the screens that show it: the answers recorded at
/// check-ins, the milestones reached, when the records and the plan
/// started, and what the last two calendar years added.
public struct JourneyGlance: Hashable, Sendable {
    /// Your birthday (Settings), for the birthday note; `nil` without one.
    public var birthDate: CalendarDate?
    /// The first record of net worth; `nil` before the first check-in.
    public var firstRecord: CalendarDate?
    /// The main plan's answers recorded at check-ins, oldest first.
    public var checkIns: [JourneyPoint]
    /// The main plan's name; `nil` without a main plan.
    public var planName: String?
    /// When the main plan last changed: the first check-in that recorded
    /// it as it is now; `nil` before one did.
    public var planChanged: CalendarDate?
    /// When each of the main plan's milestones was reached, oldest first.
    public var reached: [CalendarDate]
    /// The main plan's retirement spending a year, in today's money and
    /// ``GlanceSnapshot/currency``; `nil` without one.
    public var yearlySpending: Decimal?
    /// Last calendar year and this one so far, oldest first; a year without
    /// a check-in is left out.
    public var years: [JourneyYear]

    public init(birthDate: CalendarDate? = nil, firstRecord: CalendarDate? = nil, checkIns: [JourneyPoint] = [],
                planName: String? = nil, planChanged: CalendarDate? = nil, reached: [CalendarDate] = [],
                yearlySpending: Decimal? = nil, years: [JourneyYear] = []) {
        self.birthDate = birthDate
        self.firstRecord = firstRecord
        self.checkIns = checkIns
        self.planName = planName
        self.planChanged = planChanged
        self.reached = reached
        self.yearlySpending = yearlySpending
        self.years = years
    }

    /// The latest check-in's answer.
    public var latest: JourneyPoint? { checkIns.last }

    /// The first check-in that recorded an age.
    public var firstWithAge: JourneyPoint? { checkIns.first { $0.earliestAge != nil } }

    /// The latest check-in on or before `date`.
    public func checkIn(onOrBefore date: CalendarDate) -> JourneyPoint? {
        checkIns.last { $0.date <= date }
    }

    /// The check-in before the latest one.
    public var previous: JourneyPoint? {
        checkIns.count >= 2 ? checkIns[checkIns.count - 2] : nil
    }

    /// The last `count` check-ins, oldest first, for a chart of the age.
    public func recent(_ count: Int = 12) -> [JourneyPoint] {
        Array(checkIns.suffix(count))
    }

    /// The calendar year `year`, if it had a check-in.
    public func year(_ year: Int) -> JourneyYear? {
        years.first { $0.year == year }
    }

    /// How many milestones were reached in `year`.
    public func reachedCount(in year: Int) -> Int {
        reached.filter { $0.year == year }.count
    }
}

/// The answer recorded at one check-in.
public struct JourneyPoint: Hashable, Sendable, Codable {
    public var date: CalendarDate
    /// `nil` when no age worked out.
    public var earliestAge: Int?
    /// As recorded (``Readiness``): 0.58 is 58%; `nil` in older records.
    public var readiness: Double?

    public init(date: CalendarDate, earliestAge: Int?, readiness: Double? = nil) {
        self.date = date
        self.earliestAge = earliestAge
        self.readiness = readiness
    }

    /// Readiness in whole percent: 58.
    public var readinessPercent: Int? {
        readiness.map { Int(($0 * 100 + 1e-9).rounded(.down)) }
    }
}

/// What one calendar year added to net worth, from 31 December before it
/// (or the first record) to its last check-in.
public struct JourneyYear: Hashable, Sendable {
    public var year: Int
    public var from: CalendarDate
    /// The year's last check-in.
    public var to: CalendarDate
    /// Money added, as the Overview's *Saved* counts it.
    public var saved: Decimal
    /// What markets added (+) or took (−).
    public var markets: Decimal

    public init(year: Int, from: CalendarDate, to: CalendarDate, saved: Decimal, markets: Decimal) {
        self.year = year
        self.from = from
        self.to = to
        self.saved = saved
        self.markets = markets
    }

    /// Whether the year's December was checked in: the year is complete.
    public var isComplete: Bool { to.month == 12 }
}

extension JourneyGlance {
    /// The journey of `library`'s main plan as of `asOf`.
    ///
    /// - Parameters:
    ///   - reached: when the main plan's milestones were reached, as the
    ///     Planner works them out (`PlanProgress.reached`).
    ///   - yearlySpending: the main plan's retirement spending a year, in
    ///     the base currency (the Planner's `MilestoneLadder.spending`).
    public init(library: Library, valuator: Valuator, asOf: CalendarDate, reached: [CalendarDate],
                yearlySpending: Decimal?) {
        var headlines: [Headline] = []
        var planName: String?
        if let main = library.settings.mainPlan, let plan = library.plans[main] {
            planName = plan.name
            headlines = library.headlines(for: main).filter { $0.date <= asOf }
        }
        let changed = zip(headlines, headlines.dropFirst()).filter { $0.planHash != $1.planHash }.last?.1.date
        let firstRecord = valuator.firstValuationDate(in: .netWorth)
        self.init(
            birthDate: library.settings.person?.birthDate,
            firstRecord: firstRecord,
            checkIns: headlines.map {
                JourneyPoint(date: $0.date, earliestAge: $0.earliestAge, readiness: $0.readiness?.doubleValue)
            },
            planName: planName,
            planChanged: changed ?? headlines.first?.date,
            reached: reached.sorted(),
            yearlySpending: yearlySpending,
            years: firstRecord.map { first in
                [asOf.year - 1, asOf.year].compactMap {
                    JourneyYear(year: $0, valuator: valuator, firstRecord: first, asOf: asOf)
                }
            } ?? [])
    }
}

extension JourneyYear {
    /// `year` from 31 December before it, or the first record when that's
    /// later, to its last check-in on or before `asOf`; `nil` without one.
    init?(year: Int, valuator: Valuator, firstRecord: CalendarDate, asOf: CalendarDate) {
        let start = max(CalendarDate.lastDay(ofYear: year - 1), firstRecord)
        guard let end = valuator.latestCheckIn(onOrBefore: min(CalendarDate.lastDay(ofYear: year), asOf),
                                               in: .netWorth),
              end > start
        else { return nil }
        let split = valuator.savedSplit(of: valuator.change(from: start, to: end, in: .netWorth))
        self.init(year: year, from: start, to: end, saved: split.newMoney, markets: split.market)
    }
}
