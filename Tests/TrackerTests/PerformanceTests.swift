import Foundation
import Model
import Testing
import TestSupport
import Tracker

private func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

struct XIRRTests {
    @Test func oneYearAtTenPercent() throws {
        let rate = try #require(XIRR.rate(of: [
            DatedAmount(date: "2025-01-01", amount: -1000), DatedAmount(date: "2026-01-01", amount: 1100),
        ]))
        #expect(rate.rounded(8) == d("0.1"))
    }

    @Test func spreadsheetExample() throws {
        // The example from spreadsheet documentation for XIRR: 37.34%.
        let rate = try #require(XIRR.rate(of: [
            DatedAmount(date: "2008-01-01", amount: -10000), DatedAmount(date: "2008-03-01", amount: 2750),
            DatedAmount(date: "2008-10-30", amount: 4250), DatedAmount(date: "2009-02-15", amount: 3250),
            DatedAmount(date: "2009-04-01", amount: 2750),
        ]))
        #expect(rate.rounded(8) == d("0.37336253"))
    }

    @Test func losses() throws {
        let rate = try #require(XIRR.rate(of: [
            DatedAmount(date: "2025-01-01", amount: -1000), DatedAmount(date: "2025-02-01", amount: 500),
        ]))
        // Half lost in 31 days: 0.5^(365/31) − 1.
        #expect(rate.rounded(6) == d("-0.999714"))
    }

    @Test func noSolution() {
        #expect(XIRR.rate(of: []) == nil)
        #expect(XIRR.rate(of: [DatedAmount(date: "2025-01-01", amount: -1000),
                               DatedAmount(date: "2026-01-01", amount: -10)]) == nil)
        #expect(XIRR.rate(of: [DatedAmount(date: "2025-01-01", amount: -1000),
                               DatedAmount(date: "2025-01-01", amount: 1100)]) == nil)
    }
}

struct ReturnFigureTests {
    @Test func annualisesOnlyPeriodsLongerThanAYear() {
        let twoYears = ReturnFigure(cumulative: d("0.21"), days: 730)
        #expect(twoYears.annualized?.rounded(8) == d("0.1"))
        #expect(twoYears.headline == twoYears.annualized)
        let year = ReturnFigure(cumulative: d("0.05"), days: 365)
        #expect(year.annualized == nil)
        #expect(year.headline == d("0.05"))
    }
}

/// Hand-made libraries with returns worked out by hand.
struct PerformanceTests {
    /// A pension fund: 1,000 → 1,150 with 100 contributed → 1,200.
    private func fundLibrary() -> Library {
        var library = Library(accounts: [
            Account(id: "fund", name: "Fund", kind: .pensionFund, currency: .eur, opened: "2025-01-01"),
            Account(id: "home", name: "Home", kind: .property, currency: .eur, opened: "2020-01-01"),
            Account(id: "loan", name: "Loan", kind: .loan, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "fund", date: "2025-01-31", balance: 1000))
        library.upsert(Valuation(account: "fund", date: "2025-02-28", balance: 1150, flow: 100))
        library.upsert(Valuation(account: "fund", date: "2025-03-31", balance: 1200, flow: 0))
        library.upsert(Valuation(account: "home", date: "2025-01-31", balance: 200_000))
        library.upsert(Valuation(account: "home", date: "2025-03-31", balance: 210_000))
        library.upsert(Valuation(account: "loan", date: "2025-01-31", balance: -5000))
        library.upsert(Valuation(account: "loan", date: "2025-03-31", balance: -4000, flow: 1000))
        for (date, value) in [("2025-01-31", "100"), ("2025-02-28", "101"), ("2025-03-31", "102")] {
            library.upsert(IndexRecord(index: .hicpIT, date: CalendarDate(date)!, value: d(value)))
        }
        return library
    }

    @Test func timeWeightedIsModifiedDietzChained() throws {
        let library = fundLibrary()
        let result = try #require(Valuator(library: library).performance(
            of: .account("fund"), from: "2025-01-31", to: "2025-03-31", inflation: InflationIndex(library: library)))
        // February: the 100 arrives mid-month, so (1,150 − 1,000 − 100) ÷ (1,000 + 50).
        // March: 50 ÷ 1,150.
        let expected = (Decimal(1100) * 1200) / (Decimal(1050) * 1150) - 1
        let twr = try #require(result.timeWeighted)
        #expect(twr.cumulative.rounded(20) == expected.rounded(20))
        #expect(twr.annualized == nil)
        #expect(result.startValue == 1000)
        #expect(result.endValue == 1200)
        #expect(result.netFlows == 100)
        #expect(result.days == 59)

