import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// The savings rate of the example library, whose current account records
/// money in and out from July to September 2026 and whose pension fund is
/// paid 1,325 a quarter, worked out by hand.
struct SavingsRateTests {
    @Test func countsWhatWasPaidIntoPensionsOnBothSides() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let savings = try #require(valuator.savingsRate(overYearEndingOn: "2026-09-30"))
        // The current account's values cover 2026-06-30 to 2026-09-30.
        #expect(savings.from == "2026-06-30")
        #expect(savings.through == "2026-09-30")
        #expect(savings.moneyInOut.moneyIn == d("10200"))
        #expect(savings.moneyInOut.moneyOut == d("9579.8"))
        // The pension fund's 1,325 on 2026-09-30; the TFR has no value in those days.
        #expect(savings.pensionContributions == d("1325"))
        #expect(savings.plannedContributionAccounts.isEmpty)
        #expect(savings.income == d("11525"))
        #expect(savings.saved == d("1945.2"))
        // 1,945.2 / 11,525.
        #expect(savings.rate?.rounded(scale: 4) == d("0.1688"))
    }

    @Test func countsPensionsOnlyOverTheDaysMoneyInAndOutCover() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let august = try #require(valuator.savingsRate(from: "2026-08-01", through: "2026-08-31"))
        // August's value is measured from July's.
        #expect(august.from == "2026-07-31")
        #expect(august.pensionContributions == 0)
        // (3,400 − 2,014.6) / 3,400.
        #expect(august.rate?.rounded(scale: 4) == d("0.4075"))
    }

    /// The savings account records money in and out on 2026-09-30 for the
    /// days since 2025-10-31, with no value between. The pensions are still
    /// counted over the current account's days, which the pay came into.
    @Test func countsPensionsOverTheDaysThePayCovers() throws {
        var library = try Fixtures.exampleLibrary()
        for month in Array(library.months.keys) where month > "2025-10" && month < "2026-09" {
            library.months[month]?.valuations.removeAll { $0.account == "conto-deposito" }
        }
        let deposit = try #require(library.months["2026-09"]?.valuations.firstIndex { $0.account == "conto-deposito" })
        library.months["2026-09"]?.valuations[deposit].moneyIn = 50
        library.months["2026-09"]?.valuations[deposit].moneyOut = 0
        let valuator = Valuator(library: library)
        #expect(valuator.moneyInOut(overYearEndingOn: "2026-09-30").measuredFrom == "2025-10-31")
        let savings = try #require(valuator.savingsRate(overYearEndingOn: "2026-09-30"))
        #expect(savings.from == "2026-06-30")
        #expect(savings.moneyInOut.moneyIn == d("10250"))
        #expect(savings.pensionContributions == d("1325"))
    }

    @Test func takesThePlansContributionsWhenACheckInLeftThemEmpty() throws {
        var library = try Fixtures.exampleLibrary()
        let pension = try #require(library.months["2026-09"]?.valuations.firstIndex { $0.account == "fondo-pensione" })
        library.months["2026-09"]?.valuations[pension].flow = nil
        let savings = try #require(Valuator(library: library).savingsRate(overYearEndingOn: "2026-09-30"))
        // The base plan's 5,000 a year for 92 of 2026's 365 days.
        #expect(savings.pensionContributions.rounded(scale: 2) == d("1260.27"))
        #expect(savings.plannedContributionAccounts == ["fondo-pensione"])
    }

    @Test func moneyTakenOutOfAPensionIsNotIncome() throws {
        var library = try Fixtures.exampleLibrary()
        let pension = try #require(library.months["2026-09"]?.valuations.firstIndex { $0.account == "fondo-pensione" })
        library.months["2026-09"]?.valuations[pension].flow = -500
        let savings = try #require(Valuator(library: library).savingsRate(overYearEndingOn: "2026-09-30"))
        #expect(savings.pensionContributions == 0)
        #expect(savings.income == d("10200"))
        #expect(savings.saved == d("620.2"))
    }

    @Test func needsMoneyInAndOutAndSomethingComingIn() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        #expect(valuator.savingsRate(from: "2025-01-01", through: "2025-12-31") == nil)

        let nothingIn = SavingsRate(
            moneyInOut: MoneyInOutSummary(from: "2026-01-01", through: "2026-12-31", currency: .eur, moneyOut: 800,
                                          months: ["2026-03"], measuredFrom: "2026-02-28"),
            from: "2026-02-28", through: "2026-12-31")
        #expect(nothingIn.saved == -800)
        #expect(nothingIn.rate == nil)
    }
}
