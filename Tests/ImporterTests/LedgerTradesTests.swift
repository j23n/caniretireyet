import Foundation
@testable import Importer
import Model
import Testing
import TestSupport
import Tracker

/// Journals into accounts that record trades: the personal sample journal's
/// broker and crypto wallet become trades instead of month-end positions.
struct LedgerTradesTests {
    /// Directa and the crypto wallet record trades; the rest of the journal
    /// becomes new accounts with snapshots, as usual.
    private static func library() -> Library {
        Library(
            settings: LibrarySettings(baseCurrency: .eur),
            accounts: [
                Account(id: "directa", name: "Directa", kind: .brokerage, currency: .eur, opened: "2024-01-01",
                        valuation: .trades),
                Account(id: "crypto-wallet", name: "Crypto Wallet", kind: .crypto, currency: .eur,
                        opened: "2024-02-10", valuation: .trades),
            ],
            instruments: [
                Instrument(id: "vwce", name: "Vanguard FTSE All-World", kind: .etf, currency: .eur, unit: .share,
                           assetClasses: .single(.equity), ticker: "VWCE"),
                Instrument(id: "btc", name: "Bitcoin", kind: .crypto, currency: .eur, unit: "BTC",
                           assetClasses: .single(.crypto), ticker: "BTC"),
            ])
    }

    private static func session() throws -> LedgerImportSession {
        LedgerImportSession(journal: try LedgerSamples.read("personal/main.journal"))
    }

    /// An account's trades in the order they apply (a day's deposit before its buy).
    private static func trades(_ preview: LedgerImportPreview, _ account: AccountID) -> [Trade] {
        preview.preview.records.compactMap(\.imported.trade).filter { $0.account == account }.inProcessingOrder()
    }