        // −1,000 on 31 Jan, −100 on 14 Feb, +1,200 on 31 Mar.
        let mwr = try #require(result.moneyWeighted)
        #expect(mwr.cumulative.rounded(6) == d("0.092983"))

        let inflation = try #require(result.inflation)
        #expect(inflation.cumulative == d("0.02"))
        #expect(result.realTimeWeighted?.cumulative.rounded(12) == ((1 + expected) / d("1.02") - 1).rounded(12))
        #expect(try #require(result.realMoneyWeighted).cumulative < mwr.cumulative)
    }

    @Test func portfolioLeavesOutUnknownFlowsAndDebts() throws {
        let result = try #require(Valuator(library: fundLibrary()).performance(
            of: .portfolio(.netWorth), from: "2025-01-31", to: "2025-03-31"))
        #expect(result.accounts == ["fund"])
        #expect(result.unknownFlowAccounts == ["home"])
        #expect(result.incompleteAccounts.isEmpty)
        #expect(result.realTimeWeighted == nil)

        let home = try #require(Valuator(library: fundLibrary()).performance(
            of: .account("home"), from: "2025-01-31", to: "2025-03-31"))
        #expect(home.timeWeighted == nil)
        #expect(home.moneyWeighted == nil)
        #expect(home.unknownFlowAccounts == ["home"])
    }

    /// A broker: 10 shares at 100 plus 100 cash; in February 1 more share
    /// bought with 50 of the cash and 60 new money; the price then rises 10%.
    private func brokerLibrary() -> Library {
        var library = Library(
            accounts: [Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2025-01-01")],
            instruments: [Instrument(id: "etf", name: "ETF", kind: .etf, currency: .eur, unit: .share,
                                     assetClasses: .single(.equity))])
        library.upsert(Valuation(account: "broker", date: "2025-01-31", cash: 100,
                                 positions: [Position(instrument: "etf", quantity: 10)]))
        library.upsert(Valuation(account: "broker", date: "2025-02-28", cash: 50,
                                 positions: [Position(instrument: "etf", quantity: 11)], flow: 60))
        for (date, price) in [("2025-01-31", 100), ("2025-02-28", 110), ("2025-03-31", 121)] {
            library.upsert(PriceRecord(instrument: "etf", date: CalendarDate(date)!, price: Decimal(price),
                                       currency: .eur))
        }
        return library
    }

    @Test func assetClassesSeePurchasesAsFlows() throws {
        let valuator = Valuator(library: brokerLibrary())
        let equity = try #require(valuator.performance(of: .assetClass(.equity, .netWorth),
                                                       from: "2025-01-31", to: "2025-03-31"))
        // February: (1,210 − 1,000 − 110) ÷ (1,000 + 55); March: +10%.
        let expected = (1 + Decimal(100) / 1055) * d("1.1") - 1
        #expect(equity.timeWeighted?.cumulative.rounded(20) == expected.rounded(20))
        #expect(equity.startValue == 1000)
        #expect(equity.endValue == 1331)
        #expect(equity.netFlows == 110)

        // The cash paid for the share left the cash class: no return on cash.
        let cash = try #require(valuator.performance(of: .assetClass(.cash, .netWorth),
                                                     from: "2025-01-31", to: "2025-03-31"))
        #expect(cash.timeWeighted?.cumulative == 0)
        #expect(cash.netFlows == -50)

        // The account as a whole: February (1,260 − 1,100 − 60) ÷ (1,100 + 30), March 121 ÷ 1,260.
        let account = try #require(valuator.performance(of: .account("broker"), from: "2025-01-31",
                                                        to: "2025-03-31"))
        let whole = (1 + Decimal(100) / 1130) * (1 + Decimal(121) / 1260) - 1
        #expect(account.timeWeighted?.cumulative.rounded(20) == whole.rounded(20))
    }

    @Test func missingPricesLeaveTheAccountOut() throws {
        var library = brokerLibrary()
        library.upsert(Valuation(account: "broker", date: "2025-03-31", cash: 50, positions: [
            Position(instrument: "etf", quantity: 11), Position(instrument: "unpriced", quantity: 1),
        ], flow: 0))
        let result = try #require(Valuator(library: library).performance(of: .portfolio(.netWorth),
                                                                         from: "2025-01-31", to: "2025-03-31"))
        #expect(result.incompleteAccounts == ["broker"])
        #expect(result.accounts.isEmpty)
        #expect(result.timeWeighted == nil)
    }
}

