import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

struct PreviewApplyTests {
    private func makeSession(_ csv: String) throws -> ImportSession {
        try ImportSession(data: Data(csv.utf8))
    }

    /// A library where `broker` holds an ETF with a known cost, and `cash` has a balance.
    private func library() -> Library {
        var library = Library(
            accounts: [
                Account(id: "cash", name: "Cash", kind: .cash, currency: .eur, opened: "2020-01-01"),
                Account(id: "broker", name: "Broker", kind: .brokerage, currency: .eur, opened: "2020-01-01"),
            ],
            instruments: [
                Instrument(id: "etf", name: "ETF", kind: .etf, currency: .eur, unit: .share,
                           assetClasses: .single(.equity)),
            ])
        library.upsert(Valuation(account: "cash", date: "2026-01-31", balance: 100, flow: 10, note: "kept"))
        library.upsert(Valuation(account: "cash", date: "2026-02-28", balance: 200))
        library.upsert(Valuation(account: "broker", date: "2026-01-31", cash: 5,
                                 positions: [Position(instrument: "etf", quantity: 10)]))
        library.upsert(Valuation(account: "broker", date: "2026-02-28", cash: 5,
                                 positions: [Position(instrument: "etf", quantity: 10, costBasis: 900)]))
        return library
    }

    private let file = """
        Date;Cash;Broker ETF qty;Broker ETF cost
        2026-01-31;100;10;950
        2026-02-28;250;12;950
        2026-03-31;300;12;1000
        """

    private func mappedSession() throws -> ImportSession {
        var session = try makeSession(file)
        session.setMapping(ImportColumn(target: .quantity, account: "broker", instrument: "etf"), forColumn: 3)
        session.setMapping(ImportColumn(target: .costBasis, account: "broker", instrument: "etf"), forColumn: 4)
        return session
    }

