import Foundation
@testable import Importer
import Model
import Testing
import TestSupport
import Tracker

/// A simulated household's bank statements imported the way a person
/// would (`StatementBatch`, IMPORT.md, "Several statements at once"): a
/// year's file for each of the current and savings accounts, into a
/// library with every other record (`Household.library(statementValues:)`).
struct HouseholdImportTests {
    /// 20 seeds by default: an import takes about twenty times as long as
    /// the tracker's tests of a seed.
    static let seeds = HouseholdSeeds.all(byDefault: 20)

    /// The library after importing the household's statements: with every
    /// line classified as the truth says when `classified`, else as the
    /// import guesses. And the lines the import asked about, and how many of
    /// the truth's lines it didn't read as written.
    static func imported(_ household: Household, classified: Bool)
        -> (library: Library, asked: [StatementLine], unread: Int) {
        let base = household.library(statementValues: false)
        let today = household.end.adding(days: 40)
        let truth = household.truth
        // Each file read as a statement of its account, as a person picks it.
        var sessions: [(name: String, session: ImportSession)] = []
        var lines: [[HouseholdLine]] = []
        for account in household.statementAccounts {
            for year in household.years {
                let csv = household.statementCSV(of: account, year: year, truth: truth)
                guard !csv.isEmpty, var session = try? ImportSession(data: Data(csv.utf8)) else { continue }
                session.proposeMapping(layout: .statement)
                session.profile.constants.account = account
                sessions.append((name: "\(account)-\(year).csv", session: session))
                lines.append(household.statementLines(of: account, year: year, truth: truth))
            }
        }
        var batch = StatementBatch(sessions: sessions, library: base, today: today)
        var unread = 0
        if classified {
            batch.editSessions(library: base, today: today) { id, session in
                var waiting = lines[id]
                defer { unread += waiting.count }
                for line in session.preview(against: base, today: today).statementLines {
                    guard let index = waiting.firstIndex(where: {
                        $0.date == line.date && $0.amount == line.amount && $0.text == line.text
                    }) else { continue }
                    let truth = waiting.remove(at: index)
                    if truth.statementClass == .transfer, let other = truth.otherAccount {
                        session.setStatementAsset(.moved(other), forRow: line.row)
                    } else {
                        session.setStatementClass(truth.statementClass, forRow: line.row)
                    }
                }
            }
        }
        let previews = batch.previews(against: base, today: today)
        let result = batch.apply(previews.map(\.preview), to: base, remembering: false, today: today)
        let asked = previews.flatMap { $0.preview.statementLines.filter(\.needsAnswer) }
        return (result.result.library, asked, unread)
    }

    /// Every statement line classified as the truth says: the import
    /// records exactly the values a careful person's records have
    /// (`Household.library()`), and adds no trade.
    @Test(arguments: seeds)
    func classifiedStatementsGiveTheExactRecords(seed: UInt64) {
        let household = HouseholdSimulator.household(seed: seed)
        let exact = household.library()
        let (imported, _, unread) = Self.imported(household, classified: true)
        #expect(unread == 0, "seed \(seed): \(unread) lines not read as written")
        var differences: [String] = []
        for account in household.statementAccounts {
            let expected = exact.valuations(for: account)
            let found = imported.valuations(for: account)
            if expected.map(\.date) != found.map(\.date) {
                differences.append("\(account): values on \(found.map(\.date)), not \(expected.map(\.date))")
                continue
            }
            for (want, got) in zip(expected, found) {
                let fields: [(String, Decimal?, Decimal?)] = [
                    ("balance", want.balance, got.balance), ("moneyIn", want.moneyIn, got.moneyIn),
                    ("moneyOut", want.moneyOut, got.moneyOut), ("oneOff", want.oneOff, got.oneOff),
                    ("tax", want.tax, got.tax), ("interest", want.interest, got.interest),
                ]
                for (name, a, b) in fields where (a ?? 0) != (b ?? 0) {
                    differences.append("\(account) \(want.date) \(name): \(b.map { "\($0)" } ?? "none"), "
                        + "not \(a.map { "\($0)" } ?? "none")")
                }
            }
        }
        if Set(exact.allTrades.map(\.key)) != Set(imported.allTrades.map(\.key)) {
            differences.append("trades: \(imported.allTrades.count), not \(exact.allTrades.count)")
        }
        #expect(differences.isEmpty, "seed \(seed): \(differences.count), first \(differences.prefix(6))")
    }
}

extension HouseholdImportTests {
    /// The statements imported without a class chosen: the import guesses
    /// each line's (IMPORT.md, "Classes"). The promise: each year's came in,
    /// tax, spent, saved, what the pay saved, one-offs and money out are off
    /// by no more than the lines the import asks about add up to, since a
    /// line it's sure of is right.
    /// What a wrong class costs is measured as a share of what came in.
    @Test func unclassifiedStatementsAreWrongOnlyWhereTheImportAsks() async {
        let measured = await withTaskGroup(of: (HouseholdErrors, [String]).self) { group in
            for seed in Self.seeds {
                group.addTask {
                    let household = HouseholdSimulator.household(seed: seed)
                    let (library, asked, _) = Self.imported(household, classified: false)
                    let valuator = Valuator(library: library)
                    let truth = household.truth
                    var errors = HouseholdErrors()
                    var broken: [String] = []
                    for year in household.years {
                        let from = CalendarDate.lastDay(ofYear: year - 1)
                        let to = CalendarDate.lastDay(ofYear: year)
                        let totals = truth.totals(after: from, through: to)
                        let rate = valuator.savingsRate(from: from.adding(days: 1), through: to)
                        var moneyOut: Decimal = 0
                        for account in household.statementAccounts {
                            moneyOut += truth.moneyInOut(of: account, after: from, through: to).moneyOut
                        }
                        let numbers: [(String, Decimal?, Decimal)] = [
                            ("came in", rate?.income, totals.afterTax), ("tax", rate?.tax, totals.tax),
                            ("spent", rate?.spent, totals.spent), ("saved", rate?.saved, totals.saved),
                            ("saved from pay", rate?.savedFromPay, totals.savedFromPay),
                            ("one-offs", rate?.oneOffs, totals.oneOffs),
                            ("money out", rate?.moneyInOut.moneyOut, moneyOut),
                        ]
                        let bound = asked.filter { $0.date > from && $0.date <= to }
                            .reduce(Decimal(0)) { $0 + abs($1.amount) }
                        for (label, app, expected) in numbers {
                            errors.add("year \(label)", seed: seed, app: app, truth: expected, scale: totals.afterTax)
                            let error = (app ?? 0) - expected
                            if abs(error) >= d("0.005") + bound {
                                broken.append("seed \(seed): \(year) \(label) off by \(error), asked about \(bound)")
                            }
                        }
                        errors.add("year asked about", seed: seed, app: bound, truth: 0, scale: totals.afterTax)
                    }
                    return (errors, broken)
                }
            }
            var all = (HouseholdErrors(), [String]())
            for await (errors, broken) in group {
                all.0.append(contentsOf: errors)
                all.1 += broken
            }
            return all
        }
        print("Unclassified statements:\n\(measured.0.summary)")
        #expect(measured.1.isEmpty, "\(measured.1.count) broken: \(measured.1.prefix(5))")
    }
}
