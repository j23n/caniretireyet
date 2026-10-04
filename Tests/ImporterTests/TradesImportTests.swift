import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// The trades layout: a broker's transactions, a row per trade (IMPORT.md,
/// "Broker transactions"), with the made-up exports in `Samples/trades/`.
struct TradeTypeWordTests {
    @Test func italianAndEnglishWordsSuggestTypes() {
        let expected: [(String, TradeType)] = [
            ("Acquisto", .buy), ("Compravendita acquisto", .buy), ("BUY", .buy), ("Buy", .buy),
            ("Vendita", .sell), ("Compravendita vendita", .sell), ("Sell", .sell),
            ("Dividendo", .dividend), ("Cedola", .dividend), ("Dividends", .dividend), ("Coupon", .dividend),
            ("Interessi", .interest), ("Interessi attivi", .interest), ("Interest", .interest),
            ("Commissioni", .fee), ("Spese", .fee), ("Fee", .fee),
            ("Bollo", .tax), ("Imposta di bollo", .tax), ("Imposta", .tax), ("Ritenuta", .tax), ("Tax", .tax),
            ("Withholding Tax", .tax),
            ("Versamento", .deposit), ("Bonifico in entrata", .deposit), ("Deposit", .deposit),
            ("Prelievo", .withdrawal), ("Bonifico in uscita", .withdrawal), ("Withdrawal", .withdrawal),
            ("Frazionamento", .split), ("Split", .split),
        ]
        for (word, type) in expected {
            #expect(TradeTypeWords.suggestion(for: word) == type, "\(word)")
        }
    }

    @Test func wordsAreFoundInLongerValuesIgnoringCaseAndAccents() {
        #expect(TradeTypeWords.suggestion(for: "  COMPRAVENDITA   ACQUISTO ") == .buy)
        #expect(TradeTypeWords.suggestion(for: "Broker Interest Received") == .interest)
        #expect(TradeTypeWords.suggestion(for: "Other Fees") == .fee)
        #expect(TradeTypeWords.suggestion(for: "Dividendo netto") == .dividend)
        #expect(TradeTypeWords.suggestion(for: "Prelievo contanti") == .withdrawal)
        // IBKR writes both ways in one type; the amount's sign then decides.
        #expect(TradeTypeWords.suggestion(for: "Deposits/Withdrawals") == .deposit)
    }

    @Test func aChargeOnIncomeIsTheCharge() {
        #expect(TradeTypeWords.suggestion(for: "Ritenuta su dividendo") == .tax)
        #expect(TradeTypeWords.suggestion(for: "Dividend Tax") == .tax)
        #expect(TradeTypeWords.suggestion(for: "Commissioni su vendita") == .fee)
        #expect(TradeTypeWords.suggestion(for: "Imposta su interessi") == .tax)
    }

    @Test func unknownOrAmbiguousWordsAreNeverGuessed() {
        #expect(TradeTypeWords.suggestion(for: "Giroconto") == nil)
        #expect(TradeTypeWords.suggestion(for: "Rimborso") == nil)
        #expect(TradeTypeWords.suggestion(for: "Bonifico") == nil)
        #expect(TradeTypeWords.suggestion(for: "Acquisto/Vendita") == nil)
        #expect(TradeTypeWords.suggestion(for: "Commissioni e imposte") == nil)
        #expect(TradeTypeWords.suggestion(for: "") == nil)
        #expect(TradeTypeWords.suggestion(for: "A") == nil)
    }

    @Test func theProfilesMapComesFirst() throws {
        var session = try Samples.session("trades/directa.csv")
        #expect(session.tradeType(for: "Acquisto") == (.buy, .suggested))
        #expect(session.tradeType(for: "Giroconto") == (nil, .unmapped))
        session.setTradeType(.deposit, for: "Giroconto")
        session.setTradeType(.sell, for: "Acquisto")
        #expect(session.tradeType(for: "GIROCONTO") == (.deposit, .profile))
        #expect(session.tradeType(for: "Acquisto") == (.sell, .profile))
        session.setTradeType(nil, for: "acquisto")
        #expect(session.tradeType(for: "Acquisto") == (.buy, .suggested))
        #expect(session.profile.tradeTypes == ["Giroconto": .deposit])
    }
}