    @Test func comparesEveryRecordWithTheLibrary() throws {
        let preview = try mappedSession().preview(against: library())
        #expect(preview.issues.isEmpty)
        #expect(preview.statuses == [
            "cash on 2026-01-31": .identical, "cash on 2026-02-28": .conflict, "cash on 2026-03-31": .new,
            "broker on 2026-01-31": .updated, "broker on 2026-02-28": .conflict, "broker on 2026-03-31": .new,
        ])
        let summary = preview.summary
        #expect((summary.newRecords, summary.updatedRecords, summary.identicalRecords, summary.conflicts)
            == (2, 1, 1, 2))
        #expect(summary.undecidedConflicts == 2)
        #expect(summary.description == "2 new, 1 updated, 1 identical, 2 conflicts (2 undecided)")
        let conflict = try #require(preview.record(.valuation("broker", "2026-02-28")))
        #expect(conflict.existing == .valuation(Valuation(account: "broker", date: "2026-02-28", cash: 5,
            positions: [Position(instrument: "etf", quantity: 10, costBasis: 900)])))
        #expect(conflict.incoming == .valuation(Valuation(account: "broker", date: "2026-02-28", cash: 5,
            positions: [Position(instrument: "etf", quantity: 12, costBasis: 950)], source: .import)))
    }

    @Test func appliesByPolicy() throws {
        let base = library()
        var preview = try mappedSession().preview(against: base)

        // Undecided conflicts are kept; new values are still filled in.
        var result = preview.apply(to: base)
        #expect(result.library.valuations(for: "cash").map(\.balance) == [100, 200, 300])
        #expect(result.library.valuations(for: "broker")[0].positions == [
            Position(instrument: "etf", quantity: 10, costBasis: 950),
        ])
        #expect((result.added, result.updated, result.kept, result.undecided, result.identical) == (2, 1, 2, 2, 1))
        #expect(result.changedMonths == ["2026-01", "2026-03"])

        preview.resolveConflicts(.overwrite)
        result = preview.apply(to: base)
        #expect(result.library.valuations(for: "cash").map(\.balance) == [100, 250, 300])
        #expect(result.library.valuations(for: "broker")[1].positions == [
            Position(instrument: "etf", quantity: 12, costBasis: 950),
        ])
        #expect(result.overwritten == 2)
        #expect(result.changedMonths == ["2026-01", "2026-02", "2026-03"])

        // One by one.
        preview.resolveConflicts(.keep)
        let index = try #require(preview.records.firstIndex { $0.imported.key == .valuation("cash", "2026-02-28") })
        preview.records[index].resolution = .overwrite
        result = preview.apply(to: base)
        #expect(result.library.valuations(for: "cash").map(\.balance) == [100, 250, 300])
        #expect(result.library.valuations(for: "broker")[1].positions[0].quantity == 10)
        #expect((result.overwritten, result.kept, result.undecided) == (1, 1, 0))
    }

    @Test func keepsWhatTheFileDoesNotMention() throws {
        let base = library()
        var preview = try mappedSession().preview(against: base)
        preview.resolveConflicts(.overwrite)
        let result = preview.apply(to: base)
        let january = try #require(result.library.valuations(for: "cash").first)
        #expect(january.flow == 10)
        #expect(january.note == "kept")
        #expect(result.library.valuations(for: "broker")[1].cash == 5)
        #expect(result.library.valuations(for: "cash").last?.source == .import)
    }

    @Test func profilePolicyStartsTheResolution() throws {
        var session = try mappedSession()
        session.profile.onConflict = .overwrite
        let preview = session.preview(against: library())
        #expect(preview.conflicts.allSatisfy { $0.resolution == .overwrite })
        #expect(preview.conflictPolicy == .overwrite)
        #expect(preview.summary.undecidedConflicts == 0)
    }

    @Test func switchingBetweenBalanceAndHoldingsIsAConflict() throws {
        var base = library()
        base.upsert(Valuation(account: "broker", date: "2026-03-31", balance: 1000))
        var session = try makeSession("Date;Broker\n2026-01-31;1500\n")
        var preview = session.preview(against: base)
        #expect(preview.statuses == ["broker on 2026-01-31": .conflict])
        preview.resolveConflicts(.overwrite)
        let valuation = preview.apply(to: base).library.valuations(for: "broker")[0]
        #expect(valuation == Valuation(account: "broker", date: "2026-01-31", balance: 1500, source: .import))

        session = try makeSession("Date;Broker qty\n2026-03-31;7\n")
        session.setMapping(ImportColumn(target: .quantity, account: "broker", instrument: "etf"), forColumn: 2)
        preview = session.preview(against: base)
        #expect(preview.statuses == ["broker on 2026-03-31": .conflict])
        #expect(preview.apply(to: base).library.valuations(for: "broker")[2].balance == 1000)
        preview.resolveConflicts(.overwrite)
        #expect(preview.apply(to: base).library.valuations(for: "broker")[2]
            == Valuation(account: "broker", date: "2026-03-31", positions: [Position(instrument: "etf", quantity: 7)],
                         source: .import))
    }

    @Test func pricesAndFXRates() throws {
        var base = library()
        base.upsert(PriceRecord(instrument: "etf", date: "2026-01-31", price: 100, currency: .eur, source: .yahoo))
        base.upsert(FXRecord(base: .eur, quote: .usd, date: "2026-01-31", rate: dec("1.1"), source: .ecb))
        var session = try makeSession("Date;Prezzo ETF;EURUSD\n2026-01-31;100,00;1,1\n2026-02-28;101,5;1,12\n")
        #expect(session.mapping(forColumn: 2)?.target == .price)
        #expect(session.mapping(forColumn: 3)?.target == .fx)
        var preview = session.preview(against: base)
        #expect(preview.statuses == [
            "etf price on 2026-01-31": .identical, "EUR/USD on 2026-01-31": .identical,
            "etf price on 2026-02-28": .new, "EUR/USD on 2026-02-28": .new,
        ])
        let result = preview.apply(to: base)
        #expect(result.library.prices(for: "etf").map(\.source) == [.yahoo, .import])
        #expect(result.library.fxRates(base: .eur, quote: .usd).last?.rate == dec("1.12"))

        session.setMapping(ImportColumn(target: .price, instrument: "etf", currency: .usd), forColumn: 2)
        preview = session.preview(against: base)
        #expect(preview.statuses["etf price on 2026-01-31"] == .conflict)
    }

    @Test func proposalsCanBeEditedOrRejected() throws {
        let base = library()
        var preview = try makeSession("Date;Cash;Savings;Loan\n2026-01-31;1;2;-3\n2026-02-28;1;2;\n")
            .preview(against: base)
        #expect(preview.newAccounts.map(\.account.id) == ["loan", "savings"])
        #expect(preview.accountChanges == [AccountChangeProposal(account: "loan", change: .close(on: "2026-02-01"),
                                                                 isAccepted: false)])
        preview.newAccounts[1].account.kind = .other
        preview.newAccounts[1].account.currency = .chf
        preview.newAccounts[0].isAccepted = false

        let result = preview.apply(to: base)
        #expect(result.createdAccounts == ["savings"])
        #expect(result.library.accounts["savings"]?.kind == .other)
        #expect(result.library.accounts["savings"]?.currency == .chf)
        #expect(result.library.accounts["loan"] == nil)
        #expect(result.library.valuations(for: "loan").isEmpty)
        #expect(result.skipped == 1)
        #expect(result.closedAccounts.isEmpty)
        #expect(result.changedAccounts == ["savings"])
    }

    @Test func proposesClosingAndOpeningEarlier() throws {
        var base = library()
        base.accounts["cash"]?.opened = "2026-02-01"
        let file = "Date;Cash;Broker\n2025-12-31;50;10\n2026-01-31;100;0\n2026-02-28;200;0\n"
        var preview = try makeSession(file).preview(against: base)
        // Closing is proposed but only made when accepted; opening earlier is accepted.
        #expect(preview.accountChanges == [
            AccountChangeProposal(account: "broker", change: .close(on: "2026-01-01"), isAccepted: false),
            AccountChangeProposal(account: "cash", change: .openEarlier(on: "2025-12-31")),
        ])
        let opened = preview.apply(to: base)
        #expect(opened.library.accounts["broker"]?.closed == nil)
        #expect(opened.library.accounts["cash"]?.opened == date("2025-12-31"))
        #expect(opened.closedAccounts.isEmpty)
        #expect(opened.changedAccounts == ["cash"])
        preview.accountChanges[0].isAccepted = true
        let result = preview.apply(to: base)
        #expect(result.library.accounts["broker"]?.closed == date("2026-01-01"))
        #expect(result.library.accounts["cash"]?.opened == date("2025-12-31"))
        #expect(result.closedAccounts == ["broker"])
        #expect(result.changedAccounts == ["broker", "cash"])

        // Later values in the library mean the account isn't closed.
        base.upsert(Valuation(account: "broker", date: "2026-05-31", balance: 20))
        preview = try makeSession(file).preview(against: base)
        #expect(!preview.accountChanges.contains { $0.account == "broker" })

        // Values after an account closed are flagged.
        base.accounts["cash"]?.closed = "2026-01-15"
        preview = try makeSession(file).preview(against: base)
        #expect(preview.issues.contains(ImportIssue(kind: .valuesAfterClosed("cash", closed: "2026-01-15"))))
    }

    @Test func followedFlowsAreWrittenWithTheImport() throws {
        let base = library()
        let file = "Date;Cash\n2026-01-15;150\n"
        var result = try makeSession(file).preview(against: base).apply(to: base)
        // A spreadsheet gives no flows: none are fixed.
        #expect(result.fixedFlows.isEmpty)
        #expect(result.changedMonths == ["2026-01"])
        // The caller works out the next value's flow again (Tracker) and records it.
        let next = try #require(result.library.valuations(for: "cash").first { $0.date == "2026-02-28" })
        result.followedFlows([next])
        #expect(result.recomputedFlows == [next.key])
        #expect(result.changedMonths == ["2026-01", "2026-02"])
    }

    @Test func openingEarlierMovesAPensionFundsJoiningDate() throws {
        var base = library()
        base.accounts["fondo"] = Account(id: "fondo", name: "Fondo", kind: .pensionFund, currency: .eur,
                                         opened: "2026-02-01",
                                         tax: AccountTax(wrapper: "it.pensionFund", details: ["joined": "2026-02-01"]))
        base.upsert(Valuation(account: "fondo", date: "2026-02-28", balance: 1000))
        let file = "Date;Fondo\n2025-12-31;800\n2026-02-28;1000\n"
        let preview = try makeSession(file).preview(against: base)
        #expect(preview.accountChanges == [
            AccountChangeProposal(account: "fondo", change: .openEarlier(on: "2025-12-31")),
        ])
        var result = preview.apply(to: base)
        #expect(result.library.accounts["fondo"]?.opened == date("2025-12-31"))
        #expect(result.library.accounts["fondo"]?.tax?.joined == date("2025-12-31"))

        // A joining date set by hand stays.
        base.accounts["fondo"]?.tax?.details["joined"] = "2010-01-01"
        result = try makeSession(file).preview(against: base).apply(to: base)
        #expect(result.library.accounts["fondo"]?.opened == date("2025-12-31"))
        #expect(result.library.accounts["fondo"]?.tax?.joined == date("2010-01-01"))
    }

    @Test func reportsProblemsBetweenCells() throws {
        let file = "Date,Account,Value,Currency\n2026-01-31,Cash,100,EUR\n2026-01-31,Cash,101,EUR\n"
            + "2026-01-31,Cash,$5,\n2026-01-31,,7,EUR\n2026-01-31,Cash,8,EURO\n"
        let preview = try makeSession(file).preview(against: library())
        #expect(preview.cellErrors.map(\.problem) == [
            .duplicate(row: 2), .currencyMismatch(expected: .eur, found: .usd), .missingName(.account),
            .unknownCurrency("EURO"),
        ])
        #expect(preview.cellErrors.map(\.cell) == [
            ImportCellRef(row: 3, column: 3), ImportCellRef(row: 4, column: 3), ImportCellRef(row: 5, column: 2),
            ImportCellRef(row: 6, column: 4),
        ])

        var costs = try makeSession("Date;Broker cost\n2026-03-31;500\n")
        costs.setMapping(ImportColumn(target: .costBasis, account: "broker", instrument: "etf"), forColumn: 2)
        let costPreview = costs.preview(against: library())
        #expect(costPreview.cellErrors.map(\.problem) == [.costWithoutQuantity])
        #expect(costPreview.records.isEmpty)
    }

    @Test func constantsFillInWhatTheFileLeavesOut() throws {
        // A wide file for one account: each column is an instrument.
        var session = try makeSession("Data;ETF;BTC\n31/01/2026;11;0,5\n")
        session.profile.constants.account = "broker"
        session.setMapping(ImportColumn(target: .quantity), forColumn: 2)
        session.setMapping(ImportColumn(target: .quantity), forColumn: 3)
        var preview = session.preview(against: library())
        #expect(preview.issues.isEmpty)
        #expect(preview.record(.valuation("broker", "2026-01-31"))?.imported.positions == [
            ImportedPosition(instrument: "btc", quantity: dec("0.5")), ImportedPosition(instrument: "etf", quantity: 11),
        ])
        #expect(preview.newInstruments.map(\.instrument.kind) == [.crypto])
        #expect(preview.newInstruments.first?.instrument.unit == "BTC")

        // A long file with only dates and values.
        session = try makeSession("date,value\n2026-03-31,42\n")
        session.profile.layout = .long
        session.setMapping(ImportColumn(field: .date), forColumn: 1)
        session.setMapping(ImportColumn(field: .value), forColumn: 2)
        session.profile.target = .balance
        session.profile.constants = ImportConstants(account: "cash", currency: .eur)
        preview = session.preview(against: library())
        #expect(preview.record(.valuation("cash", "2026-03-31"))?.imported.balance == 42)
    }

    @Test func longFXRates() throws {
        let session = try makeSession("Date,Base,Quote,Rate\n2026-01-31,EUR,USD,1.1034\n2026-01-31,EUR,CHF,0.9412\n")
        #expect(session.profile.layout == .long)
        #expect(session.profile.columns.map(\.field) == [.date, .base, .quote, .value])
        #expect(session.profile.target == .fx)
        let preview = session.preview(against: Library())
        #expect(preview.records.map(\.imported.key.description) == ["EUR/CHF on 2026-01-31", "EUR/USD on 2026-01-31"])
        #expect(preview.records.map(\.imported.rate) == [dec("0.9412"), dec("1.1034")])
    }

    @Test func emptyCellsCanBeZero() throws {
        var session = try makeSession("Date;Cash\n2026-01-31;\n2026-02-28;200\n")
        #expect(session.preview(against: library()).record(.valuation("cash", "2026-01-31")) == nil)
        session.profile.defaults.empty = .zero
        #expect(session.preview(against: library()).record(.valuation("cash", "2026-01-31"))?.status == .conflict)
    }

    /// Importing the same file twice changes nothing. Closings that weren't
    /// accepted are proposed again, still not accepted.
    @Test(arguments: ["italian-excel-1252.csv", "us-export.csv", "numbers-export.csv", "titles-totals-utf16.tsv",
                      "month-only.csv", "excel-serial.csv", "long-format.csv", "positions.csv", "broken-rows.csv",
                      "positive-debts.csv"])
    func importingTwiceChangesNothing(name: String) throws {
        let session = try Samples.session(name)
        let library = try Fixtures.exampleLibrary()
        var first = session.preview(against: library)
        first.resolveConflicts(.overwrite)
        let once = first.apply(to: library)
        #expect(once.hasChanges)

        var second = session.preview(against: once.library)
        #expect(second.records.allSatisfy { $0.status == .identical })
        #expect(second.newAccounts.isEmpty)
        #expect(second.newInstruments.isEmpty)
        #expect(second.accountChanges == first.accountChanges.filter { !$0.isAccepted })
        second.resolveConflicts(.overwrite)
        let twice = second.apply(to: once.library)
        #expect(!twice.hasChanges)
        #expect(twice.library == once.library)
    }

    @Test func keepingConflictsIsIdempotentToo() throws {
        let library = try Fixtures.exampleLibrary()
        let profile = try #require(library.importProfiles["net-worth-sheet"])
        let data = try Samples.data("italian-excel-1252.csv")
        let once = try Importer.preview(data, profile: profile, library: library).apply(to: library)
        let again = try Importer.preview(data, profile: profile, library: once.library)
        #expect(again.summary.newRecords == 0)
        #expect(again.summary.conflicts == 5)
        #expect(!again.apply(to: once.library).hasChanges)
    }
}
