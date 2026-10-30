import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// Where a statement's values go before the library's first check-in
/// (IMPORT.md, "Values"): every month end, every quarter end, or never. A
/// made-up current account's January to April, imported into a library
/// without values, with the balance before the file given.
struct StatementCheckInsTests {
    static let today: CalendarDate = "2026-05-12"

    static let csv = """
        Data;Importo;Descrizione
        05/01/2026;-100,00;Spesa gennaio
        05/02/2026;-100,00;Spesa febbraio
        05/03/2026;-100,00;Spesa marzo
        05/04/2026;-100,00;Spesa aprile
        """

    static func library() -> Library {
        Library(accounts: [
            Account(id: "conto", name: "Conto", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "risparmio", name: "Risparmio", kind: .savings, currency: .eur, opened: "2020-01-01"),
        ])
    }

    static func valueDates(_ ends: StatementCheckIns.Ends?, library: Library) throws -> [CalendarDate] {
        var session = try ImportSession(data: Data(csv.utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        session.statementOpeningBalance = 1000
        session.statementCheckIns = ends.map { StatementCheckIns(ends: $0, before: library) }
        let preview = session.preview(against: library, today: Self.today)
        let ends: [CalendarDate] = ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"]
        return ends.filter { preview.record(.valuation("conto", $0)) != nil }
    }

    @Test func everyMonthEndIsTheDefault() throws {
        let all: [CalendarDate] = ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"]
        #expect(try Self.valueDates(nil, library: Self.library()) == all)
        #expect(try Self.valueDates(.months, library: Self.library()) == all)
    }

    @Test func quarterEndsOnly() throws {
        #expect(try Self.valueDates(.quarters, library: Self.library()) == ["2026-03-31", "2026-04-30"])
    }

    /// Without any, the lines are one stretch up to the file's last day.
    @Test func noneLeavesOneStretch() throws {
        #expect(try Self.valueDates(.never, library: Self.library()) == ["2026-04-30"])
    }

    /// From the library's first check-in on, every month end gets a value.
    @Test func monthEndsFromTheFirstCheckInOnAlwaysCount() throws {
        var library = Self.library()
        library.upsert(Valuation(account: "risparmio", date: "2026-02-28", balance: 5000))
        #expect(try Self.valueDates(.quarters, library: library) == ["2026-02-28", "2026-03-31", "2026-04-30"])
        #expect(try Self.valueDates(.never, library: library) == ["2026-02-28", "2026-03-31", "2026-04-30"])
    }

    /// Each file's last month end gets a value, so a file that starts the
    /// month after follows on from it, even mid-quarter.
    @Test func theNextFileFollowsOnFromTheLastMonthEnd() throws {
        var library = Self.library()
        library.upsert(Valuation(account: "risparmio", date: "2026-02-28", balance: 5000))
        let first = "Data;Importo;Descrizione\n" + (2...7).map { "05/0\($0)/2024;-100,00;Spesa" }
            .joined(separator: "\n")
        let second = "Data;Importo;Descrizione\n" + ["08", "09", "10", "11", "12"]
            .map { "05/\($0)/2024;-100,00;Spesa" }.joined(separator: "\n") + "\n05/01/2025;-100,00;Spesa"
        var batch = StatementBatch(files: [("first.csv", Data(first.utf8)), ("second.csv", Data(second.utf8))],
                                   library: library, today: Self.today)
        for file in batch.files {
            batch.setAccount("conto", forFile: file.id, library: library, today: Self.today)
        }
        let firstID = try #require(batch.files.first { $0.name == "first.csv" }?.id)
        batch.editSession(ofFile: firstID, library: library, today: Self.today) {
            $0.statementOpeningBalance = 1000
        }
        batch.setCheckIns(StatementCheckIns(ends: .quarters, before: library), library: library, today: Self.today)
        let previews = batch.previews(against: library, today: Self.today).map(\.preview)
        let needsBalance = previews.contains { $0.issues.contains { $0.kind == .needsOpeningBalance("conto") } }
        #expect(!needsBalance)
        let imported = ImportPreview.apply(previews, to: library).library
        let dates = imported.valuations(for: "conto").map(\.date)
        let expected: [CalendarDate] = ["2024-03-31", "2024-06-30", "2024-07-31", "2024-09-30", "2024-12-31",
                                        "2025-01-31"]
        #expect(dates == expected)
    }

    /// A month that isn't over gets no value, as with every month end.
    @Test func aMonthThatIsntOverGetsNone() throws {
        var session = try ImportSession(data: Data("Data;Importo;Descrizione\n05/05/2026;-100,00;Spesa".utf8))
        session.proposeMapping(layout: .statement)
        session.profile.constants.account = "conto"
        session.statementOpeningBalance = 1000
        session.statementCheckIns = StatementCheckIns(ends: .never, firstCheckIn: "2026-02-28")
        let preview = session.preview(against: Self.library(), today: Self.today)
        let values = preview.records.filter { if case .valuation = $0.imported.key { true } else { false } }
        #expect(values.isEmpty)
    }

    @Test func aBatchSetsThemForEveryFile() {
        let library = Self.library()
        var batch = StatementBatch(files: [("a.csv", Data(Self.csv.utf8))], library: library, today: Self.today)
        let checkIns = StatementCheckIns(ends: .quarters, before: library)
        batch.setCheckIns(checkIns, library: library, today: Self.today)
        batch.add(files: [("b.csv", Data(Self.csv.utf8))], library: library, today: Self.today)
        #expect(batch.files.map(\.session.statementCheckIns) == [checkIns, checkIns])
    }
}