struct TradesLayoutTests {
    private static func fields(_ session: ImportSession) -> [String: ImportField] {
        Dictionary(uniqueKeysWithValues: session.profile.columns.map { ($0.header ?? "", $0.field ?? .ignore) })
    }

    @Test func transactionsFilesAreDetected() throws {
        for name in ["directa", "fineco", "degiro", "ibkr"] {
            let session = try Samples.session("trades/\(name).csv")
            #expect(session.looksLikeTransactions, "\(name)")
            #expect(session.profile.layout == .trades, "\(name)")
        }
        for name in ["positions.csv", "long-format.csv", "italian-excel-1252.csv", "us-export.csv"] {
            let session = try Samples.session(name)
            #expect(!session.looksLikeTransactions, "\(name)")
            #expect(session.profile.layout != .trades, "\(name)")
        }
    }

    @Test func italianColumnsAreProposed() throws {
        let directa = try Samples.session("trades/directa.csv")
        #expect(directa.table.headerRow == 5)
        #expect(Self.fields(directa) == [
            "Data operazione": .date, "Data valuta": .ignore, "Tipo operazione": .type, "Ticker": .instrument,
            "ISIN": .instrument, "Titolo": .instrument, "Quantità": .quantity, "Prezzo": .price,
            "Importo euro": .amount, "Commissioni": .fees, "Divisa": .currency, "Descrizione": .note,
        ])
        let fineco = try Samples.session("trades/fineco.csv")
        #expect(fineco.table.encoding == .windows1252)
        #expect(Self.fields(fineco) == [
            "Operazione": .type, "Data operazione": .date, "Data valuta": .ignore, "Titolo": .instrument,
            "ISIN": .instrument, "Quantità": .quantity, "Prezzo": .price, "Divisa": .currency,
            "Controvalore": .gross, "Commissioni": .fees, "Ritenuta": .tax, "Descrizione": .note,
        ])
        #expect(fineco.effectiveFormat(forColumn: 2).date?.pattern == "dd/MM/yyyy")
        #expect(fineco.effectiveFormat(forColumn: 9).number?.decimal == ",")
    }

    @Test func englishColumnsAreProposed() throws {
        let degiro = try Samples.session("trades/degiro.csv")
        #expect(Self.fields(degiro) == [
            "Date": .date, "Time": .ignore, "Product": .instrument, "ISIN": .instrument, "Reference exchange": .ignore,
            "Venue": .ignore, "Quantity": .quantity, "Price": .price, "Currency": .currency, "Local value": .ignore,
            "Value EUR": .gross, "Exchange rate": .ignore, "Transaction costs EUR": .fees, "Total EUR": .amount,
            "Order ID": .ignore,
        ])
        #expect(degiro.effectiveFormat(forColumn: 1).date?.pattern == "dd-MM-yyyy")
        #expect(degiro.tradeTypeColumn == nil)
        // Camel-case headers: `NetCash` is the net amount, over `Proceeds`.
        let ibkr = try Samples.session("trades/ibkr.csv")
        #expect(Self.fields(ibkr) == [
            "ClientAccountID": .account, "CurrencyPrimary": .currency, "Symbol": .instrument, "Description": .note,
            "ISIN": .instrument, "Date": .date, "Type": .type, "Quantity": .quantity, "TradePrice": .price,
            "Proceeds": .gross, "IBCommission": .fees, "Taxes": .ignore, "NetCash": .amount,
        ])
    }

    @Test func typeValuesAreListedWithTheirMapping() throws {
        let session = try Samples.session("trades/directa.csv")
        let values = session.tradeTypeValues
        #expect(values.map(\.value) == ["Bonifico in entrata", "Acquisto", "Dividendo", "Ritenuta su dividendo",
                                        "Vendita", "Imposta di bollo", "Commissioni", "Giroconto"])
        #expect(values.map(\.count) == [1, 5, 1, 1, 1, 1, 1, 1])
        #expect(values.map(\.type) == [.deposit, .buy, .dividend, .tax, .sell, .tax, .fee, nil])
        #expect(values.last?.source == .unmapped)
        #expect(values.dropLast().allSatisfy { $0.source == .suggested && $0.isImported })
    }
}

