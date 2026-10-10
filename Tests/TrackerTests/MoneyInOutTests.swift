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
        // The values cover 2026-06-30 to 2026-09-30: 9,730.4 × 365 / 92 days.
        #expect(summary.moneyOutPerYear == d("38604.3"))
        #expect(summary.isComplete)
    }

    @Test func countsOnlyTheDaysAskedFor() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let august = valuator.moneyInOut(from: "2026-08-01", through: "2026-08-31")
        #expect(august.moneyOut == d("2865.2"))
        #expect(august.months == ["2026-08"])
        // 2,865.2 × 365 / 31 days.
        #expect(august.moneyOutPerYear == d("33735.42"))
        let june = valuator.moneyInOut(from: "2026-06-01", through: "2026-06-30")
        #expect(june.isEmpty)
        #expect(june.moneyOutPerYear == nil)
    }

    @Test func aSkippedCheckInCoversTheDaysSinceTheValueBefore() throws {
        var library = try Fixtures.exampleLibrary()
        library.months["2026-08"]?.valuations.removeAll { $0.account == "conto-fineco" }
        let september = try #require(library.months["2026-09"]?.valuations.firstIndex { $0.account == "conto-fineco" })
        // September's check-in records August's money too.
        library.months["2026-09"]?.valuations[september].moneyIn = 6800
        library.months["2026-09"]?.valuations[september].moneyOut = d("6569.85")
        let summary = Valuator(library: library).moneyInOut(overYearEndingOn: "2026-09-30")
        #expect(summary.moneyOut == d("9730.4"))
        #expect(summary.months == ["2026-07", "2026-09"])
        // The same 92 days as without the skip, not two months' worth of values.
        #expect(summary.moneyOutPerYear == d("38604.3"))
    }

    @Test func scalesEachAccountByItsOwnDays() throws {
        var library = try Fixtures.exampleLibrary()
        let deposit = try #require(library.months["2026-09"]?.valuations.firstIndex { $0.account == "conto-deposito" })
        library.months["2026-09"]?.valuations[deposit].moneyIn = 500
        library.months["2026-09"]?.valuations[deposit].moneyOut = 300
        let summary = Valuator(library: library).moneyInOut(overYearEndingOn: "2026-09-30")
        #expect(summary.moneyOut == d("10030.4"))
        // 9,730.4 × 365 / 92 for the current account, plus 300 × 365 / 30
        // (2026-08-31 to 2026-09-30) for the savings account.
        #expect(summary.moneyOutPerYear == d("42254.3"))
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