/// Periods and returns on the example library.
struct ExampleLibraryPerformanceTests {
    let library: Library
    let valuator: Valuator

    init() throws {
        library = try Fixtures.exampleLibrary()
        valuator = Valuator(library: library)
    }

    @Test func periods() {
        let portfolio = PerformanceSubject.portfolio(.netWorth)
        #expect(valuator.dateRange(of: .sinceLastCheckIn, for: portfolio, asOf: "2026-09-30")
            == "2026-08-31"..."2026-09-30")
        #expect(valuator.dateRange(of: .yearToDate, for: portfolio, asOf: "2026-09-30")
            == "2025-12-31"..."2026-09-30")
        #expect(valuator.dateRange(of: .sinceStart, for: portfolio, asOf: "2026-09-30")
            == "2025-10-31"..."2026-09-30")
        // Not enough history.
        #expect(valuator.dateRange(of: .oneYear, for: portfolio, asOf: "2026-09-30") == nil)
        #expect(valuator.dateRange(of: .oneYear, for: portfolio, asOf: "2026-10-31")
            == "2025-10-31"..."2026-10-31")
        #expect(valuator.dateRange(of: .threeYears, for: portfolio, asOf: "2026-09-30") == nil)
        #expect(valuator.dateRange(of: .sinceLastCheckIn, for: .account("tfr"), asOf: "2026-09-30")
            == "2025-12-31"..."2026-06-30")
    }

    @Test func sinceTheLastCheckIn() throws {
        let result = try #require(valuator.performance(of: .portfolio(.netWorth), over: .sinceLastCheckIn,
                                                       asOf: "2026-09-30", inflation: InflationIndex(library: library)))
        #expect(result.accounts == ["conto-deposito", "conto-fineco", "directa", "fondo-pensione", "gold-coins",
                                    "ledger-wallet", "tfr"])
        // The home's value was carried from June, when it had no flow.
        #expect(result.unknownFlowAccounts == ["casa"])
        #expect(result.startValue.rounded(2) == d("156737.83"))
        #expect(result.endValue.rounded(2) == d("161505.49"))
        #expect(result.netFlows == d("1531.65"))
        // One piece: gains 3,236.01 over 156,737.83 plus half of the monthly
        // flows and all of the pension fund's quarterly contribution.
        let twr = try #require(result.timeWeighted)
        #expect(twr.cumulative.rounded(10) == d("0.0204595711"))
        #expect(result.moneyWeighted != nil)
        // No index value for September yet: August's is used, so no inflation.
        #expect(result.inflation?.cumulative == 0)
        #expect(result.realTimeWeighted?.cumulative.rounded(10) == d("0.0204595711"))
    }

    @Test func sinceTheStart() throws {
        let result = try #require(valuator.performance(of: .portfolio(.netWorth), over: .sinceStart,
                                                       asOf: "2026-09-30", inflation: InflationIndex(library: library)))
        #expect(result.unknownFlowAccounts == ["casa"])
        #expect(result.accounts == ["conto-deposito", "conto-fineco", "directa", "fondo-pensione", "gold-coins",
                                    "ledger-wallet", "old-bank", "tfr"])
        #expect(result.startValue.rounded(2) == d("132390.28"))
        #expect(result.endValue.rounded(2) == d("161505.49"))
        // Every recorded flow, and the closed account's 850 leaving.
        #expect(result.netFlows == d("23692.65"))
        // Gains of 5,422.57 over roughly 140,000 invested.
        let twr = try #require(result.timeWeighted)
        let mwr = try #require(result.moneyWeighted)
        #expect(twr.annualized == nil)
        #expect(twr.cumulative > d("0.03") && twr.cumulative < d("0.045"))
        #expect(abs(mwr.cumulative - twr.cumulative) < d("0.01"))
        let inflation = try #require(result.inflation)
        #expect(inflation.cumulative.rounded(10) == (d("128.41") / d("126.1") - 1).rounded(10))
        let real = try #require(result.realTimeWeighted)
        #expect(real.cumulative.rounded(12) == ((1 + twr.cumulative) / (d("128.41") / d("126.1")) - 1).rounded(12))

        // By asset class, the parts cover the same accounts.
        let gold = try #require(valuator.performance(of: .assetClass(.gold, .netWorth), over: .sinceStart,
                                                     asOf: "2026-09-30"))
        // Only accounts holding gold count; the home doesn't show up as unknown.
        #expect(gold.accounts == ["gold-coins"])
        #expect(gold.unknownFlowAccounts.isEmpty)
        #expect(gold.startValue == d("5728.62"))
        #expect(gold.endValue == d("9180.72"))
        #expect(gold.netFlows == d("3026.03"))
        #expect(try #require(gold.timeWeighted).cumulative > 0)
    }
}

