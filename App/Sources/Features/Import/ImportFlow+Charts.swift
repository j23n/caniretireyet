import Foundation
import Importer
import Model
import Tracker

/// What bank statements' Review draws, to check the import before it's
/// written (UI.md, "Import"): what came in and was spent each month of the
/// import's last year, as Trends will count it with the import applied, and
/// one account's balance by the files against its values before the
/// import.
struct ImportStatementCharts {
    /// A balance at the end of a day.
    struct Balance: Hashable, Identifiable {
        var date: CalendarDate
        var balance: Decimal

        var id: CalendarDate { date }
    }

    /// One month's pair of bars.
    struct Month: Hashable, Identifiable {
        var month: YearMonth
        var cameIn: Decimal
        var spent: Decimal
        /// The current month, not over yet.
        var isSoFar: Bool

        var id: YearMonth { month }
    }

    /// The year drawn: the year of the import's last day.
    var year: Int
    /// Money in and out by month with the import applied, from the year's
    /// first day.
    var money: PlanMoneyInOut
    /// The account whose balance is drawn: the first with a value before
    /// the import in the year that the files disagree with, else the first
    /// file's.
    var account: AccountID
    /// Its name, for "Girokonto, balance".
    var accountName: String
    /// The account's balance by the files at the end of each day with a
    /// line in the year, and of the day before, oldest first.
    var file: [Balance]
    /// The account's values before the import in the year, on the days the
    /// files cover: check-ins and earlier imports, oldest first.
    var before: [Balance]

    /// "Came in and spent, 2025".
    var moneyTitle: String { "Came in and spent, \(year)" }

    /// "Girokonto, balance".
    var balanceTitle: String { "\(accountName), balance" }

    /// The year's months from January, each with what came in and was
    /// spent; nothing in the months before money in and out was recorded.
    var months: [Month] {
        let periods = money.periods.filter { $0.through.year == year }
        guard let last = periods.last?.through.yearMonth, let january = YearMonth(year: year, month: 1) else {
            return []
        }
        return (0...january.months(to: last)).map { offset in
            let month = january.adding(months: offset)
            guard let period = periods.first(where: { $0.through.yearMonth == month }) else {
                return Month(month: month, cameIn: 0, spent: 0, isSoFar: false)
            }
            return Month(month: month, cameIn: period.cameIn, spent: period.spent, isSoFar: money.isSoFar(period))
        }
    }

    /// The file's balance at the end of `date`: the last day's before it,
    /// or the balance before the first line.
    func fileBalance(on date: CalendarDate) -> Decimal? {
        Self.balance(on: date, in: file)
    }

    /// Whether the file gives `value`'s balance on its day.
    func agrees(_ value: Balance) -> Bool {
        fileBalance(on: value.date) == value.balance
    }

    /// The balance at the end of `date` by `file`'s day ends: the last
    /// day's before it, or the first's.
    static func balance(on date: CalendarDate, in file: [Balance]) -> Decimal? {
        (file.last { $0.date <= date } ?? file.first)?.balance
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
    /// The account the batch's file `file` is a statement of.
    func statementAccount(ofFile file: Int) -> AccountID? {
        batch?.files.first { $0.id == file }?.account
    }

    /// Bank statements' charts, once their accounts and the days they
    /// cover are known; `nil` for any other file. Money in and out starts
    /// on the first day of the year of the import's last day, and ends
    /// where Trends' would in the import's last month: Trends ends at the
    /// planned library's latest check-in of the plan's accounts, so at the
    /// month's last day when that check-in is in a later month, otherwise
    /// at it, when that's after the import's last day.
    func makeStatementCharts() -> ImportStatementCharts? {
        guard layout == .statement, let period = statementsPeriod, let after = planned?.library else { return nil }
        let year = period.through.year
        let start = CalendarDate.firstDay(ofYear: year)
        let balances = reviewBalances(from: start)
        guard let shown = balances.first(where: \.disagrees) ?? balances.first else { return nil }
        let valuator = Tracker.Valuator(library: after)
        let latest = valuator.latestCheckIn(onOrBefore: .today(), in: .planAssets) ?? period.through
        let end = latest.yearMonth > period.through.yearMonth ? period.through.endOfMonth : max(period.through, latest)
        let money = PlanMoneyInOut(valuator.moneyInOutSeries(.months, through: end), from: start, firstRecord: nil,
                                   through: end)
        let name = after.accounts[shown.account]?.name ?? accountName(shown.account)
        return ImportStatementCharts(year: year, money: money, account: shown.account, accountName: name,
                                     file: shown.file, before: shown.before)
    }

    /// Each statement account's balance by its files from the day before
    /// `start`, and its values before the import from `start` on the days
    /// its files cover, in the order the files are imported.
    private func reviewBalances(from start: CalendarDate) -> [ImportReviewBalance] {
        var accounts: [AccountID] = []
        for (file, _) in previews {
            if let account = statementAccount(ofFile: file), !accounts.contains(account) { accounts.append(account) }
        }
        return accounts.map { account in
            let previews = self.previews.filter { statementAccount(ofFile: $0.file) == account }.map(\.preview)
            let values = previews.flatMap(\.records).compactMap { record -> ImportStatementCharts.Balance? in
                guard case .valuation(let key) = record.imported.key, key.account == account,
                      let balance = record.imported.balance else { return nil }
                return ImportStatementCharts.Balance(date: key.date, balance: balance)
            }
            let periods = previews.compactMap(\.statementPeriod)
            let lines = previews.flatMap { preview in
                preview.statementLines.filter { line in
                    preview.statementPeriod?.contains(line.date) ?? false
                }
            }.map { (date: $0.date, amount: $0.amount) }
            let file = ImportStatementCharts.dayEnds(lines: lines, values: values)
            let before = library.valuations(for: account)
                .filter { valuation in
                    valuation.date >= start
                        && periods.contains { valuation.date >= $0.from && valuation.date <= $0.through }
                }
                .compactMap { valuation in
                    valuation.balance.map { ImportStatementCharts.Balance(date: valuation.date, balance: $0) }
                }
            let disagrees = before.contains { ImportStatementCharts.balance(on: $0.date, in: file) != $0.balance }
            // The year's days, and the last day before them for the line to start from.
            let dayBefore = start.adding(days: -1)
            let opening = file.last { $0.date <= dayBefore }
            let shown = (opening.map { [$0] } ?? []) + file.filter { $0.date > dayBefore }
            return ImportReviewBalance(account: account, file: shown, before: before, disagrees: disagrees)
        }
    }
}

/// A statement account's balance on Review, before one is chosen to draw.
private struct ImportReviewBalance {
    var account: AccountID
    var file: [ImportStatementCharts.Balance]
    var before: [ImportStatementCharts.Balance]
    /// Whether a value before the import differs from the files'.
    var disagrees: Bool
}
