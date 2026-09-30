import Foundation
@testable import Importer
import Model
import Testing

/// Reading journals: syntax, amounts, directives, includes, balancing.
struct LedgerReaderTests {
    // MARK: - Syntax

    @Test func ledgerCLISyntax() throws {
        let journal = try LedgerSamples.read("ledger-cli.ledger")
        #expect(journal.transactions.map(\.description) == [
            "Paycheck", "Rent", "Stocks", "Moving money, virtually", "Transfer within", "Sale",
        ])
        let paycheck = journal.transactions[0]
        #expect(paycheck.date == date("2024-01-05"))
        #expect(paycheck.status == .cleared)
        #expect(paycheck.code == "1001")
        #expect(paycheck.postings.map(\.account) == ["Assets:Checking", "Income:Salary"])
        #expect(paycheck.postings.map(\.amount) == [LedgerAmount(dec("3000"), "$"), LedgerAmount(dec("-3000"), "$")])
        #expect(paycheck.postings[1].isInferred)

        let rent = journal.transactions[1]
        #expect(rent.date == date("2024-01-10"))
        #expect(rent.status == .pending)

        let stocks = journal.transactions[2]
        #expect(stocks.postings[0].amount == LedgerAmount(10, "AAPL"))
        #expect(stocks.postings[0].cost == LedgerAmount(1500, "$"))
        #expect(stocks.postings[0].unitPrice == LedgerAmount(150, "$"))
        #expect(stocks.postings[1].amount == LedgerAmount(-1500, "$"))

        let virtual = journal.transactions[3]
        #expect(virtual.postings.map(\.kind) == [.balancedVirtual, .balancedVirtual, .unbalancedVirtual])
        #expect(virtual.postings.map(\.account) == ["Assets:Savings", "Assets:Checking", "Budget:Fun"])

        let within = journal.transactions[4]
        #expect(within.postings.map(\.account) == ["Assets:Savings", "Assets:Checking"])
        #expect(within.postings[1].amount == LedgerAmount(-200, "$"))

        let sale = journal.transactions[5]
        #expect(sale.postings[0].amount == LedgerAmount(-4, "AAPL"))
        #expect(sale.postings[0].cost == LedgerAmount(-600, "$"), "a lot price is what the posting balances with")
        #expect(sale.postings[0].unitPrice == LedgerAmount(160, "$"))

        #expect(journal.balance("Assets:Checking", "$") == 640)
        #expect(journal.balance("Assets:Savings", "$") == 300)
        #expect(journal.balance("Assets:Brokerage", "AAPL") == 6)
        #expect(journal.prices.map(\.commodity) == ["AAPL", "EUR"])
        #expect(journal.prices[1].price == LedgerAmount(dec("1.08"), "$"))
        #expect(journal.declaredAccounts == ["Assets:Checking"])

        #expect(journal.messages == [
            "24: Automated transactions (`=`) aren't supported; this one was skipped.",
            "27: Periodic transactions (`~`) aren't supported; this one was skipped.",
            "31: The `define` directive isn't supported; it was skipped.",
            "32: The `bucket` directive isn't supported; it was skipped.",
            "57: The transaction doesn't balance: it's off by 15 $. It was skipped.",
        ])
        #expect(journal.errors.count == 1)
    }

    @Test func hledgerSyntaxWithADecimalComma() throws {
        let journal = try LedgerSamples.read("hledger.journal")
        #expect(journal.transactions.count == 7)
        #expect(journal.accountTypes == ["assets:banca:conto": .asset, "liabilities:mutuo": .liability,
                                         "income:stipendio": .revenue])
        let opening = journal.transactions[0]
        #expect(opening.postings.map(\.amount) == [
            LedgerAmount(10000, "EUR"), LedgerAmount(-150_000, "EUR"), LedgerAmount(140_000, "EUR"),
        ])
        #expect(journal.transactions[1].postings[0].amount == LedgerAmount(dec("2000.5"), "EUR"))
        // The balance assignment sets the amount.
        let rata = journal.transactions[2]
        #expect(rata.postings[2].amount == LedgerAmount(-750, "EUR"))
        #expect(rata.postings[2].isInferred)
        // A quoted commodity with an `@` price in decimal comma.
        let etf = journal.transactions[5]
        #expect(etf.postings[0].amount == LedgerAmount(3, "VWCE.MI"))
        #expect(etf.postings[0].cost == LedgerAmount(dec("316.5"), "EUR"))
        #expect(etf.postings[1].amount == LedgerAmount(dec("-316.5"), "EUR"))
        // Two commodities without a price: the price is inferred.
        let crypto = journal.transactions[6]
        #expect(crypto.postings[0].amount == LedgerAmount(dec("0.01"), "BTC"))
        #expect(crypto.postings[0].cost == LedgerAmount(400, "EUR"))
        #expect(crypto.postings[0].unitPrice == nil)

        #expect(journal.balance("assets:banca:conto", "EUR") == dec("10484"))
        #expect(journal.balance("liabilities:mutuo", "EUR") == -149_400)
        #expect(journal.prices == [LedgerMarketPrice(
            date: date("2024-02-29"), commodity: "VWCE.MI", price: LedgerAmount(dec("107.25"), "EUR"),
            location: LedgerLocation(file: "hledger.journal", line: 39))])
        // Passing assertions are silent; the failing one is a warning, and the transaction stays.
        #expect(journal.messages == [
            "28: The balance assertion for assets:banca:conto fails: it's 11200.5 EUR, the journal says 11000 EUR.",
        ])
        #expect(journal.warnings.count == 1)
    }

    // MARK: - Amounts

    @Test(arguments: [
        ("€5", "5", "€"), ("5 EUR", "5", "EUR"), ("-5.00 EUR", "-5", "EUR"), ("EUR -5", "-5", "EUR"),
        ("-€5", "-5", "€"), ("€-5", "-5", "€"), ("5EUR", "5", "EUR"), ("$1,000.50", "1000.5", "$"),
        ("\"VWCE.MI\" 10", "10", "VWCE.MI"), ("10 \"BTC-2\"", "10", "BTC-2"), ("10 VWCE.MI", "10", "VWCE.MI"),
        ("1.000,50 EUR", "1000.5", "EUR"), ("- 7 CHF", "-7", "CHF"), ("0.00001 BTC", "0.00001", "BTC"),
        ("1'234.5 CHF", "1234.5", "CHF"), ("12", "12", ""), ("+3 GBP", "3", "GBP"),
    ])
    func amountForms(text: String, quantity: String, commodity: String) throws {
        let parts = try LedgerAmountParser.split(text).get()
        let value = try #require(LedgerAmountParser.value(of: parts.number, negative: parts.negative, mark: nil,
                                                          fallback: "."))
        #expect(value.value == dec(quantity), "\(text)")
        #expect(parts.commodity == commodity, "\(text)")
    }

    @Test func amountsThatArentAmounts() {
        for text in ["EUR", "--5 EUR", "\"VWCE 5", "5 EUR EUR"] {
            #expect(throws: AmountError.self, "\(text)") { try LedgerAmountParser.split(text).get() }
        }
    }

    @Test func ambiguousNumbersFollowTheJournal() {
        // `1.000` alone could be either; the fallback (from the file's other numbers) decides.
        #expect(LedgerAmountParser.value(of: "1.000", negative: false, mark: nil, fallback: ".")?.value == 1)
        #expect(LedgerAmountParser.value(of: "1.000", negative: false, mark: nil, fallback: ",")?.value == 1000)
        #expect(LedgerAmountParser.value(of: "1,000", negative: false, mark: nil, fallback: ".")?.value == 1000)
        #expect(LedgerAmountParser.value(of: "1,5", negative: false, mark: nil, fallback: ".")?.value == dec("1.5"))
        #expect(LedgerAmountParser.value(of: "1.000.000", negative: false, mark: nil, fallback: ".")?.value
            == 1_000_000)
        // A declared mark wins.
        #expect(LedgerAmountParser.value(of: "1.000", negative: false, mark: ",", fallback: ".")?.value == 1000)
        #expect(LedgerAmountParser.value(of: "1,5,0", negative: false, mark: ",", fallback: ".") == nil)
    }

    @Test func aFileWithDecimalCommasReadsAmbiguousNumbersThatWay() {
        let journal = LedgerReader.read(text: """
            2024-01-01 Opening
                Assets:Bank   1.500 EUR
                Assets:Cash   12,50 EUR
                Equity:Opening
            """)
        #expect(journal.balance("Assets:Bank", "EUR") == 1500)
        #expect(journal.balance("Assets:Cash", "EUR") == dec("12.5"))
    }

    @Test func commodityFormatsAndDefaultCommodity() {
        let journal = LedgerReader.read(text: """
            commodity EUR
                format 1.000,00 EUR
            commodity 1,000.00 USD
            D 1.000,00 EUR

            2024-01-01 Opening
                Assets:Bank     1.000 EUR
                Assets:Dollars  1.000 USD
                Assets:Cash     2,5
                Equity:Opening
            """)
        #expect(journal.balance("Assets:Bank", "EUR") == 1000)
        #expect(journal.balance("Assets:Dollars", "USD") == 1)
        #expect(journal.balance("Assets:Cash", "EUR") == dec("2.5"))
        #expect(journal.errors.isEmpty)
    }

    // MARK: - Directives

    @Test func aliasesRegexAliasesAndApplyAccount() {
        let journal = LedgerReader.read(text: """
            alias /^(expenses):food/ = \\1:Groceries
            alias bank = Assets:Bank
            2024-01-01 Food
                expenses:food:market   10 EUR
                bank
            apply account Personal
            2024-01-02 Inside
                Cash   1 EUR
                bank
            end apply account
            end aliases
            2024-01-03 After
                bank   1 EUR
                Equity:Opening
            """)
        #expect(journal.transactions[0].postings.map(\.account) == ["expenses:Groceries:market", "Assets:Bank"])
        // The prefix comes first, then aliases: `Personal:bank` isn't `bank`.
        #expect(journal.transactions[1].postings.map(\.account) == ["Personal:Cash", "Personal:bank"])
        #expect(journal.transactions[2].postings.map(\.account) == ["bank", "Equity:Opening"])
    }

    @Test func datesWithoutAYearNeedTheYearDirective() {
        let journal = LedgerReader.read(text: """
            3/1 No year yet
                Assets:Cash   1 EUR
                Equity:Opening

            year 2023
            3/2 With the year
                Assets:Cash   1 EUR
                Equity:Opening

            2023-02-30 No such day
                Assets:Cash   1 EUR
                Equity:Opening
            """)
        #expect(journal.transactions.map(\.date) == [date("2023-03-02")])
        #expect(journal.messages == [
            "1: “3/1” has no year; add a `year` directive before it.",
            "10: “2023-02-30” is no such date.",
        ])
    }

    @Test func assertionsAndAssignmentsFollowTheDateOrder() throws {
        let journal = try LedgerSamples.read("years/2023.journal", "years/2024.journal")
        #expect(journal.transactions.map(\.date) == [date("2023-12-31"), date("2024-01-05"), date("2024-01-31")])
        #expect(journal.transactions[1].postings[1].amount == LedgerAmount(-900, "EUR"))
        #expect(journal.balance("Assets:Bank", "EUR") == 2600)
        #expect(journal.diagnostics.isEmpty)
    }

    @Test func inclusiveAndExactAssertions() {
        let journal = LedgerReader.read(text: """
            2024-01-01 Opening
                Assets:Broker:Cash   100 EUR
                Assets:Broker        2 VWCE @ 50 EUR
                Equity:Opening

            2024-01-02 Checks
                Assets:Broker   0 EUR =* 100 EUR
                Assets:Broker   0 VWCE == 2 VWCE
                Assets:Broker:Cash   0 EUR == 100 EUR
                Assets:Broker   0 EUR =* 0

            2024-01-03 Wrong on purpose
                Assets:Broker   0 VWCE = 3 VWCE
            """)
        #expect(journal.messages == [
            "10: The balance assertion for Assets:Broker fails: it's 100 EUR, 2 VWCE, the journal says 0.",
            "13: The balance assertion for Assets:Broker fails: it's 2 VWCE, the journal says 3 VWCE.",
        ])
    }

    @Test func aTransactionWithTwoEmptyPostingsIsSkipped() {
        let journal = LedgerReader.read(text: """
            2024-01-01 Two empty
                Assets:Cash
                Equity:Opening

            2024-01-02 Fine
                Assets:Cash   1 EUR
                Equity:Opening

            2024-01-03 Bad amount
                Assets:Cash   1.2.3,4,5 EUR
                Equity:Opening

            2024-01-04 An expression
                Assets:Cash   (2 * 3 EUR)
                Equity:Opening
            """)
        #expect(journal.transactions.map(\.description) == ["Fine"])
        #expect(journal.errors.map(\.location?.line) == [10, 14, 1])
    }

    @Test func anElidedAmountCanHoldSeveralCommodities() {
        let journal = LedgerReader.read(text: """
            2024-01-01 Opening
                Assets:Broker   10 VWCE
                Assets:Bank     100 EUR
                Equity:Opening
            """)
        let postings = journal.transactions[0].postings
        #expect(postings.map(\.account) == ["Assets:Broker", "Assets:Bank", "Equity:Opening", "Equity:Opening"])
        #expect(postings.suffix(2).map(\.amount) == [LedgerAmount(-10, "VWCE"), LedgerAmount(-100, "EUR")])
    }

    // MARK: - Files

    @Test func includesWithWildcards() throws {
        let journal = try LedgerSamples.read("split/main.journal")
        #expect(journal.files.map(\.name) == ["main.journal", "accounts.journal", "2024/01.journal", "2024/02.journal"])
        #expect(journal.files.map(\.transactions) == [0, 0, 1, 2])
        #expect(journal.files[2].includedFrom == LedgerLocation(file: "main.journal", line: 5))
        // The alias in main.journal applies to the files it includes after it.
        #expect(journal.transactions.map(\.description) == [
            "Salary", "Savings, written after February but dated in January", "Salary",
        ])
        #expect(journal.balance("Assets:Bank", "EUR") == 1700)
        #expect(journal.declaredAccounts == ["Assets:Bank", "Assets:Savings"])
        #expect(journal.diagnostics.isEmpty)
    }

    @Test func includeCyclesAreReportedAndReadOnce() throws {
        let journal = try LedgerSamples.read("cycle/a.journal")
        #expect(journal.files.map(\.name) == ["a.journal", "b.journal"])
        #expect(journal.transactions.map(\.description) == ["From a", "From b"])
        #expect(journal.messages == ["1: Include cycle: a.journal → b.journal → a.journal. It was read once."])
        #expect(journal.diagnostics.first?.location?.file == "b.journal")
    }

    @Test func missingIncludesAreListed() throws {
        let journal = try LedgerSamples.read("missing/main.journal")
        #expect(journal.transactions.count == 1)
        #expect(journal.missingIncludes.map(\.path) == ["private.journal", "archive/*.journal"])
        #expect(journal.missingIncludes.map(\.location.line) == [2, 3])
        #expect(journal.missingIncludes[0].url.lastPathComponent == "private.journal")
        #expect(journal.warnings.count == 2)
    }

    @Test func twoFilesGivenAtOnceShareTheirInclude() throws {
        let journal = try LedgerSamples.read("years/2023.journal", "years/2024.journal")
        #expect(journal.files.map(\.name) == ["2023.journal", "common.journal", "2024.journal"])
        #expect(journal.transactions.count == 3)
    }

    @Test func aFileGivenAndIncludedIsReadOnce() throws {
        let journal = try LedgerSamples.read("split/main.journal", "split/2024/01.journal")
        #expect(journal.files.count == 4)
        #expect(journal.transactions.count == 3)
    }

    @Test func aFileThatCantBeReadIsAnError() throws {
        let journal = LedgerReader.read([URL(fileURLWithPath: "/nowhere/nothing.journal")],
                                        files: InMemoryLedgerFiles([:]))
        #expect(journal.transactions.isEmpty)
        #expect(journal.messages == ["nothing.journal can't be read: there's no such file"])
    }

    @Test func recursiveWildcardsInMemory() {
        let files = InMemoryLedgerFiles([
            "/books/2023/q1/jan.journal": "2023-01-01 A\n    Assets:Cash  1 EUR\n    Equity:Opening\n",
            "/books/2023/feb.journal": "2023-02-01 B\n    Assets:Cash  1 EUR\n    Equity:Opening\n",
            "/books/2023/feb.csv": "not a journal",
        ])
        let journal = LedgerReader.read(text: "include 2023/**/*.journal\n", path: "/books/main.journal", files: files)
        #expect(journal.files.map(\.name) == ["main.journal", "2023/feb.journal", "2023/q1/jan.journal"])
        #expect(journal.transactions.map(\.description) == ["A", "B"])
    }

    @Test func wildcardMatching() {
        #expect(LedgerLoader.matches("2024.journal", "*.journal"))
        #expect(LedgerLoader.matches("01.journal", "0?.journal"))
        #expect(LedgerLoader.matches("q3.journal", "q[1-4].journal"))
        #expect(!LedgerLoader.matches("q5.journal", "q[1-4].journal"))
        #expect(LedgerLoader.matches("b.ledger", "[!a]*"))
        #expect(!LedgerLoader.matches("notes.txt", "*.journal"))
    }
}
