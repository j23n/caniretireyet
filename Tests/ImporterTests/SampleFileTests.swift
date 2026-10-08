import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// Each sample file, read with a proposed mapping and previewed.
struct SampleFileTests {
    @Test func italianExcelExportWithTheSavedProfile() throws {
        let library = try Fixtures.exampleLibrary()
        let profile = try #require(library.importProfiles["net-worth-sheet"])
        let preview = try Importer.preview(Samples.data("italian-excel-1252.csv"), profile: profile, library: library)

        #expect(preview.issues.isEmpty)
        #expect(preview.cellErrors.isEmpty)
        #expect(preview.newAccounts.isEmpty)
        #expect(preview.statuses == [
            "conto-fineco on 2026-01-31": .identical, "conto-fineco on 2026-02-28": .identical,
            "conto-fineco on 2026-03-31": .identical,
            "directa on 2026-01-31": .conflict, "directa on 2026-02-28": .conflict, "directa on 2026-03-31": .conflict,
            "ledger-wallet on 2026-01-31": .new, "ledger-wallet on 2026-02-28": .new,
            "ledger-wallet on 2026-03-31": .conflict,
            "gold-coins on 2026-01-31": .new, "gold-coins on 2026-02-28": .new, "gold-coins on 2026-03-31": .conflict,
        ])
        let wallet = try #require(preview.record(.valuation("ledger-wallet", "2026-03-31")))
        #expect(wallet.imported.positions == [ImportedPosition(instrument: "btc", quantity: d("0.2201"))])
        #expect(wallet.cells == [ImportCellRef(row: 4, column: 4)])
        #expect(wallet.resolution == .ask)
        #expect(preview.summary.undecidedConflicts == 5)
        #expect(preview.skippedRows.map(\.reason) == [.excluded(rule: "Totale")])
        #expect(preview.nameMatches.contains(NameMatch(name: "gold-coins", account: "gold-coins", method: .profile)))
    }

    @Test func italianExcelExportWithAProposedMapping() throws {
        var session = try Samples.session("italian-excel-1252.csv")
        #expect(session.profile.layout == .wide)
        #expect(session.profile.dateColumn == "Data")
        #expect(session.profile.columns.map(\.target) == [.balance, .balance, .quantity, .balance, .ignore])
        #expect(session.issues.isEmpty)

        let library = try Fixtures.exampleLibrary()
        var preview = session.preview(against: library)
        // The header names the instrument, but not which account holds it.
        #expect(preview.issues == [ImportIssue(kind: .missingField(.account), column: 4, header: "BTC (qtà)")])
        #expect(preview.newAccounts.map(\.account.id) == ["oro"])
        #expect(preview.newAccounts.first?.account.kind == .metals)

        session.setMapping(ImportColumn(target: .quantity, account: "ledger-wallet"), forColumn: 4)
        session.match(account: "Oro", to: "gold-coins")
        preview = session.preview(against: library)
        #expect(preview.issues.isEmpty)
        #expect(preview.newAccounts.isEmpty)
        #expect(preview.record(.valuation("ledger-wallet", "2026-01-31"))?.imported.positions
            == [ImportedPosition(instrument: "btc", quantity: d("0.215"))])
        #expect(preview.nameMatches.contains(NameMatch(name: "Oro", account: "gold-coins", method: .remembered)))
        #expect(preview.nameMatches.contains(NameMatch(name: "BTC (qtà)", instrument: "btc", method: .existing)))
    }

    @Test func usExport() throws {
        let session = try Samples.session("us-export.csv")
        #expect(session.table.encoding == .utf8)
        #expect(session.detection.column(1)?.date?.pattern == "MM/dd/yyyy")
        #expect(session.detection.column(2)?.number == ImportNumberFormat(decimal: ".", thousands: ","))
        #expect(session.detection.column(2)?.currency == .usd)
        let fx = try #require(session.mapping(forColumn: 5))
        #expect(fx.target == .fx)
        #expect(fx.base == .eur)
        #expect(fx.quote == .usd)

        let preview = session.preview(against: Library())
        let accounts = Dictionary(uniqueKeysWithValues: preview.newAccounts.map { ($0.account.id, $0.account) })
        #expect(accounts["checking"]?.kind == .cash)
        #expect(accounts["brokerage"]?.kind == .brokerage)
        #expect(accounts["credit-card"]?.kind == .creditCard)
        #expect(accounts.values.allSatisfy { $0.currency == .usd && $0.opened == date("2026-01-31") })
        #expect(preview.record(.valuation("credit-card", "2026-03-31"))?.imported.balance == d("-410.35"))
        #expect(preview.record(.fx(FXKey(base: .eur, quote: .usd, date: "2026-02-28")))?.imported.rate == d("1.0968"))
        #expect(preview.summary.newRecords == 12)
    }

    @Test func numbersExport() throws {
        let session = try Samples.session("numbers-export.csv")
        #expect(session.table.headerRow == 2)
        #expect(session.detection.column(1)?.date?.pattern == "d MMM yyyy")
        #expect(session.detection.column(2)?.number == ImportNumberFormat(decimal: ",", thousands: "\u{00A0}"))
        #expect(session.detection.column(2)?.currency == .eur)
        #expect(session.detection.column(4)?.number?.percent == true)
        #expect(session.mapping(forColumn: 4)?.target == .ignore)

        let preview = session.preview(against: smallLibrary())
        #expect(preview.record(.valuation("fondo-pensione", "2026-02-28"))?.imported.balance == d("17402.11"))
        #expect(preview.record(.valuation("fondo-pensione", "2026-01-31"))?.status == .conflict)
        #expect(preview.newAccounts.map(\.account.id) == ["conto-deposito"])
        #expect(preview.newAccounts.first?.account.kind == .savings)
        #expect(preview.skippedRows.map(\.number) == [1])
    }

    @Test func titleRowsAndTotals() throws {
        let preview = try Samples.session("titles-totals-utf16.tsv").preview(against: Library())
        #expect(preview.records.count == 9)
        #expect(preview.summary.skippedRows == 4)
        #expect(preview.cellErrors.isEmpty)
        #expect(preview.newAccounts.map(\.account.kind) == [.savings, .cash, .tfr])
    }

    @Test func monthOnlyDates() throws {
        var session = try Samples.session("month-only.csv")
        #expect(session.table.delimiter == "|")
        #expect(session.detection.column(1)?.date?.pattern == "MMM yyyy")
        var preview = session.preview(against: Library())
        #expect(Set(preview.records.map(\.imported.key.date)) == [date("2026-01-31"), date("2026-02-28"),
                                                                 date("2026-03-31")])
        session.profile.defaults.date = ImportDateFormat(monthOnly: .start)
        preview = session.preview(against: Library())
        #expect(Set(preview.records.map(\.imported.key.date)) == [date("2026-01-01"), date("2026-02-01"),
                                                                 date("2026-03-01")])
    }

    @Test func excelSerialDates() throws {
        let session = try Samples.session("excel-serial.csv")
        #expect(session.detection.column(1)?.date?.pattern == ImportDateFormat.excelSerialPattern)
        let preview = session.preview(against: Library())
        #expect(preview.lastDate == date("2026-03-31"))
        #expect(preview.record(.valuation("mortgage", "2026-02-28"))?.imported.balance == d("-146250"))
        let kinds = Dictionary(uniqueKeysWithValues: preview.newAccounts.map { ($0.account.id, $0.account.kind) })
        #expect(kinds == ["savings-account": .savings, "old-savings": .savings, "mortgage": .mortgage])
        #expect(preview.accountChanges == [AccountChangeProposal(account: "old-savings", change: .close(on: "2026-03-01"),
                                                                 isAccepted: false)])
    }

    @Test func longFormat() throws {
        var session = try Samples.session("long-format.csv")
        #expect(session.profile.layout == .long)
        #expect(session.profile.columns.map(\.field) == [.date, .account, .value, .currency])
        #expect(session.profile.target == .balance)

        let library = smallLibrary()
        var preview = session.preview(against: library)
        // Case and accents don't matter; "Fineco" isn't a name the library knows.
        #expect(preview.newAccounts.map(\.account.id) == ["credit-agricole", "fineco"])
        #expect(preview.newAccounts.first?.names == ["Crédit Agricole", "Credit Agricole"])
        #expect(preview.statuses["conto-fineco on 2026-01-31"] == .identical)
        #expect(preview.statuses["fondo-pensione on 2026-01-31"] == .conflict)

        session.match(account: "Fineco", to: "conto-fineco")
        preview = session.preview(against: library)
        #expect(preview.newAccounts.map(\.account.id) == ["credit-agricole"])
        #expect(preview.record(.valuation("conto-fineco", "2026-02-28"))?.cells.count == 2)

        // A date-time is read in the chosen time zone: 23:30 at UTC−1 is 1:30 the next day in Rome.
        session.profile.defaults.date = ImportDateFormat(timeZone: "Europe/Rome")
        preview = session.preview(against: library)
        #expect(preview.record(.valuation("conto-fineco", "2026-03-01"))?.cells == [ImportCellRef(row: 5, column: 3)])
    }

    @Test func quantitiesPricesAndCostsInOneFile() throws {
        let session = try Samples.session("positions.csv")
        #expect(session.detection.column(1)?.date?.pattern == "d-MMM-yy")
        #expect(session.profile.columns.map(\.target) == [nil, nil, nil, .quantity, .price, nil, .costBasis, .ignore])

        var library = smallLibrary()
        library.upsert(Valuation(account: "directa", date: "2026-01-31", cash: d("256.8"),
                                 positions: [Position(instrument: "vwce", quantity: 368)]))
        library.upsert(PriceRecord(instrument: "vwce", date: "2026-01-31", price: d("132.6"), currency: .eur))
        let preview = session.preview(against: library)
        #expect(preview.statuses == [
            "directa on 2026-01-31": .updated, "vwce price on 2026-01-31": .identical,
            "swda price on 2026-01-31": .new, "directa on 2026-02-28": .new, "vwce price on 2026-02-28": .new,
            "swda price on 2026-02-28": .new,
        ])
        #expect(preview.newInstruments.map(\.instrument.id) == ["swda"])
        #expect(preview.newInstruments.first?.instrument.ticker == "SWDA")

        let result = preview.apply(to: library)
        let january = try #require(result.library.months["2026-01"]?.valuations.first { $0.account == "directa" })
        #expect(january.cash == d("256.8"))
        #expect(january.positions == [
            Position(instrument: "swda", quantity: 50, costBasis: 4500),
            Position(instrument: "vwce", quantity: 368, costBasis: 40200),
        ])
        #expect(result.library.prices(for: "swda").map(\.price) == [d("98.4"), d("99.1")])
        #expect(result.createdInstruments == ["swda"])
    }

    @Test func brokenRows() throws {
        let session = try Samples.session("broken-rows.csv")
        let preview = session.preview(against: Library())
        let errors = preview.cellErrors.map { "\($0.row):\($0.column):\($0.raw):\($0.problem)" }
        #expect(errors == [
            "3:1:2026-02-30:no such date",
            "4:1:not a date:not a date in yyyy-MM-dd",
            "5:2:12x0.00:not a number in 1,234.56",
            "6:3:abc:not a number in 1,234.56",
            "7:1::the row has no date",
            "9:2:\"1600.00:not a number in 1,234.56",
        ])
        #expect(preview.issues == [ImportIssue(kind: .unterminatedQuote(row: 9))])
        #expect(preview.record(.valuation("checking", "2026-04-30"))?.imported.balance == 1300)
        #expect(preview.records.count == 7)
        // The broken cell in row 9 still counts as a value: Checking isn't proposed as closed.
        #expect(preview.accountChanges.isEmpty)
        #expect(preview.cellErrors[0].description == "Row 3, “Date”: “2026-02-30”: no such date")
    }
}
