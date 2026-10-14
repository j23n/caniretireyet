import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// `Library.problems()`: the checks across the library's files.
struct LibraryProblemsTests {
    private let september = "history/2026/2026-09.json"

    @Test func theExampleLibraryHasNoProblems() throws {
        #expect(try Fixtures.exampleLibrary().problems() == [])
    }

    @Test func moneyInOutThatIsNotCountedIsAWarning() throws {
        var library = try Fixtures.exampleLibrary()
        library.changeValuation(of: "fondo-pensione") {
            $0.moneyIn = 100
            $0.moneyOut = 0
            $0.tax = 10
        }
        library.changeValuation(of: "conto-deposito") {
            $0.moneyIn = 500
            $0.moneyOut = nil
            $0.oneOff = 100
        }
        library.changeValuation(of: "conto-fineco") {
            $0.moneyOut = -1
            $0.oneOff = -5
        }

        let problems = library.problems()
        #expect(problems.allSatisfy { $0.path == september && $0.severity == .warning })
        #expect(problems.count == 6)
        #expect(Set(problems.map(\.message)) == [
            "The valuation of fondo-pensione on 2026-09-30 records money in or out, but only cash and savings "
                + "accounts and tax pots do; it isn't counted.",
            "The valuation of fondo-pensione on 2026-09-30 records tax, but only cash and savings accounts do; "
                + "it isn't counted.",
            "The valuation of conto-deposito on 2026-09-30 records only money in; record both, or neither; "
                + "it isn't counted.",
            "The valuation of conto-deposito on 2026-09-30 records a one-off without both money in and out; "
                + "it isn't counted.",
            "The valuation of conto-fineco on 2026-09-30 has a negative one-off, an amount without a sign; "
                + "it isn't counted.",
            "The valuation of conto-fineco on 2026-09-30 has negative money in or out; both are amounts "
                + "without a sign; it isn't counted.",
        ])
    }

    @Test func referencesAndTradesAreCheckedInTheFileOfTheRecord() throws {
        var library = try Fixtures.exampleLibrary()
        library.instruments["btc"] = nil
        library.upsert(Trade(account: "conto-fineco", date: "2026-09-15", id: "dep12345", type: .deposit, amount: 5))

        let problems = library.problems()
        // The twelve month files with btc's prices or positions, and an import profile.
        #expect(problems.filter { $0.message.contains("instruments that don't exist: btc") }.count == 13)
        #expect(problems.contains { $0.path == september && $0.message.hasPrefix("conto-fineco: ") })
        #expect(problems.allSatisfy { $0.severity == .warning })
    }
}

extension Library {
    /// Changes the example library's valuation of `account` on 2026-09-30.
    fileprivate mutating func changeValuation(of account: AccountID, _ change: (inout Valuation) -> Void) {
        guard var valuation = months["2026-09"]?.valuations.first(where: { $0.account == account }) else {
            Issue.record("No valuation of \(account) in 2026-09")
            return
        }
        change(&valuation)
        upsert(valuation)
    }
}
