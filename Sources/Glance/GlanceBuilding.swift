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
            let history = valuator.dates(.monthEnds, in: .netWorth, through: asOf)
                .filter { $0 >= yearAgo }
                .map { date in
                    let total = valuator.total(on: date, in: .netWorth)
                    return GlancePoint(date: date, value: total.total, isComplete: total.isComplete)
                }
            netWorth = NetWorthGlance(
                date: asOf, total: now.total, isComplete: now.isComplete,
                sinceLastCheckIn: valuator.changeSinceLastCheckIn(asOf: asOf, in: .netWorth).map(NetWorthChange.init),
                thisYear: Self.changeThisYear(valuator: valuator, now: now), history: history)
            allocation = valuator.breakdown(of: now, by: .assetClass).slices
                .sorted { $0.key < $1.key }
                .compactMap(AllocationSlice.init)
        }

        var retirement: RetirementGlance?
        if let main = library.settings.mainPlan, let plan = library.plans[main] {
            let recorded = library.headlines(for: main)
            let birthDate = library.settings.person?.birthDate
            if let answer = answer ?? recorded.last.map({ RetirementAnswer(recorded: $0, birthDate: birthDate) }) {
                retirement = RetirementGlance(
                    plan: main, planName: plan.name, answer: answer,
                    history: recorded.filter { $0.date >= yearAgo && $0.date <= asOf }
                        .map { AnswerPoint(date: $0.date, earliestAge: $0.earliestAge) })
            }
        }

        self.init(currency: library.settings.baseCurrency, netWorth: netWorth, allocation: allocation,
                  retirement: retirement, checkIn: checkIn)
    }

    /// The change since 31 December of last year, as the Overview's hero
    /// has it: `nil` without a value by then, or when it was zero.
    static func changeThisYear(valuator: Valuator, now: NetWorth) -> Double? {
        guard let yearEnd = YearMonth(year: now.date.year - 1, month: 12)?.lastDay, yearEnd < now.date,
              let first = valuator.firstValuationDate(in: .netWorth), first <= yearEnd
        else { return nil }
        let start = valuator.total(on: yearEnd, in: .netWorth).total
        guard start != 0 else { return nil }
        return ((now.total - start) / abs(start)).doubleValue
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
