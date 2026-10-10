import Foundation
import Model
import Tracker

extension GlanceSnapshot {
    /// The snapshot of `library` as the Overview shows it.
    ///
    /// - Parameters:
    ///   - asOf: the date net worth is reported on: today, as on the
    ///     Overview. The change is the last check-in's on or before it.
    ///   - answer: the main plan's latest answer, from its latest results;
    ///     `nil` takes the last answer recorded at a check-in, as the
    ///     Overview does.
    ///   - checkIn: when the next check-in is due.
    public init(library: Library, valuator: Valuator, asOf: CalendarDate, answer: RetirementAnswer?,
                checkIn: CheckInGlance) {
        let yearAgo = asOf.adding(years: -1)
        var netWorth: NetWorthGlance?
        var allocation: [AllocationSlice] = []
        if valuator.firstValuationDate(in: .netWorth) != nil {
            let now = valuator.total(on: asOf, in: .netWorth)
            netWorth = NetWorthGlance(valuator: valuator, now: now, historyFrom: yearAgo)
            allocation = valuator.breakdown(of: now, by: .assetClass).slices
                .sorted { $0.key < $1.key }
                .compactMap(AllocationSlice.init)
        }

        var retirement: RetirementGlance?
        if let main = library.settings.mainPlan, library.plans[main] != nil {
            let recorded = library.headlines(for: main)
            let birthDate = library.settings.person?.birthDate
            if let answer = answer ?? recorded.last.map({ RetirementAnswer(recorded: $0, birthDate: birthDate) }) {
                retirement = RetirementGlance(
                    answer: answer,
                    history: recorded.filter { $0.date >= yearAgo && $0.date <= asOf }
                        .map { AnswerPoint(date: $0.date, earliestAge: $0.earliestAge) })
            }
        }

        self.init(currency: library.settings.baseCurrency, netWorth: netWorth, allocation: allocation,
                  retirement: retirement, checkIn: checkIn)
    }
}

extension NetWorthGlance {
    /// Net worth on `date` as the Overview's hero has it, and the widgets:
    /// the total, the change at the last check-in on or before `date`, and
    /// the change since 31 December of last year. With `start`, the history
    /// has each month end from `start` through `date`, and `date` itself.
    public init(valuator: Valuator, asOf date: CalendarDate, historyFrom start: CalendarDate? = nil) {
        self.init(valuator: valuator, now: valuator.total(on: date, in: .netWorth), historyFrom: start)
    }

    /// The same from `now`, net worth on the date, once it's worked out.
    init(valuator: Valuator, now: NetWorth, historyFrom start: CalendarDate?) {
        let history = start.map { start in
            valuator.dates(.monthEnds, in: .netWorth, through: now.date)
                .filter { $0 >= start }
                .map { GlancePoint(date: $0, value: valuator.total(on: $0, in: .netWorth).total) }
        }
        self.init(
            date: now.date, total: now.total, isComplete: now.isComplete,
            sinceLastCheckIn: valuator.changeSinceLastCheckIn(asOf: now.date, in: .netWorth).map(NetWorthChange.init),
            thisYear: Self.relativeChangeThisYear(valuator: valuator, now: now), history: history ?? [])
    }

    /// The change since 31 December of last year: `nil` without a value by
    /// then, or when it was zero.
    private static func relativeChangeThisYear(valuator: Valuator, now: NetWorth) -> Double? {
        guard let yearEnd = valuator.endOfLastYear(before: now.date) else { return nil }
        let start = valuator.total(on: yearEnd, in: .netWorth).total
        guard start != 0 else { return nil }
        return ((now.total - start) / abs(start)).doubleValue
    }
}

extension Valuator {
    /// 31 December of the year before `date`, where "this year" starts for
    /// the Overview's hero and its *This year*: `nil` when net worth has no
    /// value by then, so a library started this year has no change this year.
    public func endOfLastYear(before date: CalendarDate) -> CalendarDate? {
        guard let yearEnd = YearMonth(year: date.year - 1, month: 12)?.lastDay, yearEnd < date,
              let first = firstValuationDate(in: .netWorth), first <= yearEnd
        else { return nil }
        return yearEnd
    }

    /// How net worth changed from 31 December of last year to `date`, split
    /// into markets, new money and other (``change(from:to:in:)``), for the
    /// Overview's *This year*; `nil` without a value by 31 December.
    public func changeThisYear(asOf date: CalendarDate) -> ChangeReport? {
        endOfLastYear(before: date).map { change(from: $0, to: date, in: .netWorth) }
    }
}

extension NetWorthChange {
    /// The change between two check-ins, from Tracker's report.
    public init(_ report: ChangeReport) {
        self.init(from: report.from, to: report.to, start: report.total.start, markets: report.total.market,
                  newMoney: report.total.newMoney, other: report.total.other, end: report.total.end)
    }
}

extension AllocationSlice {
    /// An asset class's slice, or the debts'; `nil` for a slice of another
    /// breakdown.
    public init?(_ slice: BreakdownSlice) {
        let key: String
        switch slice.key {
        case .assetClass(let assetClass): key = assetClass.rawValue
        case .debts: key = Self.debts
        default: return nil
        }
        self.init(key: key, name: slice.key.description, value: slice.value,
                  share: slice.shareOfAssets?.doubleValue)
    }
}
