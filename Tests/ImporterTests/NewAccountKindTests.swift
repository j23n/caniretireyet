import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// The kinds proposed for new accounts: brokerage, crypto and metals accounts
/// record trades (docs/ACCOUNTS.md, "The importer").
struct NewAccountKindTests {
    @Test func aBalanceColumnOfAnInvestmentAccountIsProposedAsOther() throws {
        let session = try ImportSession(data: Data("Date;Crypto wallet;Broker;Oro;Conto\n2026-01-31;1000;2000;3000;10\n"
            .utf8))
        let preview = session.preview(against: Library())
        let kinds = Dictionary(uniqueKeysWithValues: preview.newAccounts.map { ($0.account.id, $0.account.kind) })
        #expect(kinds == ["crypto-wallet": .other, "broker": .other, "oro": .other, "conto": .cash])
        #expect(preview.newAccounts.allSatisfy { !$0.account.recordsTrades && $0.account.valuation == nil })
    }

    @Test func aTransactionsFileProposesAnAccountThatRecordsTrades() throws {
        var session = try ImportSession(data: Data("""
            Data;Tipo operazione;Titolo;Quantità;Prezzo;Importo
            12/01/2026;Acquisto;VWCE;10;100;-1000
            """.utf8))
        #expect(session.profile.layout == .trades)
        session.profile.constants.account = "nuovo-broker"
        var preview = session.preview(against: Library())
        let account = try #require(preview.newAccounts.first?.account)
        #expect(account.kind == .brokerage)
        #expect(account.valuation == nil)
        #expect(account.recordsTrades)
        #expect(preview.summary.trades == 1)

        // Its kind edited to one that records a balance: it still records its trades.
        preview.newAccounts[0].account.kind = .other
        let result = preview.apply(to: Library())
        #expect(result.library.accounts["nuovo-broker"]?.valuation == .trades)
        #expect(result.library.trades(for: "nuovo-broker").count == 1)
    }
}