/// Signs: quantities positive, amounts signed by the file or by the type.
struct TradeSignTests {
    private static let library = Library(
        accounts: [Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2020-01-01",
                           valuation: .trades)],
        instruments: [Instrument(id: "vwce", name: "Vanguard FTSE All-World", kind: .etf, currency: .eur,
                                 unit: .share, assetClasses: .single(.equity), ticker: "VWCE")])

    private static func trades(_ csv: String, _ edit: (inout ImportSession) -> Void = { _ in }) throws
        -> (trades: [Trade], preview: ImportPreview) {
        var session = try ImportSession(data: Data(csv.utf8))
        if session.profile.layout != .trades { session.proposeMapping(layout: .trades) }
        session.profile.constants.account = "broker"
        edit(&session)
        let preview = session.preview(against: library)
        let trades = preview.records.compactMap(\.imported.trade)
        return (trades, preview)
    }

    @Test func absoluteAmountsTakeTheirSignFromTheType() throws {
        let (trades, preview) = try Self.trades("""
            Tipo;Data;Titolo;Quantità;Prezzo;Importo
            Versamento;02/01/2026;;;;1.000,00
            Acquisto;05/01/2026;VWCE;5;100,00;505,00
            Vendita;07/01/2026;VWCE;2;110,00;215,00
            Commissioni;08/01/2026;;;;3,00
            Imposta di bollo;09/01/2026;;;;2,00
            Prelievo;10/01/2026;;;;100,00
            Dividendo;20/01/2026;VWCE;;;4,50
            """)
        #expect(trades.map(\.type) == [.deposit, .buy, .sell, .fee, .tax, .withdrawal, .dividend])
        #expect(trades.map(\.amount) == [1000, -505, 215, -3, -2, -100, dec("4.5")])
        #expect(preview.issues.map(\.kind) == [.tradeAmountSigns(signed: false)])
        #expect(preview.issues[0].isNote)
    }

    @Test func signedAmountsKeepTheirSigns() throws {
        let (trades, preview) = try Self.trades("""
            Type,Date,Symbol,Quantity,Price,Amount
            Buy,2026-01-05,VWCE,5,100,-505
            Sell,2026-01-07,VWCE,-2,110,215
            Interest,2026-01-08,,,,-1.20
            Deposits/Withdrawals,2026-01-09,,,,-300
            Deposits/Withdrawals,2026-01-10,,,,400
            """)
        #expect(trades.map(\.type) == [.buy, .sell, .interest, .withdrawal, .deposit])
        // Negative interest is charged; quantities are positive whatever the file writes.
        #expect(trades.map(\.amount) == [-505, 215, dec("-1.2"), -300, 400])
        #expect(trades.compactMap(\.quantity) == [5, 2])
        #expect(preview.issues.map(\.kind) == [
            .tradeAmountSigns(signed: true), .negativeQuantities(count: 1, byType: true),
            .cashDirectionBySign(count: 1),
        ])
    }

    @Test func theAmountSignCanBeSet() throws {
        // A file of absolute values with one negative amount (a refund) reads as
        // signed, unless the profile says so.
        let csv = """
            Type,Date,Symbol,Quantity,Price,Amount
            Buy,2026-01-05,VWCE,5,100,505
            Fee,2026-01-08,,,,-3
            """
        let auto = try Self.trades(csv).trades
        #expect(auto.map(\.amount) == [505, -3])
        let fromType = try Self.trades(csv) { $0.profile.defaults.amountSign = .fromType }.trades
        #expect(fromType.map(\.amount) == [-505, -3])
        let asWritten = try Self.trades("""
            Type,Date,Symbol,Quantity,Price,Amount
            Withdrawal,2026-01-05,,,,50
            """) { $0.profile.defaults.amountSign = .asWritten }.trades
        #expect(asWritten.map(\.amount) == [50])
    }

    @Test func aSettlementColumnOrConstantSaysWhatWasPaidFromOutside() throws {
        func mapSettlement(_ session: inout ImportSession) {
            guard let index = session.profile.columns.firstIndex(where: { $0.header == "Paid from" }) else { return }
            session.profile.columns[index].field = .settlement
        }
        let (trades, preview) = try Self.trades("""
            Type,Date,Symbol,Quantity,Price,Amount,Paid from
            Buy,2026-01-05,VWCE,5,100,-505,outside
            Buy,2026-01-06,VWCE,1,100,-100,
            Sell,2026-01-07,VWCE,2,110,215,Yes
            Fee,2026-01-08,,,,-3,esterno
            Deposit,2026-01-09,,,,50,external
            Sell,2026-01-10,VWCE,1,110,110,account
            """, mapSettlement)
        #expect(trades.map(\.type) == [.buy, .buy, .sell, .fee, .deposit, .sell])
        // A deposit can't be paid from outside the account: its cell is ignored.
        #expect(trades.map(\.settlement) == [.external, nil, .external, .external, nil, nil])
        #expect(preview.cellErrors.isEmpty)

        let unreadable = try Self.trades("""
            Type,Date,Symbol,Quantity,Price,Amount,Paid from
            Buy,2026-01-05,VWCE,5,100,-505,bank transfer
            Buy,2026-01-06,VWCE,1,100,-100,no
            """, mapSettlement)
        #expect(unreadable.trades.map(\.date) == ["2026-01-06"])
        #expect(unreadable.preview.cellErrors.map(\.problem) == [.unknownSettlement("bank transfer")])

        // The profile's constant, for every buy, sell, fee and tax of a file without the column.
        let constant = try Self.trades("""
            Type,Date,Symbol,Quantity,Price,Amount
            Buy,2026-01-05,VWCE,5,100,-505
            Dividend,2026-01-20,VWCE,,,4.5
            """) { $0.profile.constants.settlement = .external }.trades
        #expect(constant.map(\.settlement) == [.external, nil])
        #expect(SettlementWords.settlement(for: " SÌ ") == .external)
        #expect(SettlementWords.settlement(for: "Conto") == .account)
        #expect(SettlementWords.settlement(for: "maybe") == nil)
    }

    @Test func grossValuesLoseTheirFeesAndTax() throws {
        let (trades, _) = try Self.trades("""
            Operazione;Data;Titolo;Quantità;Prezzo;Controvalore;Commissioni;Ritenuta
            Acquisto;05/01/2026;VWCE;5;100,00;500,00;-2,95;
            Vendita;07/01/2026;VWCE;2;110,00;220,00;2,95;1,20
            Dividendo;20/01/2026;VWCE;;;10,00;;2,60
            """)
        #expect(trades.map(\.amount) == [dec("-502.95"), dec("215.85"), dec("7.4")])
        #expect(trades.map(\.fees) == [dec("2.95"), dec("2.95"), nil])
        #expect(trades.map(\.tax) == [nil, dec("1.2"), dec("2.6")])
    }

    @Test func withoutATypeTheQuantitysSignSaysBuyOrSell() throws {
        let (trades, preview) = try Self.trades("""
            Date,Product,Quantity,Price,Total
            05-01-2026,VWCE,5,100.00,-502.00
            13-01-2026,VWCE,-2,110.00,218.00
            """)
        #expect(trades.map(\.type) == [.buy, .sell])
        #expect(trades.map(\.quantity) == [5, 2])
        #expect(trades.map(\.amount) == [-502, 218])
        #expect(preview.issues.contains { $0.kind == .negativeQuantities(count: 1, byType: false) })
    }

    @Test func rowsThatCantBeTradesAreFlagged() throws {
        let (trades, preview) = try Self.trades("""
            Tipo;Data;Titolo;Quantità;Prezzo;Importo
            Acquisto;05/01/2026;VWCE;5;;
            Rimborso;06/01/2026;VWCE;5;100;500
            Rimborso;07/01/2026;VWCE;1;100;100
            Acquisto;08/01/2026;VWCE;5;100;500
            """)
        #expect(trades.map(\.date) == ["2026-01-08"])
        #expect(preview.cellErrors.map(\.row) == [2, 3, 4])
        #expect(preview.cellErrors.map(\.problem) == [
            .invalidTrade("A buy needs a price or an amount."), .unmappedTradeType("Rimborso"),
            .unmappedTradeType("Rimborso"),
        ])
        #expect(preview.issues.contains { $0.kind == .unmappedTradeType("Rimborso", count: 2) && !$0.isNote })
    }

    @Test func ignoredTypesAreLeftOutWithANote() throws {
        let (trades, preview) = try Self.trades("""
            Tipo;Data;Importo
            Versamento;02/01/2026;1000
            Rimborso;06/01/2026;500
            """) { $0.setTradeType(TradeTypeWords.ignore, for: "Rimborso") }
        #expect(trades.map(\.type) == [.deposit])
        #expect(preview.cellErrors.isEmpty)
        #expect(preview.issues.contains { $0.kind == .ignoredTradeRows(count: 1) && $0.isNote })
    }

    /// Rows left out (a type ignored or not mapped) don't decide how the
    /// file writes its amounts: a negative amount among them doesn't make a
    /// file of absolute amounts signed, which would turn its withdrawals
    /// into deposits and its buys into money in.
    @Test func rowsLeftOutDontDecideTheSigns() throws {
        let csv = """
            Tipo;Data;Titolo;Quantità;Prezzo;Importo
            Versamento;02/01/2026;;;;1.000,00
            Acquisto;05/01/2026;VWCE;5;100,00;505,00
            Prelievo;10/01/2026;;;;100,00
            Rimborso;12/01/2026;;;;-40,00
            """
        let (ignored, preview) = try Self.trades(csv) { $0.setTradeType(TradeTypeWords.ignore, for: "Rimborso") }
        #expect(ignored.map(\.type) == [.deposit, .buy, .withdrawal])
        #expect(ignored.map(\.amount) == [1000, -505, -100])
        #expect(preview.issues.contains { $0.kind == .tradeAmountSigns(signed: false) })
        #expect(!preview.issues.contains { if case .cashDirectionBySign = $0.kind { true } else { false } })
        let unmapped = try Self.trades(csv).trades
        #expect(unmapped.map(\.amount) == [1000, -505, -100])
    }
}