struct InflationIndexTests {
    @Test func exampleLibraryIndex() throws {
        let index = try #require(InflationIndex(library: try Fixtures.exampleLibrary()))
        #expect(index.index == .hicpIT)
        #expect(index.records.count == 11)
        #expect(index.value(on: "2026-09-30")?.date == "2026-08-31")
        #expect(index.value(on: "2026-09-15")?.value == d("128.41"))
        #expect(index.value(on: "2025-10-30") == nil)
        #expect(index.factor(from: "2025-10-31", to: "2026-08-31") == d("128.41") / d("126.1"))
        #expect(index.convert(1000, from: "2025-10-31", to: "2026-09-30")?.rounded(4) == d("1018.3188"))
        #expect(index.convert(1000, from: "2025-10-30", to: "2026-09-30") == nil)
        #expect(index.inflation(from: "2025-11-30", to: "2025-12-31")?.rounded(6) == d("0.002779"))
    }

    @Test func seriesInTodaysMoney() throws {
        let library = try Fixtures.exampleLibrary()
        let nominal = Valuator(library: library).series(through: "2026-09-30")
        let real = try #require(InflationIndex(library: library)).series(nominal, inMoneyOf: "2026-09-30")
        #expect(real.count == nominal.count)
        #expect(real.last?.value == nominal.last?.value)
        #expect(real.first?.value.rounded(10) == (nominal.first!.value * d("128.41") / d("126.1")).rounded(10))
    }

    @Test func otherIndicesAreIgnored() {
        let index = InflationIndex([
            IndexRecord(index: .hicpIT, date: "2025-01-31", value: 100),
            IndexRecord(index: "cpi-us", date: "2025-01-31", value: 300),
            IndexRecord(index: .hicpIT, date: "2026-01-31", value: 103),
        ], index: .hicpIT)
        #expect(index.convert(100, from: "2025-01-31", to: "2026-01-31") == 103)
        #expect(index.convert(103, from: "2026-01-31", to: "2025-06-30") == 100)
    }

    /// The library's own index follows its settings, not a fixed country.
    @Test func theLibrarysIndexIsItsOwn() throws {
        var library = try Fixtures.exampleLibrary()
        library.settings.taxResidence = .de
        for (date, value) in [("2025-10-31", "120"), ("2026-08-31", "126")] {
            library.upsert(IndexRecord(index: "hicp-de", date: CalendarDate(date)!, value: d(value)))
        }
        let germany = try #require(InflationIndex(library: library))
        #expect(germany.index == "hicp-de")
        #expect(germany.convert(1000, from: "2025-10-31", to: "2026-09-30") == 1050)

        library.settings = LibrarySettings(baseCurrency: .usd, taxResidence: .us)
        #expect(InflationIndex(library: library) == nil)
        library.settings.inflationIndex = .hicpIT
        #expect(InflationIndex(library: library)?.records.count == 11)
    }
}
