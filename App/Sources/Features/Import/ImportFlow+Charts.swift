import Foundation
import Importer
import Model
import Tracker

/// What a bank statement's Preview draws, to check the import before it's
/// written (UI.md, "Import"): money in and out by month over the days the
/// file covers, as Trends will show it with the import applied, and the
/// account's balance day by day from the file against its values before
/// the import.
struct ImportStatementCharts {
    /// A balance at the end of a day.
    struct Balance: Hashable, Identifiable {
        var date: CalendarDate
        var balance: Decimal

        var id: CalendarDate { date }
    }

    /// Money in and out by month with the import applied.
    var money: PlanMoneyInOut
    /// The account's balance by the file at the end of each day with a line,
    /// and the day before the first line, oldest first.
    var file: [Balance]
    /// The account's values before the import in the days the file covers:
    /// check-ins and earlier imports, oldest first.
    var before: [Balance]

    /// The file's balance at the end of `date`: the last day's before it,
    /// or the balance before the first line.
    func fileBalance(on date: CalendarDate) -> Decimal? {
        (file.last { $0.date <= date } ?? file.first)?.balance
    }

    /// Whether the file gives `value`'s balance on its day.
    func agrees(_ value: Balance) -> Bool {
        fileBalance(on: value.date) == value.balance
    }

    /// "The line is the file's balance, the dots the account's values before
    /// this import: 3 of 4 agree."
    var balanceCaption: String {
        guard !before.isEmpty else {
            return "The line is the file's balance. The account has no values in these days yet."
        }
        let agreeing = before.filter(agrees).count
        let count = agreeing == before.count
            ? (before.count == 1 ? "it agrees" : "all \(before.count) agree")
            : "\(agreeing) of \(before.count) agree"
        return "The line is the file's balance, the dots the account's values before this import: \(count)."
    }

    /// The balance at the end of each day with a line, worked back from the
    /// values the import writes (`values`, by date): a day's balance is the
    /// next value's less the lines after the day up to it. Lines after the
    /// last value are left out, as the import leaves them out.
    static func dayEnds(lines: [(date: CalendarDate, amount: Decimal)], values: [Balance]) -> [Balance] {
        let values = values.sorted { $0.date < $1.date }
        guard let last = values.last else { return [] }
        let lines = lines.filter { $0.date <= last.date }.sorted { $0.date < $1.date }
        var days = Set(lines.map(\.date)).union(values.map(\.date))
        if let first = lines.first?.date { days.insert(first.adding(days: -1)) }
        return days.sorted().compactMap { day in
            guard let value = values.first(where: { $0.date >= day }) else { return nil }
            let later = lines.filter { $0.date > day && $0.date <= value.date }.reduce(Decimal(0)) { $0 + $1.amount }
            return Balance(date: day, balance: value.balance - later)
        }
    }
}

extension ImportFlow {
    /// A bank statement's charts, once its account and the days it covers
    /// are known; `nil` for any other file. Money in and out ends where
    /// Trends' would in the file's last month: Trends ends at the planned
    /// library's latest check-in of the plan's accounts, so at the month's
    /// last day when that check-in is in a later month, otherwise at it,
    /// when that's after the file's last day.
    func makeStatementCharts() -> ImportStatementCharts? {
        guard layout == .statement, let account = constants.account, let period = statementPeriod,
              let after = planned?.library else { return nil }
        let values = (preview?.records ?? []).compactMap { record -> ImportStatementCharts.Balance? in
            guard case .valuation(let key) = record.imported.key, key.account == account,
                  let balance = record.imported.balance else { return nil }
            return ImportStatementCharts.Balance(date: key.date, balance: balance)
        }
        let lines = statementLines.filter { $0.date >= period.from && $0.date <= period.through }
            .map { (date: $0.date, amount: $0.amount) }
        let before = library.valuations(for: account)
            .filter { $0.date >= period.from && $0.date <= period.through }
            .compactMap { valuation in
                valuation.balance.map { ImportStatementCharts.Balance(date: valuation.date, balance: $0) }
            }
        let valuator = Tracker.Valuator(library: after)
        let latest = valuator.latestCheckIn(onOrBefore: .today(), in: .planAssets) ?? period.through
        let end = latest.yearMonth > period.through.yearMonth ? period.through.endOfMonth : max(period.through, latest)
        let money = PlanMoneyInOut(valuator.moneyInOutSeries(.months, through: end),
                                   from: period.from, firstRecord: nil, through: end)
        return ImportStatementCharts(money: money, file: ImportStatementCharts.dayEnds(lines: lines, values: values),
                                     before: before)
    }
}
