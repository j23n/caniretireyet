import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// A simulated household whose records leave the app to guess, one option
/// at a time (`HouseholdOptions`): each number the guess affects is
/// measured against the truth over the seeds, a summary is printed, and a
/// test fails only above its threshold, a written promise of how wrong the
/// guess may be.
struct HouseholdGuessTests {
    /// What one seed measured: its errors and the promises it broke.
    struct Measured: Sendable {
        var errors = HouseholdErrors()
        var broken: [String] = []
        /// Broken promises that need the owner's decision (``knownIssue``).
        var known: [String] = []
    }

    /// Each seed's household with `options`, measured by `body`, in parallel.
    static func measure(_ options: HouseholdOptions,
                        _ body: @Sendable @escaping (Household, Valuator, HouseholdTruth, inout Measured) -> Void)
        async -> Measured {
        await withTaskGroup(of: Measured.self) { group in
            for seed in HouseholdSeeds.all {
                group.addTask {
                    let household = HouseholdSimulator.household(seed: seed, options: options)
                    var measured = Measured()
                    body(household, Valuator(library: household.library()), household.truth, &measured)
                    return measured
                }
            }
            var all = Measured()
            for await measured in group {
                all.errors.append(contentsOf: measured.errors)
                all.broken += measured.broken
                all.known += measured.known
            }
            return all
        }
    }

    /// Fails on every broken promise, and records those that need the
    /// owner's decision as a known issue with `reason`.
    static func report(_ title: String, _ measured: Measured, knownIssue reason: String? = nil) {
        print("\(title):\n\(measured.errors.summary)")
        #expect(measured.broken.isEmpty, "\(measured.broken.count) broken: \(measured.broken.prefix(5))")
        if let reason, !measured.known.isEmpty {
            withKnownIssue(Comment(rawValue: reason)) {
                Issue.record("\(measured.known.count) seeds: \(measured.known.prefix(5))")
            }
        }
    }

    /// The days of a calendar year: after the 31 December before it through its own.
    static func days(of year: Int) -> (from: CalendarDate, to: CalendarDate) {
        (CalendarDate.lastDay(ofYear: year - 1), CalendarDate.lastDay(ofYear: year))
    }

    /// The year's came in, tax, spent and saved by the savings rate, as
    /// shares of what truly came in after tax that year.
    static func yearErrors(_ year: Int, _ household: Household, _ valuator: Valuator, _ truth: HouseholdTruth,
                           into errors: inout HouseholdErrors) -> [String: Decimal] {
        let (from, to) = days(of: year)
        let totals = truth.totals(after: from, through: to)
        let rate = valuator.savingsRate(from: from.adding(days: 1), through: to)
        let numbers: [(String, Decimal?, Decimal)] = [
            ("came in", rate?.income, totals.afterTax), ("tax", rate?.tax, totals.tax),
            ("spent", rate?.spent, totals.spent), ("saved", rate?.saved, totals.saved),
        ]
        var found: [String: Decimal] = [:]
        for (label, app, expected) in numbers {
            errors.add("year \(label)", seed: household.seed, app: app, truth: expected, scale: totals.afterTax)
            found[label] = (app ?? 0) - expected
        }
        return found
    }

    /// A month end without a check-in: the month after it covers both
    /// months. Every number over the two months together is the truth, and
    /// so is every year that doesn't end on it. A year that ends on it
    /// shifts that month's money into the next year, so each of their
    /// numbers is off by at most the month's money: its came in, what was
    /// spent and what was deposited at the broker, added up. The two years
    /// together are the truth.
    @Test func aSkippedCheckIn() async {
        let measured = await Self.measure(HouseholdOptions(skippedCheckIn: true)) { household, valuator, truth, out in
            guard let skipped = household.records.skippedCheckIns.first,
                  let after = household.checkIns.first(where: { $0 > skipped }),
                  let before = household.checkIns.last(where: { $0 < skipped })
            else { return }
            let seed = household.seed
            var checker = HouseholdComparison.Checker()
            HouseholdComparison.checkPeriod(after: before, through: after, prefix: "two months.", household,
                                            valuator, truth, &checker)
            let series = valuator.moneyInOutSeries(.months, through: household.end).periods
            // A series starts at its first month with money counted, so a skipped first month has none.
            if series.first(where: { $0.through == skipped }).map(\.isEmpty) == false {
                out.broken.append("seed \(seed): the skipped month \(skipped) has money in and out")
            }
            if series.first(where: { $0.through == after })?.coversMore(.months) != true {
                out.broken.append("seed \(seed): the month after the skipped one doesn't say it covers more")
            }
            let month = truth.totals(after: before, through: skipped)
            let deposits = truth.moved(into: HouseholdAccount.broker, after: before, through: skipped)
            let bound = abs(month.afterTax) + abs(month.spent) + abs(deposits)
            var shifted: [String: Decimal] = [:]
            for year in household.years {
                let errors = Self.yearErrors(year, household, valuator, truth, into: &out.errors)
                let touched = skipped.month == 12 && (year == skipped.year || year == skipped.year + 1)
                if touched {
                    for (label, error) in errors where abs(error) > bound {
                        out.broken.append("seed \(seed): \(year) \(label) off by \(error), more than \(bound)")
                    }
                    shifted.merge(errors, uniquingKeysWith: +)
                } else {
                    let (from, to) = Self.days(of: year)
                    HouseholdComparison.checkPeriod(after: from, through: to, prefix: "year.", household,
                                                    valuator, truth, &checker)
                }
            }
            out.broken += checker.mismatches.map { "seed \(seed): \($0)" }
            // The two years around a skipped 31 December, added up, are the truth: the
            // first year's pay ends at the check-in before it, where the next year's starts.
            for (label, error) in shifted.sorted(by: { $0.key < $1.key })
            where abs(error) >= HouseholdComparison.tolerance {
                out.broken.append("seed \(seed): \(skipped.year) and \(skipped.year + 1) \(label) off by \(error)")
            }
        }
        Self.report("A skipped check-in", measured)
    }

