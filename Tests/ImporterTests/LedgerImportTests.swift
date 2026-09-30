import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// From a journal to library records: mapping, snapshots, flows, costs, prices.
struct LedgerImportTests {
    /// A library with no accounts, in euros.
    private static func emptyLibrary() -> Library {
        Library(settings: LibrarySettings(baseCurrency: .eur))
    }

    private static func personal() throws -> LedgerJournal {
        try LedgerSamples.read("personal/main.journal")
    }

    private static func valuation(_ preview: LedgerImportPreview, _ account: AccountID,
                                  _ day: String) -> ImportedRecord? {
        preview.preview.records.first { $0.imported.key == .valuation(account, date(day)) }?.imported
    }

    private static func dates(_ preview: LedgerImportPreview, _ account: AccountID) -> [String] {
        preview.preview.records.compactMap { record in
            record.imported.key.account == account ? record.imported.key.date.description : nil
        }
    }

    // MARK: - Mapping

    @Test func theJournalReadsCleanly() throws {
        let journal = try Self.personal()
        #expect(journal.diagnostics.isEmpty, "\(journal.messages)")
        #expect(journal.files.map(\.name) == ["main.journal", "2024/01.journal", "2024/02.journal",
                                              "2024/03.journal", "2024/04.journal", "prices.journal"])
        #expect(journal.transactions.count == 20)
    }

    @Test func accountsAreGroupedAndProposed() throws {
        let session = LedgerImportSession(journal: try Self.personal())
        let preview = session.preview(against: Self.emptyLibrary())
        let heads = preview.accounts.filter(\.isGroupHead).map(\.name)
        #expect(heads == ["Assets:Bank:Fineco", "Assets:Bank:OldBank", "Assets:Bank:Wise", "Assets:Broker:Directa",
                          "Assets:Crypto:Wallet", "Liabilities:CreditCard:Visa"])
        #expect(preview.account("Assets:Broker:Directa:Cash")?.mapping == .account("directa"))
        #expect(preview.account("Assets:Broker:Directa:Cash")?.source == .new)
        #expect(preview.account("Assets:Bank")?.mapping == .split)
        #expect(preview.account("Assets")?.mapping == .split)
        #expect(preview.account("Equity:Opening balances")?.role == .equity)
        #expect(preview.account("Equity:Opening balances")?.mapping == .flow)

        let accounts = preview.preview.newAccounts.map(\.account)
        #expect(accounts.map(\.id) == ["crypto-wallet", "directa", "fineco", "old-bank", "visa", "wise"])
        #expect(accounts.map(\.name) == ["Crypto Wallet", "Directa", "Fineco", "Old Bank", "Visa", "Wise"])
        #expect(accounts.map(\.kind) == [.crypto, .brokerage, .cash, .cash, .creditCard, .cash])
        #expect(accounts.map(\.currency) == [.eur, .eur, .eur, .eur, .eur, .usd])
        #expect(accounts.map(\.opened) == [date("2024-02-10"), date("2024-01-01"), date("2024-01-01"),
                                           date("2024-01-01"), date("2024-01-25"), date("2024-03-05")])
        #expect(preview.preview.newAccounts.first { $0.account.id == "directa" }?.names == ["Assets:Broker:Directa"])
    }

    @Test func returnsAccountsByName() throws {
        let preview = LedgerImportSession(journal: try Self.personal()).preview(against: Self.emptyLibrary())
        let returns = preview.accounts.filter { $0.mapping == .returns }.map(\.name)
        #expect(returns == ["Expenses:Fees", "Expenses:Fees:Broker", "Income:Capital gains", "Income:Dividends",
                            "Income:Interest", "Income:Staking"])
        #expect(preview.account("Income:Salary")?.mapping == .flow)
        #expect(preview.account("Expenses:Food")?.mapping == .flow)
    }

    @Test func commoditiesAreCurrenciesOrInstruments() throws {
        let preview = LedgerImportSession(journal: try Self.personal()).preview(against: Self.emptyLibrary())
        #expect(preview.commodities.map(\.symbol) == ["BTC", "EUR", "USD", "VWCE.MI"])
        #expect(preview.commodity("EUR")?.mapping == .currency(.eur))
        #expect(preview.commodity("USD")?.mapping == .currency(.usd))
        #expect(preview.commodity("VWCE.MI")?.prices == 5)
        let instruments = preview.preview.newInstruments.map(\.instrument)
        #expect(instruments.map(\.id) == ["btc", "vwce"])
        let btc = instruments[0], vwce = instruments[1]
        #expect(btc.kind == .crypto)
        #expect(btc.unit == "BTC")
        #expect(btc.currency == .eur)
        #expect(btc.priceSource == PriceSource(provider: .coingecko, symbol: "BTC"))
        #expect(vwce.kind == .etf)
        #expect(vwce.ticker == "VWCE")
        #expect(vwce.priceSource == PriceSource(provider: .yahoo, symbol: "VWCE.MI"))
        #expect(vwce.assetClasses == .single(.equity))
    }

    @Test func commoditiesMatchTheLibrarysInstruments() throws {
        let library = try Fixtures.exampleLibrary()
        let preview = LedgerImportSession(journal: try Self.personal()).preview(against: library)
        #expect(preview.commodity("VWCE.MI")?.mapping == .instrument("vwce"))
        #expect(preview.commodity("VWCE.MI")?.source == .matched)
        #expect(preview.commodity("BTC")?.mapping == .instrument("btc"))
        #expect(preview.preview.newInstruments.isEmpty)
    }

    @Test func accountsMatchTheLibrarysByName() throws {
        let library = try Fixtures.exampleLibrary()
        let preview = LedgerImportSession(journal: try Self.personal()).preview(against: library)
        #expect(preview.account("Assets:Bank:Fineco")?.mapping == .account("conto-fineco"))
        #expect(preview.account("Assets:Bank:Fineco")?.source == .matched)
        #expect(preview.account("Assets:Broker:Directa")?.mapping == .account("directa"))
        #expect(preview.account("Assets:Bank:OldBank")?.mapping == .account("old-bank"))
        #expect(preview.preview.newAccounts.map(\.account.id) == ["crypto-wallet", "visa", "wise"])
        #expect(preview.preview.nameMatches.contains(
            NameMatch(name: "Assets:Bank:Fineco", account: "conto-fineco", method: .existing)))
    }

    @Test func localisedRootsAndDeclaredTypes() {
        let journal = LedgerReader.read(text: """
            account Personale:Contanti   ; type: A
            2024-01-01 Apertura
                Attività:Banca:Intesa     100 EUR
                Passività:Mutuo          -50 EUR
                Personale:Contanti         5 EUR
                Patrimonio:Apertura
            """)
        let preview = LedgerImportSession(journal: journal).preview(against: Self.emptyLibrary())
        #expect(preview.account("Attività:Banca:Intesa")?.role == .asset)
        #expect(preview.account("Passività:Mutuo")?.role == .liability)
        #expect(preview.account("Personale:Contanti")?.role == .asset)
        #expect(preview.account("Patrimonio:Apertura")?.role == .equity)
        let kinds = Dictionary(uniqueKeysWithValues: preview.preview.newAccounts.map { ($0.account.id, $0.account.kind) })
        #expect(kinds == ["intesa": .cash, "mutuo": .mortgage, "contanti": .cash])
    }

    // MARK: - Snapshots

    @Test func monthEndSnapshots() throws {
        let preview = LedgerImportSession(journal: try Self.personal()).preview(against: Self.emptyLibrary())
        #expect(Self.dates(preview, "fineco") == ["2024-01-31", "2024-02-29", "2024-03-31", "2024-04-30"])
        #expect(Self.dates(preview, "crypto-wallet") == ["2024-02-29", "2024-03-31", "2024-04-30"])
        #expect(Self.dates(preview, "wise") == ["2024-03-31", "2024-04-30"])
        let balances = ["2024-01-31", "2024-02-29", "2024-03-31", "2024-04-30"].map {
            Self.valuation(preview, "fineco", $0)?.balance
        }
        #expect(balances == [dec("5880"), dec("6681.2"), dec("8465.2"), dec("10905.2")])
        #expect(Self.valuation(preview, "visa", "2024-02-29")?.balance == -60, "a debt stays negative")
        #expect(Self.valuation(preview, "wise", "2024-03-31")?.balance == 300)
        let fineco = try #require(Self.valuation(preview, "fineco", "2024-01-31"))
        #expect(fineco.source == .ledger)
        #expect(fineco.positions.isEmpty && fineco.cash == nil)
    }

    @Test func quarterAndActivitySnapshots() throws {
        var session = LedgerImportSession(journal: try Self.personal())
        session.setFrequency(.quarter)
        var preview = session.preview(against: Self.emptyLibrary())
        #expect(Self.dates(preview, "fineco") == ["2024-03-31", "2024-06-30"])
        #expect(Self.valuation(preview, "fineco", "2024-03-31")?.flow == 8464, "without the interest")
        session.setFrequency(.activity)
        preview = session.preview(against: Self.emptyLibrary())
        #expect(Self.dates(preview, "visa") == ["2024-01-25", "2024-01-31", "2024-02-25", "2024-04-10"])
        #expect(Self.valuation(preview, "visa", "2024-01-25")?.flow == -120)
    }

    @Test func snapshotsStopAtUntil() throws {
        let preview = LedgerImportSession(journal: try Self.personal())
            .preview(against: Self.emptyLibrary(), until: date("2024-03-15"))
        #expect(Self.dates(preview, "fineco") == ["2024-01-31", "2024-02-29"])
        #expect(!preview.preview.records.contains { $0.imported.key.date > date("2024-03-15") })
    }

    @Test func holdingsWithAverageCostAfterAPartialSale() throws {
        let preview = LedgerImportSession(journal: try Self.personal()).preview(against: Self.emptyLibrary())
        let january = try #require(Self.valuation(preview, "directa", "2024-01-31"))
        #expect(january.cash == 498)
        #expect(january.positions == [ImportedPosition(instrument: "vwce", quantity: 20, costBasis: 2000)])
        let february = try #require(Self.valuation(preview, "directa", "2024-02-29"))
        #expect(february.cash == 1063)
        #expect(february.positions == [ImportedPosition(instrument: "vwce", quantity: 15, costBasis: 1500)])
        let wallet = try #require(Self.valuation(preview, "crypto-wallet", "2024-04-30"))
        #expect(wallet.cash == nil, "the wallet never held cash")
        // Staking rewards cost their market value when received: 0.0001 × 58,500.
        #expect(wallet.positions == [ImportedPosition(instrument: "btc", quantity: dec("0.0501"),
                                                      costBasis: dec("2005.85"))])
    }

    @Test func averageCostThroughBuysAndSales() {
        let journal = LedgerReader.read(text: """
            2024-01-02 Buy
                Assets:Broker   10 ETF @ 10 EUR
                Assets:Bank
            2024-01-03 Buy more, dearer
                Assets:Broker   10 ETF @@ 300 EUR
                Assets:Bank
            2024-01-04 Sell a quarter
                Assets:Broker   -5 ETF @ 25 EUR
                Assets:Bank
            2024-01-05 Sell everything
                Assets:Broker   -15 ETF @ 26 EUR
                Assets:Bank
            2024-01-06 Buy again
                Assets:Broker   2 ETF {30 EUR}
                Assets:Bank
            """)
        var session = LedgerImportSession(journal: journal)
        session.setFrequency(.activity)
        let preview = session.preview(against: Self.emptyLibrary())
        let costs = ["2024-01-02", "2024-01-03", "2024-01-04", "2024-01-05", "2024-01-06"].map {
            Self.valuation(preview, "broker", $0)?.positions.first?.costBasis
        }
        #expect(costs == [100, 400, 300, nil, 60])
        #expect(Self.valuation(preview, "broker", "2024-01-05")?.positions == [])
    }

    @Test func anAccountThatStaysEmptyIsProposedToClose() throws {
        let preview = LedgerImportSession(journal: try Self.personal()).preview(against: Self.emptyLibrary())
        #expect(Self.dates(preview, "old-bank") == ["2024-01-31", "2024-02-12"])
        let closing = try #require(Self.valuation(preview, "old-bank", "2024-02-12"))
        #expect(closing.balance == 0)
        #expect(closing.flow == -300)
        // The card is paid off on April 10, too recently to be closed.
        #expect(preview.preview.accountChanges == [AccountChangeProposal(account: "old-bank",
                                                                         change: .close(on: date("2024-02-12")))])
        #expect(Self.valuation(preview, "visa", "2024-04-30")?.balance == 0)
    }

    // MARK: - Flows

    @Test func flowsFollowTheCounterparts() throws {
        let preview = LedgerImportSession(journal: try Self.personal()).preview(against: Self.emptyLibrary())
        func flows(_ account: AccountID) -> [Decimal?] {
            preview.preview.records.filter { $0.imported.key.account == account }.map(\.imported.flow)
        }
        // Opening, salary, to the broker, card: all money in or out. February: bitcoin bought
        // (-2000), the old bank closed (+300), salary (+2500); the interest (1.20) is a return.
        #expect(flows("fineco") == [dec("5880"), 800, 1784, 2440])
        // The opening and the transfer are flows; buying VWCE and paying the fee are not;
        // the dividend and the gain on the sale are returns.
        #expect(flows("directa") == [2500, 0, 0, 0])
        // Bought from a tracked account at its cost; the staking reward is a return.
        #expect(flows("crypto-wallet") == [2000, 0, 0])
        // Groceries out, paid off by the bank: nothing net in January.
        #expect(flows("visa") == [0, -60, 0, 60])
        // Dollars: the invoice in, 200 sent home, in the account's own currency.
        #expect(flows("wise") == [300, 0])
        #expect(flows("old-bank") == [300, -300])
        #expect(preview.notes.isEmpty, "\(preview.notes)")
    }

    @Test func marketChangeIsWhatFlowsDontExplain() throws {
        let preview = LedgerImportSession(journal: try Self.personal()).preview(against: Self.emptyLibrary())
        let january = try #require(Self.valuation(preview, "fineco", "2024-01-31")?.balance)
        let february = try #require(Self.valuation(preview, "fineco", "2024-02-29"))
        #expect(february.balance! - january - february.flow! == dec("1.2"), "the interest")
    }

    @Test func returnsCanBeMarkedByHand() throws {
        var session = LedgerImportSession(journal: try Self.personal())
        session.setReturns(false, for: "Income:Dividends")
        session.setReturns(true, for: "Income:Freelance")
        let preview = session.preview(against: Self.emptyLibrary())
        #expect(preview.account("Income:Dividends")?.mapping == .flow)
        #expect(preview.account("Income:Dividends")?.source == .explicit)
        #expect(Self.valuation(preview, "directa", "2024-02-29")?.flow == 15)
        #expect(Self.valuation(preview, "wise", "2024-03-31")?.flow == -200)
    }

    @Test func movingToAnIgnoredAccountIsAFlow() throws {
        var session = LedgerImportSession(journal: try Self.personal())
        session.ignore(account: "Assets:Crypto")
        let preview = session.preview(against: Self.emptyLibrary())
        #expect(preview.account("Assets:Crypto:Wallet")?.mapping == .ignored)
        #expect(preview.account("Assets:Crypto:Wallet")?.source == .inherited(from: "Assets:Crypto"))
        #expect(Self.dates(preview, "crypto-wallet").isEmpty)
        #expect(Self.valuation(preview, "fineco", "2024-02-29")?.flow == 800)
        #expect(preview.commodity("BTC") == nil)
    }

    @Test func aSubtreeCanGoToAnotherAccount() throws {
        var session = LedgerImportSession(journal: try Self.personal())
        session.map(account: "Assets:Broker:Directa:Cash", to: "fineco")
        let preview = session.preview(against: Self.emptyLibrary())
        #expect(preview.account("Assets:Broker:Directa:Cash")?.mapping == .account("fineco"))
        #expect(preview.account("Assets:Broker:Directa")?.mapping == .account("directa"))
        // Buying VWCE now moves money between two accounts: a flow for both.
        #expect(Self.valuation(preview, "directa", "2024-01-31")?.flow == 2000)
        #expect(Self.valuation(preview, "directa", "2024-01-31")?.cash == nil)
    }

    @Test func aTransferInKindWithoutAPriceLeavesTheFlowUnknown() {
        let journal = LedgerReader.read(text: """
            2024-01-10 Coins arrive from a friend's wallet
                Assets:Wallet     1 ZZZ
                Equity:Gifts
            2024-01-20 Some price
                Assets:Wallet     1 ZZZ @ 5 EUR
                Assets:Bank      -5 EUR
            """)
        let preview = LedgerImportSession(journal: journal).preview(against: Self.emptyLibrary())
        #expect(Self.valuation(preview, "wallet", "2024-01-31")?.flow == nil)
        #expect(Self.valuation(preview, "wallet", "2024-01-31")?.positions
            == [ImportedPosition(instrument: "zzz", quantity: 2, costBasis: nil)])
        #expect(preview.notes.map(\.location?.line) == [1])
        #expect(preview.notes.first?.message.hasPrefix("1 ZZZ in Assets:Wallet can't be valued in EUR on 2024-01-10") == true)
    }

    @Test func foreignCashIsConvertedAtTheJournalsRates() {
        let journal = LedgerReader.read(text: """
            P 2024-01-01 USD 0.90 EUR
            2024-01-05 Dollars in a euro account
                Assets:Broker:Cash   100 USD
                Assets:Broker        1 ABC @ 10 EUR
                Income:Gift         -100 USD
                Assets:Bank         -10 EUR
            P 2024-01-31 EUR 1.25 USD
            """)
        let preview = LedgerImportSession(journal: journal).preview(against: Self.emptyLibrary())
        let broker = Self.valuation(preview, "broker", "2024-01-31")
        #expect(broker?.cash == 80, "100 USD at the inverse of 1.25")
        #expect(broker?.flow == 100, "the gift at 0.90, plus 10 from the bank")
    }

    @Test func commonIdioms() {
        // Lowercase hledger accounts, amounts without a commodity, a purchase in dollars for a euro
        // account, and a sale whose price is inferred from the cash it brought.
        let journal = LedgerReader.read(text: """
            P 2024-01-01 USD 0.90 EUR
            2024-01-02 opening
                assets:bank:checking      1000
                equity:opening
            2024-01-03 buy in dollars
                assets:broker             10 AAPL @ 150 USD
                income:gift              -1500 USD
            2024-01-03 dollars in the wallet
                assets:wallet             $20
                income:gift
            2024-01-04 sell some, price inferred
                assets:broker             -4 AAPL
                assets:broker:cash         680 USD
            """)
        #expect(journal.errors.isEmpty, "\(journal.messages)")
        var library = Self.emptyLibrary()
        library.accounts["broker"] = Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur,
                                             opened: "2020-01-01")
        let preview = LedgerImportSession(journal: journal).preview(against: library)
        #expect(preview.account("assets:bank:checking")?.role == .asset)
        #expect(Self.valuation(preview, "bank-checking", "2024-01-31")?.balance == 1000,
                "no commodity: the base currency")
        let broker = Self.valuation(preview, "broker", "2024-01-31")
        // The purchase cost 1,500 dollars, 1,350 euros; six of ten shares remain.
        #expect(broker?.positions == [ImportedPosition(instrument: "aapl", quantity: 6, costBasis: 810)])
        #expect(broker?.cash == 612, "680 dollars at 0.90")
        #expect(broker?.flow == 1350, "the gift, in euros")
        #expect(preview.commodity("$")?.mapping == .currency(.usd))
        #expect(preview.preview.newAccounts.first { $0.account.id == "wallet" }?.account.currency == .usd)
        #expect(Self.valuation(preview, "wallet", "2024-01-31")?.balance == 20)
    }

    // MARK: - Prices

    @Test func pricesAndExchangeRates() throws {
        let preview = LedgerImportSession(journal: try Self.personal()).preview(against: Self.emptyLibrary())
        let prices = preview.preview.records.filter { $0.imported.key.instrument == "vwce" }
        #expect(prices.map(\.imported.key.date.description) == [
            "2023-12-29", "2024-01-22", "2024-01-31", "2024-02-20", "2024-02-29", "2024-03-28", "2024-04-30",
        ])
        #expect(prices.map(\.imported.price) == [100, 100, dec("102.5"), 110, 108, dec("111.2"), dec("109.9")])
        #expect(prices.allSatisfy { $0.imported.currency == .eur && $0.imported.source == .ledger })
        let btc = preview.preview.records.filter { $0.imported.key.instrument == "btc" }
        #expect(btc.map(\.imported.price) == [40000, 56000, 62000, 58500])
        let fx = preview.preview.records.filter { if case .fx = $0.imported.key { true } else { false } }
        #expect(fx.map(\.imported.key) == [.fx(FXKey(base: .usd, quote: .eur, date: date("2024-04-30")))])
        #expect(fx.first?.imported.rate == dec("0.935"))
    }

    @Test func aPriceDirectiveWinsOverATransactionPriceOnTheSameDay() {
        let journal = LedgerReader.read(text: """
            2024-01-10 Buy
                Assets:Broker   1 ABC @ 10 EUR
                Assets:Bank
            P 2024-01-10 ABC 11 EUR
            2024-01-11 Buy
                Assets:Broker   1 ABC @ 12 EUR
                Assets:Bank
            """)
        var session = LedgerImportSession(journal: journal)
        var prices = session.preview(against: Self.emptyLibrary()).preview.records.compactMap(\.imported.price)
        #expect(prices == [11, 12])
        session.setTransactionPrices(false)
        prices = session.preview(against: Self.emptyLibrary()).preview.records.compactMap(\.imported.price)
        #expect(prices == [11])
    }

    // MARK: - Applying

    @Test func importingTheSameJournalAgainChangesNothing() throws {
        let journal = try Self.personal()
        let session = LedgerImportSession(journal: journal)
        let first = session.preview(against: Self.emptyLibrary())
        #expect(first.preview.summary.newRecords == first.preview.records.count)
        let result = first.preview.apply(to: Self.emptyLibrary())
        #expect(result.createdAccounts.count == 6)
        #expect(result.closedAccounts == ["old-bank"])
        #expect(result.library.accounts["old-bank"]?.closed == date("2024-02-12"))
        #expect(result.library.valuations(for: "fineco").first?.flow == dec("5880"))
        #expect(result.library.valuations(for: "fineco").first?.source == .ledger)

        let again = session.preview(against: result.library)
        #expect(again.preview.records.allSatisfy { $0.status == .identical })
        #expect(again.preview.newAccounts.isEmpty && again.preview.newInstruments.isEmpty)
        #expect(again.preview.accountChanges.isEmpty)
        let second = again.preview.apply(to: result.library)
        #expect(!second.hasChanges)
        #expect(second.library == result.library)
    }

    @Test func declinedNewAccountsAreLeftOutNextTime() throws {
        let session = LedgerImportSession(journal: try Self.personal())
        let proposed = session.preview(against: Self.emptyLibrary())
        var decided = proposed
        decided.preview.newAccounts = decided.preview.newAccounts.map { proposal in
            var proposal = proposal
            proposal.isAccepted = proposal.account.id != "wise"
            return proposal
        }
        let result = decided.preview.apply(to: Self.emptyLibrary())
        #expect(result.library.accounts["wise"] == nil)
        let profile = session.makeProfile(id: "journal", name: "Journal", from: decided, library: result.library)
        #expect(profile.ledger?.ignore == ["Assets:Bank:Wise"])
        #expect(profile.matches.accounts["Assets:Bank:Wise"] == nil)
        #expect(profile.matches.accounts["Assets:Bank:Fineco"] == "fineco")

        // The next import with the profile leaves it out instead of proposing it again.
        let next = LedgerImportSession(journal: try Self.personal(), profile: profile).preview(against: result.library)
        #expect(next.preview.newAccounts.isEmpty)
        #expect(next.account("Assets:Bank:Wise")?.mapping == .ignored)

        // Without decisions (all accepted), nothing is ignored.
        let undecided = session.makeProfile(id: "journal", name: "Journal", from: proposed, library: result.library)
        #expect(undecided.ledger?.ignore == [])

        // A new account chosen by hand and then declined is left out too.
        var chosen = session
        chosen.map(account: "Assets:Bank:Wise", to: "wise-usd")
        var declined = chosen.preview(against: Self.emptyLibrary())
        declined.preview.newAccounts = declined.preview.newAccounts.map { proposal in
            var proposal = proposal
            proposal.isAccepted = proposal.account.id != "wise-usd"
            return proposal
        }
        let again = chosen.makeProfile(id: "journal", name: "Journal", from: declined, library: result.library)
        #expect(again.ledger?.ignore == ["Assets:Bank:Wise"])
        #expect(again.matches.accounts["Assets:Bank:Wise"] == nil)
    }

    @Test func aJournalsValuationsKeepTheirFlows() throws {
        // Every valuation the journal gives, with or without a flow, is left
        // alone when the flows after inserted values are worked out again.
        let preview = LedgerImportSession(journal: try Self.personal()).preview(against: Self.emptyLibrary()).preview
        let keys = Set(preview.records.compactMap { record -> ValuationKey? in
            if case .valuation(let key) = record.imported.key { key } else { nil }
        })
        #expect(!keys.isEmpty)
        #expect(preview.apply(to: Self.emptyLibrary()).fixedFlows == keys)
        #expect(preview.apply(to: Self.emptyLibrary()).recomputedFlows.isEmpty)
    }

    @Test func aFlowTheLibraryLacksIsFilledInAndADifferentOneConflicts() throws {
        let journal = try Self.personal()
        let session = LedgerImportSession(journal: journal)
        var library = session.preview(against: Self.emptyLibrary()).preview.apply(to: Self.emptyLibrary()).library
        library.upsert(Valuation(account: "fineco", date: "2024-01-31", balance: 5880))
        library.upsert(Valuation(account: "fineco", date: "2024-02-29", balance: dec("6681.2"), flow: 900))
        let preview = session.preview(against: library).preview
        #expect(preview.record(.valuation("fineco", "2024-01-31"))?.status == .updated)
        #expect(preview.record(.valuation("fineco", "2024-02-29"))?.status == .conflict)
    }

    @Test func endToEndIntoTheExampleLibrary() throws {
        let library = try Fixtures.exampleLibrary()
        var session = LedgerImportSession(journal: try Self.personal())
        session.map(account: "Assets:Crypto:Wallet", to: "ledger-wallet")
        session.ignore(account: "Assets:Bank:OldBank")
        let ledgerPreview = session.preview(against: library, until: date("2026-09-30"))
        var preview = ledgerPreview.preview
        #expect(preview.newAccounts.map(\.account.id) == ["visa", "wise"])
        #expect(preview.newInstruments.isEmpty)
        #expect(preview.accountChanges == [AccountChangeProposal(account: "conto-fineco",
                                                                 change: .openEarlier(on: date("2024-01-01")))])
        preview.resolveConflicts(.keep)
        let result = preview.apply(to: library)
        #expect(result.createdAccounts == ["visa", "wise"])
        #expect(result.library.accounts["conto-fineco"]?.opened == date("2024-01-01"))
        #expect(result.changedMonths == ["2023-12", "2024-01", "2024-02", "2024-03", "2024-04"])
        let wallet = try #require(result.library.valuations(for: "ledger-wallet").first { $0.date == "2024-04-30" })
        #expect(wallet.positions == [Position(instrument: "btc", quantity: dec("0.0501"), costBasis: dec("2005.85"))])
        // Directa records trades: the journal's become its trades, and it gets no valuations.
        #expect(ledgerPreview.tradesAccounts(in: library) == ["directa"])
        let trades = result.library.trades(for: "directa").filter { $0.source == .ledger }.inProcessingOrder()
        #expect(trades.map(\.type) == [.deposit, .deposit, .buy, .dividend, .sell])
        #expect(trades.map(\.date) == ["2024-01-01", "2024-01-20", "2024-01-22", "2024-02-05", "2024-02-20"])
        #expect(result.library.valuations(for: "directa").filter { $0.date < "2025-01-01" }.isEmpty)
        #expect(result.library.prices(for: "vwce").contains {
            $0.date == "2024-04-30" && $0.price == dec("109.9") && $0.source == .ledger
        })
        // The library's own history from 2025 on is untouched.
        #expect(result.library.valuations(for: "directa").filter { $0.date >= "2025-01-01" }
            == library.valuations(for: "directa").filter { $0.date >= "2025-01-01" })

        let profile = session.makeProfile(id: "journal", name: "My journal", from: ledgerPreview,
                                          library: result.library)
        #expect(profile.layout == .ledger)
        #expect(profile.matches.accounts == [
            "Assets:Bank:Fineco": "conto-fineco", "Assets:Bank:Wise": "wise", "Assets:Broker:Directa": "directa",
            "Assets:Crypto:Wallet": "ledger-wallet", "Liabilities:CreditCard:Visa": "visa",
        ])
        #expect(profile.matches.instruments == ["BTC": "btc", "VWCE.MI": "vwce"])
        #expect(profile.ledger?.ignore == ["Assets:Bank:OldBank"])
        #expect(profile.ledger?.returns == ["Expenses:Fees", "Income:Capital gains", "Income:Dividends",
                                            "Income:Interest", "Income:Staking"])

        // Next month, the same journal with the saved profile adds nothing.
        let next = LedgerImportSession(journal: try Self.personal(), profile: profile)
            .preview(against: result.library, until: date("2026-09-30"))
        #expect(next.preview.records.allSatisfy { $0.status == .identical })
        #expect(next.preview.newAccounts.isEmpty)
        #expect(!next.preview.apply(to: result.library).hasChanges)
    }
}
