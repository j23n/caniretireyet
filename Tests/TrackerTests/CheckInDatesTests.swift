import Model
import Testing
import Tracker

struct CheckInDatesTests {
    @Test func aMonthsFirstWeekSuggestsTheMonthEndBefore() {
        #expect(CheckInDates.suggested(today: "2026-10-03") == "2026-09-30")
        #expect(CheckInDates.suggested(today: "2026-10-03", lastCheckIn: "2026-08-31") == "2026-09-30")
        #expect(CheckInDates.suggested(today: "2026-01-02") == "2025-12-31")
    }

    @Test func otherwiseItSuggestsToday() {
        #expect(CheckInDates.suggested(today: "2026-10-03", lastCheckIn: "2026-09-30") == "2026-10-03")
        #expect(CheckInDates.suggested(today: "2026-10-15") == "2026-10-15")
    }

    /// The check-ins the check-in list shows are the days with a value of
    /// a cash or savings account or a tax pot; a value of another account
    /// alone, or of a trades account, isn't one.
    @Test func moneyCheckInsAreTheDaysWithAValueOfAnAccountWithMonths() {
        var library = Library(settings: LibrarySettings(baseCurrency: .eur))
        let accounts = [
            Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2026-01-01"),
            Account(id: "fund", name: "Fund", kind: .pensionFund, currency: .eur, opened: "2026-01-01"),
            Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2026-01-01",
                    valuation: .trades),
        ]
        for account in accounts { library.accounts[account.id] = account }
        library.upsert(Valuation(account: "bank", date: "2026-08-31", balance: 10000))
        library.upsert(Valuation(account: "fund", date: "2026-08-31", balance: 5000))
        library.upsert(Valuation(account: "fund", date: "2026-09-15", balance: 5100))
        library.upsert(Valuation(account: "broker", date: "2026-09-20", cash: 0))
        library.upsert(Valuation(account: "bank", date: "2026-09-30", balance: 9000))
        let valuator = Valuator(library: library)
        #expect(valuator.checkInDates() == ["2026-08-31", "2026-09-15", "2026-09-20", "2026-09-30"])
        #expect(valuator.moneyCheckInDates() == ["2026-08-31", "2026-09-30"])
        #expect(valuator.moneyCheckInDates(through: "2026-09-29") == ["2026-08-31"])
        #expect(library.moneyCheckInDates == valuator.moneyCheckInDates())
        #expect(library.moneyMonths().map(\.through) == ["2026-09-30", "2026-08-31"])
    }
}
