import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// A simulated household with known truth (`HouseholdSimulator`, in
/// TestSupport): a seed plays out one to three years of pay, spending,
/// transfers, trades, a pension, a mortgage, a tax bill and more, day by
/// day, and the app's numbers are compared with what truly happened. The
/// truth is counted from the events, not from the app's rules, so a wrong
/// saved can't hide as markets.
struct HouseholdTests {
    /// The simulator agrees with itself: every day's money moved between
    /// accounts and in from outside adds up to what its events count as.
    @Test(arguments: HouseholdSeeds.all)
    func theSimulatorAddsUp(seed: UInt64) {
        let household = HouseholdSimulator.household(seed: seed)
        let truth = household.truth
        #expect(truth.inconsistencies.isEmpty, "seed \(seed): \(truth.inconsistencies.prefix(5))")
        for (from, to) in zip(household.checkIns, household.checkIns.dropFirst()) {
            let totals = truth.totals(after: from, through: to)
            // Exact but for amounts converted from dollars, which carry 38 digits.
            #expect(abs(totals.change - (totals.saved + totals.oneOffs + totals.startedWith + totals.markets))
                < d("0.000000000000000000001"))
        }
    }

    /// Exact records: every line classified as the truth says, every
    /// transfer recorded on both sides, a check-in at every month end and no
    /// account opened during the run. Every number equals the truth, to the cent.
    @Test(arguments: HouseholdSeeds.all)
    func exactRecordsGiveTheTruth(seed: UInt64) {
        let household = HouseholdSimulator.household(seed: seed)
        let all = HouseholdComparison.exact(household)
        let mismatches = all.filter { HouseholdComparison.knownIssues[$0.label] == nil }
        #expect(mismatches.isEmpty, "seed \(seed): \(mismatches.count) mismatches, first \(mismatches.prefix(8))")
        HouseholdComparison.recordKnownIssues(all, seed: seed)
        if !mismatches.isEmpty, HouseholdSeeds.reduces, let first = mismatches.first {
            let reduced = HouseholdSeeds.reduce(household.events) { events in
                HouseholdComparison.exact(household.with(events: events)).contains { $0.label == first.label }
            }
            print("seed \(seed), \(first.label): \(reduced.count) events still fail")
            for event in reduced { print("  \(event)") }
        }
    }
}

/// One number the app gives that isn't the truth.
struct HouseholdMismatch: CustomStringConvertible {
    /// What it is, e.g. `whatMoved.saved`.
    var label: String
    var from: CalendarDate?
    var to: CalendarDate
    var app: Decimal?
    var truth: Decimal

    var description: String {
        "\(label) \(from.map { "\($0)…" } ?? "")\(to): app \(app.map { "\($0)" } ?? "none"), truth \(truth)"
    }
}

/// Compares what the app makes of a household's records with the truth.
enum HouseholdComparison {
    /// Amounts agree when they're within half a cent: amounts converted
    /// from dollars carry more decimals than cents, summed in another order.
    static let tolerance = d("0.005")

    /// Mismatches that need the owner's decision, by label, with why.
    static let knownIssues = [
        "sources.saved": "Where your money came from counts a one-off (an inheritance) as saved, while the "
            + "savings rate, what moved it and Trends' money in and out leave it out (PROGRESS.md, \"Trends\"): "
            + "which of its three parts a one-off belongs to is the owner's decision.",
    ]

    /// Records each known issue among `mismatches` as known.
    static func recordKnownIssues(_ mismatches: [HouseholdMismatch], seed: UInt64) {
        for (label, reason) in knownIssues.sorted(by: { $0.key < $1.key }) {
            let known = mismatches.filter { $0.label == label }
            guard let first = known.first else { continue }
            withKnownIssue(Comment(rawValue: reason)) {
                Issue.record("seed \(seed): \(known.count) times, first \(first)")
            }
        }
    }

    struct Checker {
        var mismatches: [HouseholdMismatch] = []
        var count = 0

        mutating func check(_ label: String, _ app: Decimal?, _ truth: Decimal, from: CalendarDate? = nil,
                            to: CalendarDate) {
            count += 1
            if let app, abs(app - truth) < HouseholdComparison.tolerance { return }
            mismatches.append(HouseholdMismatch(label: label, from: from, to: to, app: app, truth: truth))
        }
    }

