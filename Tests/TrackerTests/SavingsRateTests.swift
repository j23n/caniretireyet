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
    @Test func savesWhatEveryAccountSaved() throws {
        let valuator = Valuator(library: try Fixtures.exampleLibrary())
        let savings = try #require(valuator.savingsRate(overYearEndingOn: "2026-09-30"))
        // The current account's values cover 2026-06-30 to 2026-09-30.
        #expect(savings.from == "2026-06-30")
        #expect(savings.through == "2026-09-30")
        #expect(savings.moneyInOut.moneyIn == d("10200"))
        // The pension fund's 1,325 on 2026-09-30; the TFR has no value in those days.
        #expect(savings.pensionContributions == d("1325"))
        #expect(savings.income == d("11525"))
        // The current account's −2,030.4 is the 500 to the savings account, the 200.6 to the broker and the
        // mortgage's 1,950, which come back as what they saved, less what was spent.
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

    /// A pension fund's value without what was saved into it: its change
    /// is other, never what the plan pays in.
    @Test func aPensionWithoutWhatWasSavedPaysNothingIn() throws {
        var library = try Fixtures.exampleLibrary()
        let pension = try #require(library.months["2026-09"]?.valuations.firstIndex { $0.account == "fondo-pensione" })
        library.months["2026-09"]?.valuations[pension].saved = nil
        let savings = try #require(Valuator(library: library).savingsRate(overYearEndingOn: "2026-09-30"))
        #expect(savings.pensionContributions == 0)
        #expect(savings.saved == d("631.05"))
    }

    @Test func moneyTakenOutOfAPensionIsNotIncome() throws {
        var library = try Fixtures.exampleLibrary()
        let pension = try #require(library.months["2026-09"]?.valuations.firstIndex { $0.account == "fondo-pensione" })
        library.months["2026-09"]?.valuations[pension].saved = -500
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
        library.upsert(Valuation(account: "bank", date: "2025-12-31", balance: 10000, saved: 10000))
        library.upsert(Valuation(account: "card", date: "2025-12-31", balance: -300, saved: -300))
        library.upsert(Valuation(account: "broker", date: "2025-12-31", cash: 0, saved: 0))
        library.upsert(Valuation(account: "fondo", date: "2025-12-31", balance: 5000))
        library.upsert(Valuation(account: "mortgage", date: "2025-12-31", balance: -100_000))
        library.upsert(Trade(account: "broker", date: "2026-01-26", id: "dep1", type: .deposit, amount: 1000))
        // Income only: the refund isn't.
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 9450, saved: -550, moneyIn: 4000,
                                 moneyOut: 4550))
        library.upsert(Valuation(account: "card", date: "2026-01-31", balance: -100, saved: 200))
        library.upsert(Valuation(account: "broker", date: "2026-01-31", cash: 1000, saved: 1000))
        library.upsert(Valuation(account: "fondo", date: "2026-01-31", balance: 5300, saved: 300))
        library.upsert(Valuation(account: "mortgage", date: "2026-01-31", balance: -99500, saved: 500))
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
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 29450, saved: 19450, moneyIn: 4000,
                                 moneyOut: 4550, oneOff: 20000))
        let savings = try #require(Valuator(library: library).savingsRate(from: "2026-01-01", through: "2026-01-31"))
        #expect(savings.oneOffs == 20000)
        #expect(savings.savedByAccount["bank"] == 19450)
        #expect(savings.saved == 1450)
        #expect(savings.spent == 2850)
        #expect(savings.rate?.rounded(scale: 4) == d("0.3372"))
        // What moved between the accounts leaves the one-off out too.
        let bank = library.valuations(for: "bank")
        let january = try #require(bank.firstIndex { $0.date == "2026-01-31" })
        #expect(Valuator(library: library).moved(bank[january], previous: january > 0 ? bank[january - 1] : nil) == 0)
        // So does the Overview's Saved bar: the one-off is under Other.
        let valuator = Valuator(library: library)
        let report = valuator.change(from: "2025-12-31", to: "2026-01-31")
        let split = valuator.savedSplit(of: report)
        #expect(split.saved == savings.saved)
        #expect(split.other == report.total.other + 20000)
        #expect(split.start + split.market + split.saved + split.other == split.end)
    }

    /// A car bought from the current account is saved, not spent; its loss
    /// of value is spent, and selling it cancels out.
    @Test func aCarsLossOfValueIsSpent() throws {
        var library = month
        library.accounts["car"] = Account(id: "car", name: "Car", kind: .belongings, currency: .eur,
                                          opened: "2026-01-10")
        // Bought for 20,000 from the current account in January.
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: -10550, saved: -20550, moneyIn: 4000,
                                 moneyOut: 4550))
        library.upsert(Valuation(account: "car", date: "2026-01-31", balance: 20000, saved: 20000))
        // Worth 19,000 at the end of February, a value without a saved amount.
        library.upsert(Valuation(account: "car", date: "2026-02-28", balance: 19000))
        let valuator = Valuator(library: library)
        let january = try #require(valuator.savingsRate(from: "2026-01-01", through: "2026-01-31"))
        #expect(january.saved == 1450)
        #expect(january.spent == 2850)
        let february = valuator.saved(after: "2026-01-31", through: "2026-02-28")
        #expect(february.byAccount["car"] == -1000)

        // Sold for 18,500 into the current account in March: only the 500 below its value is spent.
        library.upsert(Valuation(account: "car", date: "2026-03-31", balance: 0))
        library.upsert(Valuation(account: "bank", date: "2026-03-31", balance: 7950, saved: 18500, moneyIn: 0,
                                 moneyOut: 0))
        let sold = Valuator(library: library)
        let march = sold.saved(after: "2026-02-28", through: "2026-03-31")
        #expect(march.byAccount["car"] == -19000)
        #expect(march.byAccount["bank"] == 18500)
        #expect(march.byAccount.values.reduce(Decimal(0), +) == -500)
        // Over the car's two months, what's spent is its loss of value: 20,000 less the 18,500 it sold for.
        let both = sold.saved(after: "2026-01-31", through: "2026-03-31")
        #expect(both.byAccount.values.reduce(Decimal(0), +) == -1500)
    }

    /// A car that loses an estimated 12% a year: its estimated loss of value
    /// is spent month by month, and the next typed value trues it up.
    @Test func aCarsEstimatedLossOfValueIsSpentAndTrueUp() throws {
        var library = month
        library.accounts["car"] = Account(id: "car", name: "Car", kind: .belongings, currency: .eur,
                                          opened: "2026-01-10", depreciation: d("0.12"))
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: -10550, saved: -20550, moneyIn: 4000,
                                 moneyOut: 4550))
        library.upsert(Valuation(account: "car", date: "2026-01-31", balance: 20000, saved: 20000))
        let valuator = Valuator(library: library)
        // 181 days at 12% a year: 20,000 × 12% × 181 / 365.
        #expect(valuator.saved(after: "2026-01-31", through: "2026-07-31").byAccount["car"] == d("-1190.14"))
        // Worth 17,000 at the end of August: the rest of the 3,000 it lost.
        library.upsert(Valuation(account: "car", date: "2026-08-31", balance: 17000))
        let typed = Valuator(library: library)
        #expect(typed.saved(after: "2026-07-31", through: "2026-08-31").byAccount["car"] == d("-1809.86"))
        #expect(typed.saved(after: "2026-01-31", through: "2026-08-31").byAccount["car"] == -3000)
        // Two years and two days on (2028 is a leap year), compounding: 10,000 × 0.88² × (1 − 0.12 × 2 / 365).
        library.upsert(Valuation(account: "car", date: "2027-08-31", balance: 10000))
        let later = Valuator(library: library)
        #expect(later.saved(after: "2027-08-31", through: "2029-09-01").byAccount["car"] == d("-2261.09"))
    }

    /// A check-in fills in a new account's whole amount as its saved: only the
    /// part that left an account already tracked is saved.
    @Test func aNewAccountsFirstValueIsSavedOnlyAsFarAsItMovedFromAnother() throws {
        var library = month
        library.accounts["old-savings"] = Account(id: "old-savings", name: "Old savings", kind: .savings,
                                                  currency: .eur, opened: "2026-01-15")
        library.upsert(Valuation(account: "old-savings", date: "2026-01-31", balance: 20000, saved: 20000))
        let savings = try #require(Valuator(library: library).savingsRate(from: "2026-01-01", through: "2026-01-31"))
        // The bank's 550 drop is the only negative saved amount at that check-in.
        #expect(savings.savedByAccount["old-savings"] == 550)
        #expect(savings.saved == 2000)
        // The Overview's bars move what it already held from saved to other.
        let valuator = Valuator(library: library)
        let report = valuator.change(from: "2025-12-31", to: "2026-01-31")
        let split = valuator.savedSplit(of: report)
        #expect(split.saved == 2000)
        #expect(split.other == report.total.other + 19450)
        #expect(split.start + split.market + split.saved + split.other == split.end)
    }

    /// A loan you start tracking at a check-in of its own owed what it owes
    /// already: it isn't spent. One paid out into the current account at
    /// that check-in cancels out against the money it brought.
    @Test func aDebtsFirstValueIsSavedOnlyAsFarAsItMovedIntoAnother() throws {
        var library = month
        library.accounts["auto"] = Account(id: "auto", name: "Car loan", kind: .loan, currency: .eur,
                                           opened: "2026-02-10")
        library.upsert(Valuation(account: "auto", date: "2026-02-15", balance: -10000, saved: -10000))
        let tracked = Valuator(library: library).saved(after: "2025-12-31", through: "2026-02-15")
        #expect(tracked.byAccount["auto"] == 0)
        #expect(tracked.byAccount.values.reduce(Decimal(0), +) == 1450)

        library.upsert(Valuation(account: "bank", date: "2026-02-15", balance: 19450, saved: 10000, moneyIn: 0,
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
        library.upsert(Valuation(account: "auto", date: "2026-01-31", balance: -10000, saved: -10000))
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
        library.upsert(Valuation(account: "auto", date: "2026-09-30", balance: -10000, saved: -10000))
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
        library.upsert(Valuation(account: "side", date: "2025-12-31", balance: 0, saved: 0))
        library.upsert(Valuation(account: "side", date: "2026-01-31", balance: 0, saved: 0, moneyIn: 700,
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

    /// Pay of 4,000 a month before tax into the current account, 1,000 of
    /// it moved to a tax pot and 2,000 spent, from January to May; in June
    /// the pot pays the 5,000 bill, and no more is set aside.
    let taxPot: Library = {
        var library = Library(settings: LibrarySettings(baseCurrency: .eur))
        library.accounts["bank"] = Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2025-12-01")
        library.accounts["pot"] = Account(id: "pot", name: "Taxes", kind: .taxPot, currency: .eur, opened: "2025-12-01")
        library.upsert(Valuation(account: "bank", date: "2025-12-31", balance: 10000, saved: 10000))
        library.upsert(Valuation(account: "pot", date: "2025-12-31", balance: 0, saved: 0))
        let ends: [CalendarDate] = ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31"]
        for (index, end) in ends.enumerated() {
            let kept = Decimal(index + 1) * 1000
            library.upsert(Valuation(account: "bank", date: end, balance: 10000 + kept, saved: 1000, moneyIn: 4000,
                                     moneyOut: 3000))
            library.upsert(Valuation(account: "pot", date: end, balance: kept, saved: 1000))
        }
        library.upsert(Valuation(account: "bank", date: "2026-06-30", balance: 17000, saved: 2000, moneyIn: 4000,
                                 moneyOut: 2000))
        library.upsert(Valuation(account: "pot", date: "2026-06-30", balance: 0, saved: -5000))
        return library
    }()

    /// What's put into a tax pot is tax: came in is after it, and it isn't spent.
    @Test func aTaxPotsSetAsidesAreTaxNotSpending() throws {
        let valuator = Valuator(library: taxPot)
        let months = try #require(valuator.savingsRate(from: "2026-01-01", through: "2026-05-31"))
        #expect(months.moneyInOut.moneyIn == 20000)
        #expect(months.taxSetAside == 5000)
        #expect(months.tax == 5000)
        #expect(months.income == 15000)
        // The pot is outside net worth: only the current account's 1,000 a month is saved.
        #expect(months.savedByAccount["pot"] == nil)
        #expect(months.saved == 5000)
        #expect(months.spent == 10000)
        #expect(months.rate?.rounded(scale: 4) == d("0.3333"))
        // The bill paid from the pot isn't negative tax.
        let june = try #require(valuator.savingsRate(from: "2026-06-01", through: "2026-06-30"))
        #expect(june.taxSetAside == 0)
        #expect(june.income == 4000)
        #expect(june.spent == 2000)
        // Net worth never holds the pot.
        #expect(valuator.netWorth(on: "2026-05-31").total == 15000)
    }

    /// A tax pot counted in net worth is savings: what's put in is saved.
    @Test func aTaxPotInNetWorthIsSaved() throws {
        var library = taxPot
        library.accounts["pot"]?.includeIn = IncludeIn(netWorth: true)
        let savings = try #require(Valuator(library: library).savingsRate(from: "2026-01-01", through: "2026-05-31"))
        #expect(savings.taxSetAside == 0)
        #expect(savings.income == 20000)
        #expect(savings.saved == 10000)
        #expect(savings.spent == 10000)
    }

    /// With money in and out recorded on the pot, a check-in that covers
    /// both a set-aside and the bill counts the set-aside, and money taken
    /// back lowers the tax.
    @Test func aTaxPotsTaxIsWhatMovedIntoIt() throws {
        var library = taxPot
        // June: 1,000 more set aside, and the 6,000 bill paid from the pot.
        library.upsert(Valuation(account: "bank", date: "2026-06-30", balance: 16000, saved: 1000, moneyIn: 4000,
                                 moneyOut: 3000))
        library.upsert(Valuation(account: "pot", date: "2026-06-30", balance: 0, saved: -5000, moneyIn: 0,
                                 moneyOut: 6000))
        let june = try #require(Valuator(library: library).savingsRate(from: "2026-06-01", through: "2026-06-30"))
        #expect(june.tax == 1000)
        #expect(june.income == 3000)
        #expect(june.spent == 2000)
        // July: 500 of a pot's leftover moved back to the current account.
        library.upsert(Valuation(account: "pot", date: "2026-06-30", balance: 500, saved: -4500, moneyIn: 0,
                                 moneyOut: 5500))
        library.upsert(Valuation(account: "bank", date: "2026-07-31", balance: 18500, saved: 2500, moneyIn: 4000,
                                 moneyOut: 2000))
        library.upsert(Valuation(account: "pot", date: "2026-07-31", balance: 0, saved: -500, moneyIn: 0,
                                 moneyOut: 0))
        let july = try #require(Valuator(library: library).savingsRate(from: "2026-07-01", through: "2026-07-31"))
        #expect(july.tax == -500)
        #expect(july.income == 4500)
        #expect(july.spent == 2000)
    }

    /// Tax paid straight from the current account, and a refund of it, are
    /// tax, not spending, spread over the year before they were paid.
    @Test func taxPaidFromACurrentAccountIsNotSpent() throws {
        var library = month
        // January also paid 1,200 of tax from the current account, which is in its money out.
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 8250, saved: -1750, moneyIn: 4000,
                                 moneyOut: 5750, tax: 1200))
        var savings = try #require(Valuator(library: library).savingsRate(from: "2026-01-01", through: "2026-01-31"))
        #expect(savings.moneyInOut.taxes == 1200)
        // January's 31 days of the 365 the bill pays for: 1,200 × 31 / 365.
        #expect(savings.spreadTaxes == d("101.92"))
        #expect(savings.tax == d("101.92"))
        #expect(savings.income == d("4198.08"))
        // The 1,750 the current account lost, less the bill, plus January's share set aside.
        #expect(savings.saved == d("1348.08"))
        // As in the month without the tax.
        #expect(savings.spent == 2850)
        // A refund of 300 instead lowers money out and the tax.
        library.upsert(Valuation(account: "bank", date: "2026-01-31", balance: 9750, saved: -250, moneyIn: 4000,
                                 moneyOut: 4250, tax: -300))
        savings = try #require(Valuator(library: library).savingsRate(from: "2026-01-01", through: "2026-01-31"))
        #expect(savings.tax == d("-25.48"))
        #expect(savings.income == d("4325.48"))
        #expect(savings.spent == 2850)
    }

    /// A yearly bill of 3,650 paid from the current account in February
    /// counts as tax a little in each day of the year before it, as if it
    /// had been set aside, so neither month goes below nothing coming in.
    @Test func aTaxBillCountsOverTheYearBeforeIt() throws {
        var library = month
        // February: pay of 4,000, 2,000 spent and the bill.
        library.upsert(Valuation(account: "bank", date: "2026-02-28", balance: 7800, saved: -1650, moneyIn: 4000,
                                 moneyOut: 5650, tax: 3650))
        let valuator = Valuator(library: library)
        #expect(valuator.spreadTax(after: "2025-02-28", through: "2026-02-28") == 3650)
        #expect(valuator.spreadTax(after: "2025-11-30", through: "2025-12-31") == 310)
        #expect(valuator.spreadTax(after: "2026-02-28", through: "2026-03-31") == 0)

        // January holds 31 of its 365 days: 310, though it paid none.
        let january = try #require(valuator.savingsRate(from: "2026-01-01", through: "2026-01-31"))
        #expect(january.moneyInOut.taxes == 0)
        #expect(january.tax == 310)
        #expect(january.income == 3990)
        #expect(january.saved == 1140)
        #expect(january.spent == 2850)

        // February holds 28: 280. The bill's 3,650 is added back to what was saved.
        let february = try #require(valuator.savingsRate(from: "2026-02-01", through: "2026-02-28"))
        #expect(february.moneyInOut.taxes == 3650)
        #expect(february.tax == 280)
        #expect(february.income == 3720)
        #expect(february.saved == 1720)
        #expect(february.spent == 2000)
        #expect(february.noRate == nil)
        #expect(february.rate.map { $0 > 0 } == true)

        // The Overview's Saved bar counts it the same way, the difference under Other.
        let report = valuator.change(from: "2025-12-31", to: "2026-02-28")
        let split = valuator.savedSplit(of: report)
        #expect(split.saved == january.saved + february.saved)
        #expect(split.other == report.total.other + report.total.saved - split.saved)
        #expect(split.start + split.market + split.saved + split.other == split.end)
    }
}
