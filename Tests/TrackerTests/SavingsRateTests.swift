import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// The savings rate (PROGRESS.md, "Savings rate"): what was saved, worked out
/// from balances and trades, over what came in.
struct SavingsRateTests {
    /// The example library, whose current account records money in and out
    /// from July to September 2026, whose pension fund is paid 1,325 a
    /// quarter and whose mortgage repays 650 a month from the current
    /// account, worked out by hand.
    @Test func savesEveryAccountsNewMoney() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let savings = try #require(valuator.savingsRate(overYearEndingOn: "2026-09-30"))
        // The current account's values cover 2026-06-30 to 2026-09-30.
        #expect(savings.from == "2026-06-30")
        #expect(savings.through == "2026-09-30")
        #expect(savings.moneyInOut.moneyIn == d("10200"))
        // The pension fund's 1,325 on 2026-09-30; the TFR has no value in those days.
        #expect(savings.pensionContributions == d("1325"))
        #expect(savings.plannedContributionAccounts.isEmpty)
        #expect(savings.income == d("11525"))
        // The current account's −2,030.4 is the 500 to the savings account, the 200.6 to the broker and the
        // mortgage's 1,950, which come back as their new money, less what was spent.
        #expect(savings.savedByAccount["conto-fineco"] == d("-2030.4"))
        #expect(savings.savedByAccount["conto-deposito"] == 500)
        #expect(savings.savedByAccount["directa"] == d("211.45"))
        #expect(savings.savedByAccount["mutuo-casa"] == 1950)
        #expect(savings.savedByAccount["fondo-pensione"] == 1325)
        #expect(savings.saved == d("1956.05"))
        #expect(savings.spent == d("9568.95"))
        // 9,568.95 × 365 / 92 days.
        #expect(savings.spentPerYear == d("37963.77"))
        // 1,956.05 / 11,525.
        #expect(savings.rate?.rounded(scale: 4) == d("0.1697"))
        #expect(savings.isPriced)
    }

    @Test func countsOverTheDaysMoneyInCovers() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let august = try #require(valuator.savingsRate(from: "2026-08-01", through: "2026-08-31"))
        // August's value is measured from July's.
        #expect(august.from == "2026-07-31")
        #expect(august.pensionContributions == 0)
        // The current account's 534.8, the broker's deposit of 200.6 and the mortgage's 650.
        #expect(august.saved == d("1385.4"))
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
        // 1,956.05 without the 1,325 paid in, and with the 500 taken out.
        #expect(savings.saved == d("131.05"))
    }

    /// A month of made-up accounts: pay of 4,000 and a refund of 150 into the current
    /// account, which pays rent and groceries (1,800), the card's bill
    /// (1,100), 1,000 to the broker and the mortgage (500 principal, 300
    /// interest); 900 bought by card; 300 paid into the pension fund by the
    /// employer.
    let month: Library = {
        var library = Library(settings: LibrarySettings(baseCurrency: .eur))
        let accounts = [
            Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2025-12-01"),
            Account(id: "card", name: "Card", kind: .creditCard, currency: .eur, opened: "2025-12-01"),
            Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2025-12-01",
                    valuation: .trades),
            Account(id: "fondo", name: "Fondo", kind: .pensionFund, currency: .eur, opened: "2025-12-01"),
            Account(id: "mortgage", name: "Mortgage", kind: .mortgage, currency: .eur, opened: "2025-12-01"),
        ]
        for account in accounts { library.accounts[account.id] = account }
        library.upsert(Valuation(account: "bank", date: "2025-12-31", balance: 10000, flow: 10000))
        library.upsert(Valuation(account: "card", date: "2025-12-31", balance: -300, flow: -300))
        library.upsert(Valuation(account: "broker", date: "2025-12-31", cash: 0, flow: 0))
        library.upsert(Valuation(account: "fondo", date: "2025-12-31", balance: 5000))
        library.upsert(Valuation(account: "mortgage", date: "2025-12-31", balance: -100_000))
        library.upsert(Trade(account: "broker", date: "2026-01-26", id: "dep1", type: .deposit, amount: 1000))
        // Income only: the refund isn't.
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 9450, flow: -550, moneyIn: 4000,
                                 moneyOut: 4550))
        library.upsert(Valuation(account: "card", date: "2026-01-31", balance: -100, flow: 200))
        library.upsert(Valuation(account: "broker", date: "2026-01-31", cash: 1000, flow: 1000))
        library.upsert(Valuation(account: "fondo", date: "2026-01-31", balance: 5300, flow: 300))
        library.upsert(Valuation(account: "mortgage", date: "2026-01-31", balance: -99500, flow: 500))
        return library
    }()

    @Test func transfersCancelOutAndARefundLowersSpending() throws {
        let savings = try #require(Valuator(library: month).savingsRate(from: "2026-01-01", through: "2026-01-31"))
        #expect(savings.from == "2025-12-31")
        #expect(savings.income == 4300)
        // −550 + 200 + 1,000 + 300 + 500.
        #expect(savings.saved == 1450)
        // Rent and groceries, the card's purchases and the mortgage's interest, less the refund.
        #expect(savings.spent == 2850)
        #expect(savings.rate?.rounded(scale: 4) == d("0.3372"))
    }

    /// An inheritance of 20,000 into the current account is neither came in
    /// nor spent: saved, spent and the rate stay as they were.
    @Test func aOneOffIsLeftOutOfWhatWasSaved() throws {
        var library = month
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 29450, flow: 19450, moneyIn: 4000,
                                 moneyOut: 4550, oneOff: 20000))
        let savings = try #require(Valuator(library: library).savingsRate(from: "2026-01-01", through: "2026-01-31"))
        #expect(savings.oneOffs == 20000)
        #expect(savings.savedByAccount["bank"] == 19450)
        #expect(savings.saved == 1450)
        #expect(savings.spent == 2850)
        #expect(savings.rate?.rounded(scale: 4) == d("0.3372"))
        // What moved between the accounts leaves the one-off out too.
        #expect(library.months["2026-01"]?.valuations.first { $0.account == "bank" }?.moved == 0)
        // So does the Overview's Saved bar: the one-off is under Other.
        let valuator = Valuator(library: library)
        let report = valuator.change(from: "2025-12-31", to: "2026-01-31")
        let split = valuator.savedSplit(of: report)
        #expect(split.newMoney == savings.saved)
        #expect(split.other == report.total.other + 20000)
        #expect(split.start + split.market + split.newMoney + split.other == split.end)
    }

    /// A check-in fills in a new account's whole amount as its flow: only the
    /// part that left an account already tracked is saved.
    @Test func aNewAccountsFirstValueIsSavedOnlyAsFarAsItMovedFromAnother() throws {
        var library = month
        library.accounts["old-savings"] = Account(id: "old-savings", name: "Old savings", kind: .savings,
                                                  currency: .eur, opened: "2026-01-15")
        library.upsert(Valuation(account: "old-savings", date: "2026-01-31", balance: 20000, flow: 20000))
        let savings = try #require(Valuator(library: library).savingsRate(from: "2026-01-01", through: "2026-01-31"))
        // The bank's 550 drop is the only negative new money at that check-in.
        #expect(savings.savedByAccount["old-savings"] == 550)
        #expect(savings.saved == 2000)
        // The Overview's bars move what it already held from new money to other.
        let valuator = Valuator(library: library)
        let report = valuator.change(from: "2025-12-31", to: "2026-01-31")
        let split = valuator.savedSplit(of: report)
        #expect(split.newMoney == 2000)
        #expect(split.other == report.total.other + 19450)
        #expect(split.start + split.market + split.newMoney + split.other == split.end)
    }

    /// A loan you start tracking at a check-in of its own owed what it owes
    /// already: it isn't spent. One paid out into the current account at
    /// that check-in cancels out against the money it brought.
    @Test func aDebtsFirstValueIsSavedOnlyAsFarAsItMovedIntoAnother() throws {
        var library = month
        library.accounts["auto"] = Account(id: "auto", name: "Car loan", kind: .loan, currency: .eur,
                                           opened: "2026-02-10")
        library.upsert(Valuation(account: "auto", date: "2026-02-15", balance: -10000, flow: -10000))
        let tracked = Valuator(library: library).saved(after: "2025-12-31", through: "2026-02-15")
        #expect(tracked.byAccount["auto"] == 0)
        #expect(tracked.byAccount.values.reduce(Decimal(0), +) == 1450)

        library.upsert(Valuation(account: "bank", date: "2026-02-15", balance: 19450, flow: 10000, moneyIn: 0,
                                 moneyOut: 0))
        let paidOut = Valuator(library: library).saved(after: "2025-12-31", through: "2026-02-15")
        #expect(paidOut.byAccount["auto"] == -10000)
        #expect(paidOut.byAccount["bank"] == 9450)
        #expect(paidOut.byAccount.values.reduce(Decimal(0), +) == 1450)
    }

    /// A loan you start tracking at a regular check-in doesn't take that
    /// month's saving: only money moved into the current account offsets
    /// it, not the broker's deposit or the mortgage's principal.
    @Test func aDebtAddedAtARegularCheckInKeepsTheMonthsSaving() throws {
        var library = month
        library.accounts["auto"] = Account(id: "auto", name: "Car loan", kind: .loan, currency: .eur,
                                           opened: "2026-01-10")
        library.upsert(Valuation(account: "auto", date: "2026-01-31", balance: -10000, flow: -10000))
        let savings = try #require(Valuator(library: library).savingsRate(from: "2026-01-01", through: "2026-01-31"))
        #expect(savings.savedByAccount["auto"] == 0)
        #expect(savings.saved == 1450)
        #expect(savings.rate?.rounded(scale: 4) == d("0.3372"))
    }

    /// A transfer between two cash or savings accounts doesn't offset a new
    /// debt: in the example library's September, the standing order into
    /// the savings account is money moved into it, but out of the current
    /// account too.
    @Test func aTransferBetweenCashAccountsDoesNotOffsetANewDebt() throws {
        var library = try Fixtures.exampleLibrary()
        let before = try #require(Valuator(library: library).savingsRate(from: "2026-09-01", through: "2026-09-30"))
        library.accounts["auto"] = Account(id: "auto", name: "Car loan", kind: .loan, currency: .eur,
                                           opened: "2026-09-10")
        library.upsert(Valuation(account: "auto", date: "2026-09-30", balance: -10000, flow: -10000))
        let savings = try #require(Valuator(library: library).savingsRate(from: "2026-09-01", through: "2026-09-30"))
        #expect(savings.savedByAccount["auto"] == 0)
        #expect(savings.saved == before.saved)
    }

    /// Only accounts in net worth count: a current account left out of it
    /// adds nothing to what came in.
    @Test func countsOnlyAccountsInNetWorth() throws {
        var library = month
        library.accounts["side"] = Account(id: "side", name: "Side", kind: .cash, currency: .eur,
                                           opened: "2025-12-01", includeIn: IncludeIn(netWorth: false))
        library.upsert(Valuation(account: "side", date: "2025-12-31", balance: 0, flow: 0))
        library.upsert(Valuation(account: "side", date: "2026-01-31", balance: 0, flow: 0, moneyIn: 700,
                                 moneyOut: 700))
        let savings = try #require(Valuator(library: library).savingsRate(from: "2026-01-01", through: "2026-01-31"))
        #expect(savings.income == 4300)
        #expect(savings.savedByAccount["side"] == nil)
        // Trends' money in and out recorded counts the same accounts.
        let series = Valuator(library: library).moneyInOutSeries(.months, through: "2026-01-31")
        #expect(series.recorded.moneyIn == 4000)
    }

    @Test func needsMoneyInAndOutAndSomethingComingIn() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        #expect(valuator.savingsRate(from: "2025-01-01", through: "2025-12-31") == nil)

        let nothingIn = SavingsRate(
            moneyInOut: MoneyInOutSummary(from: "2026-01-01", through: "2026-12-31", currency: .eur, moneyOut: 800,
                                          months: ["2026-03"], measuredFrom: "2026-02-28"),
            from: "2026-02-28", through: "2026-12-31", savedByAccount: ["bank": -800])
        #expect(nothingIn.saved == -800)
        #expect(nothingIn.spent == 800)
        #expect(nothingIn.rate == nil)
    }
}