    /// Every number of the exact records (``Household/library(statementValues:)``)
    /// that isn't the truth.
    static func exact(_ household: Household) -> [HouseholdMismatch] {
        let library = household.library()
        let valuator = Valuator(library: library)
        let truth = household.truth
        var checker = Checker()
        for date in household.checkIns {
            checkValues(on: date, household, valuator, truth, &checker)
        }
        for (from, to) in zip(household.checkIns, household.checkIns.dropFirst()) {
            checkPeriod(after: from, through: to, prefix: "", household, valuator, truth, &checker)
        }
        let sources = valuator.moneySources(.years, through: household.end)
        let opening = truth.netWorth(on: household.start)
        for point in sources.points where point.date > household.start {
            let totals = truth.totals(after: household.start, through: point.date)
            checker.check("sources.total", point.total, truth.netWorth(on: point.date), to: point.date)
            checker.check("sources.startedWith", point.startedWith, opening + totals.startedWith, to: point.date)
            // The known issue is the one-offs counted as saved, and only that: any other gap fails.
            let app: Decimal? = point.saved
            let oneOffsCounted = totals.oneOffs != 0
                && app.map { abs($0 - totals.saved - totals.oneOffs) < HouseholdComparison.tolerance } == true
            checker.check(oneOffsCounted ? "sources.saved" : "sources.saved, apart from the one-offs", app,
                          totals.saved, to: point.date)
            checker.check("sources.markets", point.markets, totals.markets, to: point.date)
        }
        for year in household.years {
            let from = CalendarDate.lastDay(ofYear: year - 1)
            let to = CalendarDate.lastDay(ofYear: year)
            checkPeriod(after: from, through: to, prefix: "year.", household, valuator, truth, &checker)
            let report = valuator.changeThisYear(asOf: to)
            let totals = truth.totals(after: from, through: to)
            checker.check("year.thisYear.saved", report?.total.saved, totals.saved + totals.oneOffs, from: from,
                          to: to)
            checker.check("year.overYear.saved", valuator.savingsRate(overYearEndingOn: to)?.saved, totals.saved,
                          from: from, to: to)
        }
        if ProcessInfo.processInfo.environment["HOUSEHOLD_DEBUG"] == "1" {
            print("seed \(household.seed): \(household.events.count) events, \(household.checkIns.count) check-ins, "
                + "\(checker.count) numbers, car \(household.hasCar), stock \(household.hasStock), "
                + "inheritance \(household.events.contains { if case .inheritance = $0.kind { true } else { false } })")
        }
        return checker.mismatches
    }

    /// Net worth and each account's value on a check-in.
    static func checkValues(on date: CalendarDate, _ household: Household, _ valuator: Valuator,
                            _ truth: HouseholdTruth, _ checker: inout Checker) {
        let netWorth = valuator.netWorth(on: date)
        checker.check("netWorth", netWorth.total, truth.netWorth(on: date), to: date)
        if !netWorth.isComplete {
            checker.check("netWorth.complete", nil, 0, to: date)
        }
        for account in household.accounts {
            let value = netWorth.accounts.first { $0.account == account }?.value ?? 0
            checker.check("value.\(account)", value, truth.value(of: account, on: date), to: date)
        }
    }

    /// What the app says happened after `from` through `to`: each account's
    /// change, what moved net worth, the savings rate and money in and out.
    static func checkPeriod(after from: CalendarDate, through to: CalendarDate, prefix: String,
                            _ household: Household, _ valuator: Valuator, _ truth: HouseholdTruth,
                            _ checker: inout Checker) {
        let totals = truth.totals(after: from, through: to)
        func check(_ label: String, _ app: Decimal?, _ truth: Decimal) {
            checker.check(prefix + label, app, truth, from: from, to: to)
        }
        let report = valuator.change(from: from, to: to)
        for account in household.accounts {
            let change = report.accounts.first { $0.account == account }?.change ?? .zero
            check("saved.\(account)", change.saved, truth.moved(into: account, after: from, through: to))
            check("market.\(account)", change.market, truth.markets(of: account, after: from, through: to))
            check("other.\(account)", change.other, 0)
            check("lost.\(account)", change.lost, 0)
        }

        let moved = valuator.whatMoved(report)
        check("whatMoved.change", moved.change, totals.change)
        check("whatMoved.saved", moved.saved, totals.saved)
        check("whatMoved.markets", moved.markets, totals.markets)
        check("whatMoved.oneOffs", moved.oneOffs, totals.oneOffs)
        check("whatMoved.startedWith", moved.startedWith, totals.startedWith)
        check("whatMoved.lost", moved.lost, 0)
        check("whatMoved.unexplained", moved.unexplained, 0)
        check("whatMoved.pay.moneyIn", moved.pay?.moneyIn, totals.pay)
        check("whatMoved.pay.pension", moved.pay?.pension, totals.pension)
        check("whatMoved.pay.tax", moved.pay?.tax, totals.tax)
        check("whatMoved.pay.spent", moved.pay?.spent, totals.spent)
        check("savedSplit.saved", valuator.savedSplit(of: report).saved, totals.saved)

        let rate = valuator.savingsRate(from: from.adding(days: 1), through: to)
        check("rate.income", rate?.income, totals.afterTax)
        check("rate.pension", rate?.pensionContributions, totals.pension)
        check("rate.tax", rate?.tax, totals.tax)
        check("rate.saved", rate?.saved, totals.saved)
        check("rate.spent", rate?.spent, totals.spent)
        check("rate.oneOffs", rate?.oneOffs, totals.oneOffs)
        if let rate, rate.from != from {
            check("rate.from", nil, Decimal(from.days(to: rate.from)))
        }

        for account in household.accounts where [HouseholdAccount.current, HouseholdAccount.savings,
                                                 HouseholdAccount.online].contains(account) {
            let money = valuator.moneyInOut(from: from.adding(days: 1), through: to, accounts: [account])
            let expected = truth.moneyInOut(of: account, after: from, through: to)
            // An account's first value has no money in and out.
            if valuator.valuations(for: account).first.map({ $0.date > from }) ?? true { continue }
            check("money.\(account).in", money.moneyIn, expected.moneyIn)
            check("money.\(account).out", money.moneyOut, expected.moneyOut)
            check("money.\(account).tax", money.taxes, expected.tax)
            check("money.\(account).oneOff", money.oneOffs, expected.oneOff)
        }
    }
}
