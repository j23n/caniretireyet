import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// A check-in's accounts by what each needs (docs/UI.md, "Check-in"), on
/// a made-up library checked in at the end of September: a current
/// account, a tax pot, a broker that records trades, a pension fund and a
/// car whose values are typed, and a fund valued from its files.
struct CheckInGroupsTests {
    static func library() -> Library {
        var library = Library(
            settings: LibrarySettings(baseCurrency: .eur),
            accounts: [
                Account(id: "conto", name: "Conto", kind: .cash, currency: .eur, opened: "2020-01-01"),
                Account(id: "pot", name: "Tasse", kind: .taxPot, currency: .eur, opened: "2020-01-01"),
                Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2020-01-01",
                        valuation: .trades),
                Account(id: "fondo", name: "Fondo", kind: .pensionFund, currency: .eur, opened: "2020-01-01",
                        values: .typed),
                Account(id: "car", name: "Car", kind: .belongings, currency: .eur, opened: "2020-01-01",
                        depreciation: d("0.15"), values: .typed),
                Account(id: "fund", name: "Fund", kind: .pensionFund, currency: .eur, opened: "2020-01-01"),
                Account(id: "old", name: "Old", kind: .cash, currency: .eur, opened: "2020-01-01",
                        closed: "2025-12-31"),
            ])
        for (account, balance) in [("conto", 5000), ("pot", 2500), ("fondo", 24300), ("fund", 1000)]
            as [(AccountID, Decimal)] {
            library.upsert(Valuation(account: account, date: "2026-09-30", balance: balance))
        }
        library.upsert(Valuation(account: "car", date: "2025-10-31", balance: 20000))
        library.upsert(Valuation(account: "broker", date: "2026-09-30", cash: 1000))
        return library
    }

    static func october(_ library: Library) -> CheckInGroups {
        Valuator(library: library).checkInGroups(on: "2026-10-31", in: library)
    }

    @Test func accountsGoToTheirGroups() {
        let groups = Self.october(Self.library())
        #expect(groups.from == "2026-09-30")
        // By name.
        #expect(groups.money.map(\.account) == ["conto", "pot"])
        #expect(groups.investments.map(\.account) == ["broker"])
        #expect(Set(groups.typed.map(\.account)) == ["fondo", "car"])
        #expect(groups.others == ["fund"])
        #expect(groups.count == 5)
    }

    @Test func aMonthNotDoneCountsAsToDo() {
        var library = Self.library()
        let groups = Self.october(library)
        // The car's estimate is kept; nothing else is done yet.
        #expect(groups.doneCount == 1)

        library.upsert(Valuation(account: "fondo", date: "2026-10-31", balance: 24650))
        let fondo = Self.october(library).typed.first { $0.account == "fondo" }
        #expect(fondo?.isUpdated == true)
        #expect(fondo?.isDone == true)
        #expect(Self.october(library).doneCount == 2)
    }

    /// The car lost 15% in the year since its last value: its estimate is
    /// 17,000, and the 3,000 it lost is lost value.
    @Test func aCarIsEstimatedFromItsDepreciation() throws {
        let car = try #require(Self.october(Self.library()).typed.first { $0.account == "car" })
        #expect(car.last?.date == "2025-10-31")
        #expect(car.estimate == 17000)
        #expect(car.lost == 3000)
        #expect(!car.isUpdated)
        #expect(car.isDone)
    }

    @Test func aValueOnTheDateNeedsNoEstimate() throws {
        var library = Self.library()
        library.upsert(Valuation(account: "car", date: "2026-10-31", balance: 16500))
        let car = try #require(Self.october(library).typed.first { $0.account == "car" })
        #expect(car.estimate == nil)
        #expect(car.lost == nil)
        #expect(car.isUpdated)
    }

    @Test func theMoneyMonthStartsAtTheValueBefore() {
        var library = Self.library()
        library.upsert(Valuation(account: "conto", date: "2026-10-31", balance: 5200))
        let month = library.moneyMonth(through: "2026-10-31")
        #expect(month.from == "2026-09-30")
        #expect(month.isCheckedIn)
        #expect(!library.moneyMonth(through: "2026-11-30").isCheckedIn)
        #expect(library.moneyMonth(through: "2026-11-30").from == "2026-10-31")
    }
}