/// Every sample export, end to end into the made-up example library.
struct BrokerSampleTests {
    private static func session(_ name: String, account: AccountID? = nil) throws -> ImportSession {
        var session = try Samples.session("trades/\(name).csv")
        if let account { session.profile.constants.account = account }
        return session
    }

    /// The trades of a preview by date, then amount (a day's trades are in ID order).
    private static func trades(_ preview: ImportPreview) -> [Trade] {
        preview.records.compactMap(\.imported.trade).sorted { ($0.date, $0.amount ?? 0) < ($1.date, $1.amount ?? 0) }
    }

    /// Applies the preview, then checks that previewing the file again against
    /// the result changes nothing.
    private static func importTwice(_ session: ImportSession, into library: Library) throws -> ImportResult {
        let result = session.preview(against: library).apply(to: library)
        let again = session.preview(against: result.library)
        #expect(again.records.allSatisfy { $0.status == .identical })
        #expect(again.newAccounts.isEmpty && again.newInstruments.isEmpty)
        #expect(!again.apply(to: result.library).hasChanges)
        return result
    }

    @Test func directa() throws {
        let library = try Fixtures.exampleLibrary()
        var session = try Self.session("directa", account: "directa")
        var preview = session.preview(against: library)
        #expect(preview.summary.description
            == "11 new, 0 updated, 0 identical, 0 conflicts; 11 trades among them; 1 error; 1 issue; "
            + "3 rows skipped; 2 new instruments")
        #expect(preview.accountChanges.isEmpty)
        #expect(preview.newAccounts.isEmpty)
        #expect(preview.newInstruments.map(\.instrument.id) == ["ishares-core-msci-world-ucits-etf",
                                                                "vanguard-ftse-all-world-high-div"])
        let swda = preview.newInstruments[0].instrument
        #expect(swda.name == "ISHARES CORE MSCI WORLD UCITS ETF")
        #expect(swda.isin == "IE00B4L5Y983")
        #expect(swda.ticker == "SWDA")
        #expect(swda.kind == .etf)
        #expect(preview.nameMatches.contains(NameMatch(name: "VWCE", instrument: "vwce", method: .existing)))
        let trades = preview.records.compactMap(\.imported.trade)
        let buy = try #require(trades.first { $0.date == "2026-01-12" })
        #expect(buy == Trade(account: "directa", date: "2026-01-12", id: buy.id, type: .buy, instrument: "vwce",
                             quantity: 15, price: dec("102.3"), amount: dec("-1539.5"), fees: 5,
                             note: "Eseguito su ETFplus", source: .import))
        let sell = try #require(trades.first { $0.type == .sell })
        #expect(sell.quantity == 4)
        #expect(sell.amount == dec("395.2"))
        // The two identical buys of 12 May are two trades.
        let split = trades.filter { $0.date == "2026-05-12" }
        #expect(split.count == 2)
        #expect(Set(split.map(\.id)).count == 2)
        #expect(split.map(\.id).sorted() == [TradeID.stable(for: split[0], ordinal: 0),
                                             TradeID.stable(for: split[0], ordinal: 1)].sorted())

        // Giroconto isn't mapped: flagged, then mapped and imported.
        #expect(preview.cellErrors.map(\.description)
            == ["Row 17, “Tipo operazione”: “Giroconto”: “Giroconto” isn't mapped to a trade type"])
        session.setTradeType(.deposit, for: "Giroconto")
        preview = session.preview(against: library)
        #expect(preview.summary.newRecords == 12)
        #expect(preview.cellErrors.isEmpty)

        let result = try Self.importTwice(session, into: library)
        #expect(result.added == 12)
        #expect(result.tradesWritten == 12)
        #expect(result.createdInstruments.count == 2)
        #expect(result.changedMonths == ["2026-01", "2026-02", "2026-03", "2026-04", "2026-05", "2026-06",
                                         "2026-07"])
        #expect(result.library.trades(for: "directa").count == library.trades(for: "directa").count + 12)
    }

    @Test func finecoIntoANewTradesAccount() throws {
        let library = try Fixtures.exampleLibrary()
        let preview = try Self.session("fineco", account: "fineco-titoli").preview(against: library)
        #expect(preview.summary.description
            == "8 new, 0 updated, 0 identical, 0 conflicts; 8 trades among them; 1 new account, 2 new instruments")
        let account = try #require(preview.newAccounts.first?.account)
        #expect(account.id == "fineco-titoli")
        #expect(account.valuation == .trades)
        #expect(account.kind == .brokerage)
        #expect(account.opened == "2026-01-08")
        #expect(preview.newInstruments.map(\.instrument.kind) == [.bond, .etf])
        let trades = Self.trades(preview)
        #expect(trades.map(\.type) == [.deposit, .buy, .buy, .buy, .dividend, .sell, .tax, .withdrawal])
        #expect(trades.map(\.amount) == [6000, dec("-4502.15"), dec("-1555.45"), dec("-948.55"), dec("15.8"),
                                         dec("1704.97"), dec("-8.37"), -500])
        let dividend = try #require(trades.first { $0.type == .dividend })
        #expect(dividend.quantity == 25)
        #expect(dividend.price == dec("0.854"))
        #expect(dividend.tax == dec("5.55"))
        #expect(preview.issues.map(\.description) == [
            "“Controvalore”: amounts are written without signs, so each one's sign comes from its type (negative "
                + "for buys, fees, taxes and withdrawals).",
        ])
        let result = try Self.importTwice(try Self.session("fineco", account: "fineco-titoli"), into: library)
        #expect(result.createdAccounts == ["fineco-titoli"])
        #expect(result.library.accounts["fineco-titoli"]?.recordsTrades == true)
    }

    @Test func finecoIntoAnAccountThatDoesntRecordTrades() throws {
        let library = try Fixtures.exampleLibrary()
        let session = try Self.session("fineco", account: "conto-fineco")
        var preview = session.preview(against: library)
        // Proposed, but only made when accepted.
        #expect(preview.accountChanges == [AccountChangeProposal(account: "conto-fineco", change: .recordTrades,
                                                                 isAccepted: false)])
        #expect(preview.summary.tradesAccounts == 0)
        // Not accepted: nothing changes for the account, and its trades are left out.
        let kept = preview.apply(to: library)
        #expect(kept.library.accounts["conto-fineco"] == library.accounts["conto-fineco"])
        #expect(kept.library.trades(for: "conto-fineco").isEmpty)
        #expect(kept.skipped == 8)
        #expect(kept.added == 0)
        // Accepted: the account records trades, and its trades are written.
        preview.accountChanges[0].isAccepted = true
        #expect(preview.summary.tradesAccounts == 1)
        let switched = preview.apply(to: library)
        #expect(switched.tradesAccounts == ["conto-fineco"])
        #expect(switched.changedAccounts.contains("conto-fineco"))
        #expect(switched.library.accounts["conto-fineco"]?.valuation == .trades)
        #expect(switched.library.trades(for: "conto-fineco").count == 8)
    }

    @Test func degiro() throws {
        let library = try Fixtures.exampleLibrary()
        let session = try Self.session("degiro", account: "degiro")
        let preview = session.preview(against: library)
        #expect(preview.summary.description
            == "5 new, 0 updated, 0 identical, 0 conflicts; 5 trades among them; 1 new account, 2 new instruments")
        let apple = try #require(preview.newInstruments.first { $0.instrument.isin == "US0378331005" }?.instrument)
        #expect(apple.name == "APPLE INC. - COMMON ST")
        #expect(apple.currency == .usd)
        let trades = Self.trades(preview)
        #expect(trades.map(\.type) == [.buy, .buy, .buy, .sell, .sell])
        #expect(trades.map(\.quantity) == [12, 5, 8, 2, 4])
        // The price is in dollars, the amount in the account's euros, at Degiro's rate.
        let buy = trades[1]
        #expect(buy.instrument == apple.id)
        #expect(buy.price == dec("230.5"))
        #expect(buy.currency == nil)
        #expect(buy.amount == dec("-1064.41"))
        #expect(buy.fees == 2)
        #expect(preview.issues.map(\.kind) == [.tradeAmountSigns(signed: true),
                                               .negativeQuantities(count: 2, byType: false)])
        _ = try Self.importTwice(session, into: library)
    }

    @Test func ibkr() throws {
        let library = try Fixtures.exampleLibrary()
        var session = try Self.session("ibkr")
        var preview = session.preview(against: library)
        // The account column's name is new: matched to an account here.
        #expect(preview.newAccounts.map(\.account.id) == ["u0000000"])
        #expect(preview.newAccounts.first?.account.valuation == .trades)
        session.match(account: "U0000000", to: "ibkr")
        preview = session.preview(against: library)
        #expect(preview.newAccounts.map(\.account.id) == ["ibkr"])
        #expect(preview.summary.description
            == "10 new, 0 updated, 0 identical, 0 conflicts; 10 trades among them; 1 new account, 2 new instruments")
        let trades = Self.trades(preview)
        #expect(trades.map(\.type) == [.deposit, .buy, .buy, .buy, .tax, .dividend, .interest, .fee, .sell,
                                       .withdrawal])
        #expect(trades.map(\.amount) == [5000, dec("-2055.8"), dec("-2408"), dec("-619.25"), dec("-1.11"),
                                         dec("7.41"), dec("2.37"), -10, 1012, -1500])
        #expect(trades.map(\.fees) == [nil, 3, 3, dec("1.25"), nil, nil, nil, nil, 3, nil])
        #expect(trades.filter { $0.type == .dividend }.map(\.instrument) == ["vhyl"])
        // Cash rows don't name instruments.
        #expect(trades.filter { $0.type == .tax }.map(\.instrument) == [nil])
        _ = try Self.importTwice(session, into: library)
    }

    @Test func aChangedFeeIsAConflictAndAMissingOneIsFilledIn() throws {
        let library = try Fixtures.exampleLibrary()
        let session = try Self.session("degiro", account: "degiro")
        var imported = session.preview(against: library).apply(to: library).library
        var trades = imported.trades(for: "degiro")
        var changed = trades[0]
        changed.fees = 3
        changed.note = "typed by hand"
        imported.upsert(changed)
        var missing = trades[1]
        missing.fees = nil
        imported.upsert(missing)
        let preview = session.preview(against: imported)
        #expect(preview.summary.conflicts == 1)
        #expect(preview.summary.updatedRecords == 1)
        #expect(preview.summary.identicalRecords == 3)
        var keep = preview
        keep.resolveConflicts(.keep)
        let kept = keep.apply(to: imported).library
        #expect(kept.trade(changed.key) == changed)
        #expect(kept.trade(missing.key)?.fees == 2)
        var overwrite = preview
        overwrite.resolveConflicts(.overwrite)
        let overwritten = try #require(overwrite.apply(to: imported).library.trade(changed.key))
        #expect(overwritten.fees == 2)
        // A note the file doesn't have stays.
        #expect(overwritten.note == "typed by hand")
        trades = kept.trades(for: "degiro")
        #expect(trades.count == 5)
    }

    @Test func theProfileRemembersTheMappingAndTypes() throws {
        let library = try Fixtures.exampleLibrary()
        var session = try Self.session("directa", account: "directa")
        session.setTradeType(TradeTypeWords.ignore, for: "Giroconto")
        let result = session.preview(against: library).apply(to: library)
        let profile = session.makeProfile(id: "directa", name: "Directa", library: result.library)
        #expect(profile.layout == .trades)
        #expect(profile.constants.account == "directa")
        #expect(profile.tradeTypes == [
            "Acquisto": .buy, "Bonifico in entrata": .deposit, "Commissioni": .fee, "Dividendo": .dividend,
            "Giroconto": TradeTypeWords.ignore, "Imposta di bollo": .tax, "Ritenuta su dividendo": .tax,
            "Vendita": .sell,
        ])
        #expect(profile.matches.instruments["VWCE"] == "vwce")
        #expect(profile.matches.instruments["IE00B4L5Y983"] == "ishares-core-msci-world-ucits-etf")
        #expect(profile.defaults.date?.pattern == "dd/MM/yyyy")
        #expect(profile.columns.first { $0.header == "Tipo operazione" }?.field == .type)

        // The profile reads the file the same way, and finds everything in the library.
        let again = try ImportSession(data: Samples.data("trades/directa.csv"), profile: profile)
        let preview = again.preview(against: result.library)
        #expect(preview.records.count == 11)
        #expect(preview.records.allSatisfy { $0.status == .identical })
        #expect(preview.cellErrors.isEmpty)
        #expect(again.tradeTypeValues.allSatisfy { $0.source == .profile })
    }
}
