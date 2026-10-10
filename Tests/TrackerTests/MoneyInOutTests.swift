import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// Money in and out of the example library's current account, worked out by hand.
struct MoneyInOutTests {
    @Test func sumsTheExampleLibrarysCurrentAccount() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let summary = valuator.moneyInOut(overYearEndingOn: "2026-09-30")
        #expect(summary.from == "2025-10-01")
        #expect(summary.currency == "EUR")
        // 3 × 3,400 in; 3,160.55 + 2,865.2 + 3,704.65 out.
        #expect(summary.moneyIn == d("10200"))
        #expect(summary.moneyOut == d("9730.4"))
        #expect(summary.net == d("469.6"))
        #expect(summary.months == ["2026-07", "2026-08", "2026-09"])
        #expect(summary.moneyOutPerYear == d("38921.6"))
        #expect(summary.isComplete)
    }

    @Test func countsOnlyTheDaysAskedFor() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let august = valuator.moneyInOut(from: "2026-08-01", through: "2026-08-31")
        #expect(august.moneyOut == d("2865.2"))
        #expect(august.months == ["2026-08"])
        let june = valuator.moneyInOut(from: "2026-06-01", through: "2026-06-30")
        #expect(june.isEmpty)
        #expect(june.moneyOutPerYear == nil)
    }

    @Test func leavesOutOtherKindsHalfRecordedAndNegativeValues() throws {
        var library = try Fixtures.exampleLibrary()
        var valuations = try #require(library.months["2026-09"]?.valuations)
        for index in valuations.indices {
            switch valuations[index].account {
            case "fondo-pensione":
                valuations[index].moneyIn = 100
                valuations[index].moneyOut = 0
            case "conto-deposito":
                valuations[index].moneyIn = 50
            default:
                break
            }
        }
        library.months["2026-09"]?.valuations = valuations
        let september = Valuator(library: library).moneyInOut(from: "2026-09-01", through: "2026-09-30")
        #expect(september.moneyIn == d("3400"))
        #expect(september.moneyOut == d("3704.65"))

        library.months["2026-09"]?.valuations = valuations.map { valuation in
            var valuation = valuation
            if valuation.account == "conto-fineco" { valuation.moneyOut = -1 }
            return valuation
        }
        #expect(Valuator(library: library).moneyInOut(from: "2026-09-01", through: "2026-09-30").isEmpty)
    }

    @Test func onlyCashAndSavingsAccountsRecordIt() throws {
        #expect(AccountKind.cash.recordsMoneyInOut)
        #expect(AccountKind.savings.recordsMoneyInOut)
        #expect(!AccountKind.creditCard.recordsMoneyInOut)
        let library = try Fixtures.exampleLibrary()
        #expect(library.accounts["conto-fineco"]?.tracksMoneyInOut == true)
        #expect(library.accounts["conto-deposito"]?.tracksMoneyInOut == false)
        var pension = try #require(library.accounts["fondo-pensione"])
        pension.moneyInOut = true
        #expect(!pension.tracksMoneyInOut)
    }
}
