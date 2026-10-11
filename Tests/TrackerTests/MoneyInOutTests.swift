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
        // 3 × 3,400 in; 5,010.55 + 2,014.6 + 2,554.65 out.
        #expect(summary.moneyIn == d("10200"))
        #expect(summary.moneyOut == d("9579.8"))
        #expect(summary.net == d("620.2"))
        #expect(summary.months == ["2026-07", "2026-08", "2026-09"])
        // The values cover 2026-06-30 to 2026-09-30: 9,579.8 × 365 / 92 days.
        #expect(summary.moneyOutPerYear == d("38006.82"))
        #expect(summary.isComplete)
    }

    @Test func countsOnlyTheDaysAskedFor() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let august = valuator.moneyInOut(from: "2026-08-01", through: "2026-08-31")
        #expect(august.moneyOut == d("2014.6"))
        #expect(august.months == ["2026-08"])
        // 2,014.6 × 365 / 31 days.
        #expect(august.moneyOutPerYear == d("23720.29"))
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
        library.months["2026-09"]?.valuations[september].moneyOut = d("4569.25")
        let summary = Valuator(library: library).moneyInOut(overYearEndingOn: "2026-09-30")
        #expect(summary.moneyOut == d("9579.8"))
        #expect(summary.months == ["2026-07", "2026-09"])
        // The same 92 days as without the skip, not two months' worth of values.
        #expect(summary.moneyOutPerYear == d("38006.82"))
    }

    @Test func scalesEachAccountByItsOwnDays() throws {
        var library = try Fixtures.exampleLibrary()
        let deposit = try #require(library.months["2026-09"]?.valuations.firstIndex { $0.account == "conto-deposito" })
        library.months["2026-09"]?.valuations[deposit].moneyIn = 0
        library.months["2026-09"]?.valuations[deposit].moneyOut = 300
        let summary = Valuator(library: library).moneyInOut(overYearEndingOn: "2026-09-30")
        #expect(summary.moneyOut == d("9879.8"))
        // 9,579.8 × 365 / 92 for the current account, plus 300 × 365 / 30
        // (2026-08-31 to 2026-09-30) for the savings account.
        #expect(summary.moneyOutPerYear == d("41656.82"))
    }

    @Test func convertsToTheBaseCurrencyOrSaysWhatItCouldNot() throws {
        var library = try Fixtures.exampleLibrary()
        library.accounts["usd-savings"] = Account(id: "usd-savings", name: "USD savings", kind: .savings,
                                                  currency: .usd, opened: "2026-07-01")
        library.upsert(Valuation(account: "usd-savings", date: "2026-07-31", balance: 2000))
        var august = Valuation(account: "usd-savings", date: "2026-08-31", balance: 2567)
        august.moneyIn = 1134
        august.moneyOut = 567
        library.upsert(august)

        // At 2026-08-31's 1.134 dollars to the euro.
        let summary = Valuator(library: library).moneyInOut(from: "2026-08-01", through: "2026-08-31",
                                                            accounts: ["usd-savings"])
        #expect(summary.currency == "EUR")
        #expect(summary.moneyIn.rounded(scale: 2) == 1000)
        #expect(summary.moneyOut.rounded(scale: 2) == 500)
        #expect(summary.isComplete)

        for month in Array(library.months.keys) { library.months[month]?.fx = [] }
        let unconverted = Valuator(library: library).moneyInOut(from: "2026-08-01", through: "2026-08-31")
        #expect(unconverted.unconverted == ["usd-savings"])
        #expect(!unconverted.isComplete)
        #expect(unconverted.moneyIn == 3400)
        #expect(unconverted.moneyOut == d("2014.6"))
    }

    @Test func editingHistoryKeepsMoneyInAndOutForAPersonToCheck() throws {
        var library = try Fixtures.exampleLibrary()
        // A balance from a statement in the middle of September.
        let inserted = library.saveValue(Valuation(account: "conto-fineco", date: "2026-09-15", balance: 4400))
        let september = ValuationKey(account: "conto-fineco", date: "2026-09-30")
        #expect(inserted.flows.moneyInOut.map(\.key) == [september])
        #expect(inserted.flows.moneyInOut.first?.moneyOut == d("2554.65"))

        var removed = try Fixtures.exampleLibrary()
        let augustKey = ValuationKey(account: "conto-fineco", date: "2026-08-31")
        // The delete confirmation says it first.
        #expect(removed.previewRemovingValue(augustKey).moneyInOut.map(\.key) == [september])
        #expect(removed.valuations(for: "conto-fineco").contains { $0.key == augustKey })
        // Nothing after the last value records money in and out.
        #expect(removed.previewRemovingValue(september).moneyInOut.isEmpty)
        let followUp = removed.removeValue(augustKey)
        #expect(followUp.moneyInOut.map(\.key) == [september])

        // A value corrected on its date leaves the next one's days alone.
        var corrected = try Fixtures.exampleLibrary()
        var august = try #require(corrected.valuations(for: "conto-fineco").first { $0.date == "2026-08-31" })
        august.balance = 4500
        let edit = corrected.saveValue(august, replacing: august.key)
        #expect(edit.flows.moneyInOut.isEmpty)
    }

    @Test func aPastCheckInListsTheValueAfterIt() throws {
        let library = try Fixtures.exampleLibrary()
        var draft = CheckInDraft(date: "2026-09-15", library: library)
        draft["conto-fineco"]?.setBalance(4400)
        var saved = library
        let followUp = draft.apply(to: &saved)
        #expect(followUp.moneyInOut.map(\.key) == [ValuationKey(account: "conto-fineco", date: "2026-09-30")])
    }

    @Test func leavesOutAnAccountsFirstValue() throws {
        var library = try Fixtures.exampleLibrary()
        let first = try #require(library.months["2025-10"]?.valuations.firstIndex { $0.account == "conto-deposito" })
        library.months["2025-10"]?.valuations[first].moneyIn = 0
        library.months["2025-10"]?.valuations[first].moneyOut = 500
        let summary = Valuator(library: library).moneyInOut(overYearEndingOn: "2026-09-30")
        #expect(summary.moneyOut == d("9579.8"))
        #expect(summary.months == ["2026-07", "2026-08", "2026-09"])
        #expect(summary.moneyOutPerYear == d("38006.82"))
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
        #expect(september.moneyOut == d("2554.65"))

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