    @Test func aTradesAccountGetsTradesInsteadOfPositions() throws {
        let preview = try Self.session().preview(against: Self.library(), until: "2026-09-30")
        #expect(preview.account("Assets:Broker:Directa")?.mapping == .account("directa"))
        #expect(preview.account("Assets:Crypto:Wallet")?.mapping == .account("crypto-wallet"))
        let directa = Self.trades(preview, "directa")
        #expect(directa.map(\.type) == [.deposit, .deposit, .buy, .dividend, .sell])
        #expect(directa.map(\.date) == ["2024-01-01", "2024-01-20", "2024-01-22", "2024-02-05", "2024-02-20"])
        #expect(directa.allSatisfy { $0.source == .ledger })
        // The buy at its @ price, with the fee of the same transaction; its amount is what they give.
        let buy = directa[2]
        #expect(buy == Trade(account: "directa", date: "2024-01-22", id: buy.id, type: .buy, instrument: "vwce",
                             quantity: 20, price: 100, fees: 2, note: "Buy VWCE", source: .ledger))
        // The sale at its @ price, not its lot cost; the capital gain is worked out, not recorded.
        let sell = directa[4]
        #expect(sell.quantity == 5)
        #expect(sell.price == 110)
        #expect(sell.amount == nil)
        #expect(directa[3].amount == 15)
        #expect(directa.prefix(2).map(\.amount) == [1000, 1500])
        // No month-end valuations for trades accounts; the others keep theirs.
        let valuations = preview.preview.records.compactMap { $0.imported.key.isTrade ? nil : $0.imported.key.account }
        #expect(!valuations.contains("directa"))
        #expect(!valuations.contains("crypto-wallet"))
        #expect(valuations.contains("fineco"))
    }

    @Test func rewardsAreBoughtWithTheIncomeTheyAre() throws {
        let preview = try Self.session().preview(against: Self.library(), until: "2026-09-30")
        let wallet = Self.trades(preview, "crypto-wallet")
        #expect(wallet.map(\.type) == [.deposit, .buy, .buy, .interest])
        // Bought with @@: the price per unit, paid from the bank (a deposit).
        #expect(wallet[0].amount == 2000)
        #expect(wallet[1].quantity == dec("0.05"))
        #expect(wallet[1].price == 40000)
        #expect(wallet[1].amount == nil)
        // Staking: bought at the day's P price with the income it is.
        #expect(wallet[2].quantity == dec("0.0001"))
        #expect(wallet[2].price == 58500)
        #expect(wallet[3].amount == dec("5.85"))
        #expect(wallet[3].instrument == nil)
    }

    @Test func averageCostAndCashMatchTheJournal() throws {
        let library = Self.library()
        let session = try Self.session()
        let preview = session.preview(against: library, until: "2026-09-30")
        let imported = preview.preview.apply(to: library).library
        let valuator = Valuator(library: imported)
        #expect(valuator.tradeIssues().filter { $0.severity == .error }.isEmpty)

        // The same journal into accounts with snapshots, for the journal's own costs.
        let snapshots = session.preview(against: Library(settings: LibrarySettings(baseCurrency: .eur)),
                                        until: "2026-09-30")
        func position(_ account: AccountID, _ instrument: InstrumentID, _ day: String) -> ImportedPosition? {
            snapshots.preview.records.first { $0.imported.key == .valuation(account, date(day)) }?
                .imported.positions.first { $0.instrument == instrument }
        }

        // Directa: 20 bought at 100 with a fee of 2, 5 sold. The journal's cost is 1,500
        // for the 15 left; the trades add the fee to the cost (costo medio ponderato):
        // 2,002 × 15/20.
        let ledger = try #require(valuator.ledger(for: "directa"))
        let vwce = try #require(ledger.position(of: "vwce", on: "2024-02-29"))
        let journal = try #require(position("directa", "vwce", "2024-02-29"))
        #expect(vwce.quantity == journal.quantity)
        #expect(journal.costBasis == 1500)
        #expect(vwce.costBasis == dec("1501.5"))
        #expect(vwce.costBasis == journal.costBasis.map { $0 + 2 * 15 / 20 })
        #expect(ledger.entries.first { $0.type == .sell }?.realizedGain == dec("49.5"))
        // The cash the trades give is the journal's.
        let journalCash = snapshots.preview.records.first { $0.imported.key == .valuation("directa", date("2024-02-29")) }?
            .imported.cash
        #expect(valuator.tradeCash(of: "directa", on: "2024-02-29") == journalCash)
        #expect(journalCash == 1063)

        // The wallet: no fees, so the costs are the journal's exactly, the reward at its value.
        let btc = try #require(valuator.ledger(for: "crypto-wallet")?.position(of: "btc", on: "2024-04-30"))
        let journalBTC = try #require(position("crypto-wallet", "btc", "2024-04-30"))
        #expect(btc.quantity == dec("0.0501"))
        #expect(btc.quantity == journalBTC.quantity)
        #expect(btc.costBasis == journalBTC.costBasis)
        #expect(btc.costBasis == dec("2005.85"))
        #expect(valuator.tradeCash(of: "crypto-wallet", on: "2024-04-30") == 0)

        // Deposits are the money added; dividends, fees and the reward are the return.
        let summary = valuator.tradeSummary(for: 2024) { $0.id == "directa" }
        #expect(summary.deposits == 2500)
        #expect(summary.dividends == 15)
        #expect(summary.fees == 2)
    }

    @Test func importingTheJournalAgainChangesNothing() throws {
        let library = Self.library()
        let session = try Self.session()
        var preview = session.preview(against: library, until: "2026-09-30").preview
        #expect(preview.summary.trades == 9)
        let first = preview.apply(to: library)
        #expect(first.tradesWritten == 9)
        let again = session.preview(against: first.library, until: "2026-09-30").preview
        #expect(again.records.allSatisfy { $0.status == .identical })
        #expect(again.summary.identicalRecords == preview.records.count)
        #expect(!again.apply(to: first.library).hasChanges)
        // A trade edited by hand is kept, and the journal's value is a conflict.
        var edited = first.library
        var dividend = try #require(edited.trades(for: "directa").first { $0.type == .dividend })
        dividend.amount = 16
        edited.upsert(dividend)
        preview = session.preview(against: edited, until: "2026-09-30").preview
        #expect(preview.conflicts.map(\.imported.key) == [.trade(dividend.key)])
        #expect(preview.apply(to: edited).library.trade(dividend.key)?.amount == 16)
    }

    @Test func cashChecksAreWrittenWhenAsked() throws {
        var session = try Self.session()
        session.settings.cashChecks = true
        let preview = session.preview(against: Self.library(), until: "2026-09-30")
        let directa = preview.preview.records.filter {
            if case .valuation(let key) = $0.imported.key { key.account == "directa" } else { false }
        }.map(\.imported)
        #expect(directa.map(\.key.date) == ["2024-01-31", "2024-02-29", "2024-03-31", "2024-04-30"])
        #expect(directa.map(\.cash) == [498, 1063, 1063, 1063])
        #expect(directa.allSatisfy { $0.positions.isEmpty && $0.balance == nil })
        // The money added, as the trades count it (a dividend isn't).
        #expect(directa.map(\.flow) == [2500, 0, 0, 0])
        #expect(Self.trades(preview, "directa").count == 5)
    }

    @Test func tradesAfterTheCutOffAreLeftOut() throws {
        let preview = try Self.session().preview(against: Self.library(), until: "2024-02-10")
        #expect(Self.trades(preview, "directa").map(\.type) == [.deposit, .deposit, .buy, .dividend])
        #expect(Self.trades(preview, "crypto-wallet").map(\.type) == [.deposit, .buy])
    }

    @Test func feesTaxesAndWithdrawalsFromTheBroker() throws {
        let journal = LedgerReader.read(text: """
            2024-03-01 Deposit
                Assets:Broker:Directa:Cash     1000 EUR
                Assets:Bank:Fineco

            2024-03-05 Dividend with tax withheld
                Assets:Broker:Directa:Cash     11.10 EUR
                Expenses:Taxes:Ritenuta         3.90 EUR
                Income:Dividends              -15.00 EUR

            2024-03-10 Custody fee
                Expenses:Fees:Broker            2.00 EUR
                Assets:Broker:Directa:Cash

            2024-03-31 Imposta di bollo
                Expenses:Taxes:Bollo            8.47 EUR
                Assets:Broker:Directa:Cash

            2024-04-02 Opening a position with its cost
                Assets:Broker:Directa           10 VWCE {95 EUR}
                Equity:Opening balances

            2024-04-03 Shares moved in without a cost
                Assets:Broker:Directa           2 VWCE
                Equity:Opening balances        -2 VWCE

            2024-04-05 Back to the bank
                Assets:Bank:Fineco             500 EUR
                Assets:Broker:Directa:Cash
            """)
        let preview = LedgerImportSession(journal: journal).preview(against: Self.library(), until: "2026-09-30")
        let trades = Self.trades(preview, "directa")
        #expect(trades.map(\.type) == [.deposit, .dividend, .fee, .tax, .deposit, .buy, .transferIn, .withdrawal])
        let dividend = trades[1]
        #expect(dividend.amount == dec("11.1"))
        #expect(dividend.tax == dec("3.9"))
        #expect(trades[2].amount == -2)
        #expect(trades[3].amount == dec("-8.47"))
        // An opening with a cost is a buy paid for with money from outside.
        #expect(trades[4].amount == 950)
        #expect(trades[5].quantity == 10)
        #expect(trades[5].price == 95)
        #expect(trades[6].quantity == 2)
        #expect(trades[6].cost == nil)
        #expect(trades[7].amount == -500)
        #expect(preview.notes.map(\.message).contains { $0.hasPrefix("2 VWCE came into Directa without a cost") })
        let imported = preview.preview.apply(to: Self.library()).library
        #expect(Valuator(library: imported).tradeCash(of: "directa", on: "2024-04-30") == dec("500.63"))
    }
}