    /// Pension values typed without what was paid in: what the employer
    /// paid in those months is neither came in nor saved, exactly, and what
    /// was spent doesn't change. Over a year, the fund's change less what
    /// its other values say was paid in is unexplained, its return in the
    /// months with a saved amount too: the year's change of a balance with
    /// a saved amount missing is other (PROGRESS.md, "Data this needs from
    /// day one").
    @Test func aPensionValueWithoutWhatWasPaidIn() async {
        let measured = await Self.measure(HouseholdOptions(pensionWithoutSaved: true)) {
            household, valuator, truth, out in
            let seed = household.seed
            let pension = HouseholdAccount.pension
            for year in household.years {
                let (from, to) = Self.days(of: year)
                let errors = Self.yearErrors(year, household, valuator, truth, into: &out.errors)
                var missing: Decimal = 0
                for (start, end) in zip(household.checkIns, household.checkIns.dropFirst())
                where start >= from && end <= to && household.records.pensionWithoutSaved.contains(end) {
                    missing += truth.totals(after: start, through: end).pension
                }
                let expected: [String: Decimal] = ["came in": -missing, "saved": -missing, "spent": 0, "tax": 0]
                for (label, error) in errors where abs(error - (expected[label] ?? 0)) >= HouseholdComparison.tolerance {
                    out.broken.append("seed \(seed): \(year) \(label) off by \(error), not \(expected[label] ?? 0)")
                }
                let totals = truth.totals(after: from, through: to)
                let change = truth.value(of: pension, on: to) - truth.value(of: pension, on: from)
                let fundReturn = truth.markets(of: pension, after: from, through: to)
                let moved = valuator.whatMoved(valuator.change(from: from, to: to))
                out.errors.add("year markets", seed: seed, app: moved.markets, truth: totals.markets,
                               scale: totals.afterTax)
                let unexplained = household.records.pensionWithoutSaved.contains { $0 > from && $0 <= to }
                    ? change - (totals.pension - missing) : 0
                if abs(moved.unexplained - unexplained) >= HouseholdComparison.tolerance
                    || abs(moved.markets - (totals.markets - (unexplained == 0 ? 0 : fundReturn)))
                    >= HouseholdComparison.tolerance {
                    out.broken.append("seed \(seed): \(year) unexplained \(moved.unexplained), not \(unexplained)")
                }
            }
        }
        Self.report("A pension value without what was paid in", measured)
    }

    /// A second savings account opened during the run, holding money from
    /// outside, then a transfer from the current account: what it held when
    /// its records start is a guess (PROGRESS.md, "Saved"). The promise:
    /// its started with, and so what was saved and spent, are within 1% of
    /// what came in that year, a month's spending on a card or so; what
    /// came in and the tax are exact. In a month the car is sold, the guess
    /// counts what the car was worth as money moved out of it, not the
    /// price it brought, so what it brought beyond its worth is started
    /// with too, and what it brought short of it saved: they're off by that
    /// much more, that way only.
    @Test func anAccountOpenedWithMoneyFromOutside() async {
        let measured = await Self.measure(HouseholdOptions(newAccount: true)) { household, valuator, truth, out in
            guard let opened = household.onlineOpened else { return }
            let seed = household.seed
            let (from, to) = Self.days(of: opened.year)
            let year = truth.totals(after: from, through: to)
            let errors = Self.yearErrors(opened.year, household, valuator, truth, into: &out.errors)
            for label in ["came in", "tax"] where abs(errors[label] ?? 0) >= HouseholdComparison.tolerance {
                out.broken.append("seed \(seed): \(opened.year) \(label) off by \(errors[label] ?? 0)")
            }
            let month = (opened.startOfMonth.adding(days: -1), opened.endOfMonth)
            let moved = valuator.whatMoved(valuator.change(from: month.0, to: month.1))
            let truthMonth = truth.totals(after: month.0, through: month.1)
            out.errors.add("its month's started with", seed: seed, app: moved.startedWith,
                           truth: truthMonth.startedWith, scale: year.afterTax)
            out.errors.add("its month's saved", seed: seed, app: moved.saved, truth: truthMonth.saved,
                           scale: year.afterTax)
            if abs(moved.unexplained) >= HouseholdComparison.tolerance {
                out.broken.append("seed \(seed): unexplained \(moved.unexplained)")
            }
            let bound = year.afterTax / 100
            let sale = household.events.filter { $0.date > month.0 && $0.date <= month.1 }
                .compactMap { event -> Decimal? in
                    guard case .sellCar(let price) = event.kind else { return nil }
                    return price
                }.first
            let gap = sale.map { $0 - truth.value(of: HouseholdAccount.car, on: month.0) } ?? 0
            let error = moved.startedWith - truthMonth.startedWith
            let savedError = moved.saved - truthMonth.saved
            if error > max(gap, 0) + bound || error < min(gap, 0) - bound
                || savedError > max(-gap, 0) + bound || savedError < min(-gap, 0) - bound {
                out.broken.append("seed \(seed): started with off by \(error), saved by \(savedError), more than 1% "
                    + "beyond the \(gap) the car sold that month brought beyond its worth")
            }
        }
        Self.report("An account opened with money from outside", measured)
    }
}
