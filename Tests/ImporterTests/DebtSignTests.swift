import Foundation
@testable import Importer
import Model
import Testing
import TestSupport

/// Balances of debt accounts written as positive amounts, as spreadsheets
/// often do, are stored as negative balances (IMPORT.md, "Debts").
struct DebtSignTests {
    /// A current account and a mortgage recorded the usual way (negative).
    private func library() -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto", kind: .cash, currency: .eur, opened: "2020-01-01"),
            Account(id: "mutuo-casa", name: "Mutuo casa", kind: .mortgage, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "mutuo-casa", date: "2026-01-31", balance: -146_900))
        return library
    }

    private let positive = "Date;Conto;Mutuo casa\n2026-01-31;100;146900\n2026-02-28;120;146250\n"

    private func session(_ csv: String) throws -> ImportSession {
        try ImportSession(data: Data(csv.utf8))
    }

    @Test func positiveAmountsOfADebtAccountAreReadAsDebts() throws {
        let session = try session(positive)
        let preview = session.preview(against: library())

        let january = try #require(preview.record(.valuation("mutuo-casa", "2026-01-31")))
        #expect(january.imported.balance == -146_900)
        #expect(january.imported.balanceReadAsDebt)
        #expect(january.status == .identical)
        #expect(preview.record(.valuation("mutuo-casa", "2026-02-28"))?.imported.balance == -146_250)
        #expect(preview.record(.valuation("conto", "2026-01-31"))?.imported.balance == 100)
        #expect(preview.record(.valuation("conto", "2026-01-31"))?.imported.balanceReadAsDebt == false)

        let note = ImportIssue(kind: .positiveDebts("mutuo-casa", count: 2), column: 3, header: "Mutuo casa")
        #expect(preview.issues == [note])
        #expect(note.isNote)
        #expect(note.description == "“Mutuo casa”: positive amounts were read as debts (2 values).")
        // A note isn't a problem to fix.
        #expect(preview.summary.issues == 0)
        #expect(preview.summary.notes == 1)
        #expect(preview.summary.description == "3 new, 0 updated, 1 identical, 0 conflicts")

        let result = preview.apply(to: library())
        #expect(result.library.valuations(for: "mutuo-casa").map(\.balance) == [-146_900, -146_250])
        // Importing the same file again changes nothing.
        let again = session.preview(against: result.library)
        #expect(again.records.allSatisfy { $0.status == .identical })
        #expect(!again.apply(to: result.library).hasChanges)
    }

    @Test func negativeAmountsAndOtherAccountsKeepTheirSign() throws {
        let preview = try session("Date;Conto;Mutuo casa\n2026-02-28;-50;-146250\n").preview(against: library())
        #expect(preview.record(.valuation("mutuo-casa", "2026-02-28"))?.imported.balance == -146_250)
        #expect(preview.record(.valuation("conto", "2026-02-28"))?.imported.balance == -50)
        #expect(preview.issues.isEmpty)
    }

    /// A column that already writes debts as negative amounts keeps its
    /// signs with `auto`: a positive amount there is a debt in credit.
    @Test func aColumnWritingDebtsNegativeKeepsItsSigns() throws {
        var library = library()
        library.accounts["carta"] = Account(id: "carta", name: "Carta", kind: .creditCard, currency: .eur,
                                            opened: "2020-01-01")
        let csv = "Date;Conto;Mutuo casa;Carta\n2026-01-31;100;146900;-320.5\n2026-02-28;120;146250;20\n"
        let preview = try session(csv).preview(against: library)

        let credit = try #require(preview.record(.valuation("carta", "2026-02-28")))
        #expect(credit.imported.balance == 20)
        #expect(credit.imported.balanceKeptAsCredit)
        #expect(!credit.imported.balanceReadAsDebt)
        #expect(preview.record(.valuation("carta", "2026-01-31"))?.imported.balance == dec("-320.5"))
        // The mortgage's column writes debts positive: read as owed, as before.
        #expect(preview.record(.valuation("mutuo-casa", "2026-02-28"))?.imported.balance == -146_250)
        let note = ImportIssue(kind: .debtsInCredit("carta", count: 1), column: 4, header: "Carta")
        #expect(preview.issues == [
            ImportIssue(kind: .positiveDebts("mutuo-casa", count: 2), column: 3, header: "Mutuo casa"), note,
        ])
        #expect(note.isNote)
        #expect(note.description
            == "“Carta”: the column writes debts as negative amounts, so positive amounts were kept as credit (1 value).")

        let result = preview.apply(to: library)
        #expect(result.library.valuations(for: "carta").map(\.balance) == [dec("-320.5"), 20])
        #expect(result.library.valuations(for: "mutuo-casa").map(\.balance) == [-146_900, -146_250])
    }

    /// In the long layout one value column holds every account: if any debt
    /// in it is negative, the column's signs are kept.
    @Test func aLongFileWithNegativeDebtsKeepsItsSigns() throws {
        var library = library()
        library.accounts["carta"] = Account(id: "carta", name: "Carta", kind: .creditCard, currency: .eur,
                                            opened: "2020-01-01")
        let csv = "date,account,value\n2026-01-31,Mutuo casa,-146900\n2026-01-31,Carta,20\n2026-01-31,Conto,100\n"
        let preview = try session(csv).preview(against: library)
        #expect(preview.record(.valuation("carta", "2026-01-31"))?.imported.balance == 20)
        #expect(preview.record(.valuation("mutuo-casa", "2026-01-31"))?.imported.balance == -146_900)
        #expect(preview.issues.map(\.kind) == [.debtsInCredit("carta", count: 1)])
    }

    /// Applying decides again with the accounts' kinds as they are then: a
    /// proposed account turned into a card joins a column's convention.
    @Test func applyingDecidesTheConventionWithEditedKinds() throws {
        let csv = "Date;Nuovo\n2026-01-31;-320.5\n2026-02-28;20\n"
        var preview = try session(csv).preview(against: Library())
        let index = try #require(preview.newAccounts.firstIndex { $0.account.id == "nuovo" })
        #expect(!preview.newAccounts[index].account.kind.isLiability)
        preview.newAccounts[index].account.kind = .creditCard
        let result = preview.apply(to: Library())
        #expect(result.library.valuations(for: "nuovo").map(\.balance) == [dec("-320.5"), 20])
        // Without the negative value, the card's positive amount is owed.
        var positive = try session("Date;Nuovo\n2026-02-28;20\n").preview(against: Library())
        positive.newAccounts[0].account.kind = .creditCard
        #expect(positive.apply(to: Library()).library.valuations(for: "nuovo").map(\.balance) == [-20])
    }

    @Test func asWrittenKeepsTheFileSigns() throws {
        var session = try session(positive)
        func balance() -> Decimal? {
            session.preview(against: library()).record(.valuation("mutuo-casa", "2026-02-28"))?.imported.balance
        }

        // For the whole profile.
        session.profile.defaults.liabilitySign = .asWritten
        #expect(balance() == 146_250)
        #expect(session.preview(against: library()).issues.isEmpty)
        #expect(session.preview(against: library()).record(.valuation("mutuo-casa", "2026-01-31"))?.status
            == .conflict)

        // A column's own format wins over the profile's defaults, either way.
        var mapping = try #require(session.mapping(forColumn: 3))
        mapping.format = ImportFormat(liabilitySign: .auto)
        session.setMapping(mapping, forColumn: 3)
        #expect(balance() == -146_250)

        session.profile.defaults.liabilitySign = nil
        mapping.format = ImportFormat(liabilitySign: .asWritten)
        session.setMapping(mapping, forColumn: 3)
        #expect(balance() == 146_250)
    }

    @Test func longLayoutNamesTheAccountAsWritten() throws {
        let session = try session("date,account,value\n2026-01-31,Mutuo casa,146900\n2026-01-31,Conto,100\n")
        #expect(session.profile.layout == .long)
        let preview = session.preview(against: library())
        #expect(preview.record(.valuation("mutuo-casa", "2026-01-31"))?.status == .identical)
        #expect(preview.record(.valuation("conto", "2026-01-31"))?.imported.balance == 100)
        #expect(preview.issues == [
            ImportIssue(kind: .positiveDebts("mutuo-casa", count: 1), column: 3, header: "Mutuo casa"),
        ])
    }

    @Test func newDebtAccountsInTheSampleFile() throws {
        let library = try Fixtures.exampleLibrary()
        let preview = try Samples.session("positive-debts.csv").preview(against: library)

        let kinds = Dictionary(uniqueKeysWithValues: preview.newAccounts.map { ($0.account.id, $0.account.kind) })
        #expect(kinds == ["mutuo": .mortgage, "prestito-auto": .loan, "carta-di-credito": .creditCard])
        #expect(preview.issues == [
            ImportIssue(kind: .positiveDebts("mutuo", count: 3), column: 3, header: "Mutuo"),
            ImportIssue(kind: .positiveDebts("prestito-auto", count: 3), column: 4, header: "Prestito auto"),
        ])
        #expect(preview.issues.map(\.description) == [
            "“Mutuo”: positive amounts were read as debts (3 values).",
            "“Prestito auto”: positive amounts were read as debts (3 values).",
        ])

        let result = preview.apply(to: library)
        #expect(result.createdAccounts == ["carta-di-credito", "mutuo", "prestito-auto"])
        #expect(result.library.valuations(for: "mutuo").map(\.balance) == [-146_900, -146_250, -145_600])
        #expect(result.library.valuations(for: "prestito-auto").map(\.balance) == [-8000, -7600, -7200])
        #expect(result.library.valuations(for: "carta-di-credito").map(\.balance)
            == [dec("-320.5"), -410, dec("-150.25")])
        #expect(result.library.valuations(for: "conto-fineco").first { $0.date == "2026-01-31" }?.balance
            == dec("5210.85"))
    }

    @Test func applyingFollowsAnEditedProposalKind() throws {
        var preview = try Samples.session("positive-debts.csv").preview(against: Library())
        let mortgage = try #require(preview.newAccounts.firstIndex { $0.account.id == "mutuo" })
        let current = try #require(preview.newAccounts.firstIndex { $0.account.id == "conto-fineco" })
        #expect(preview.newAccounts[current].account.kind == .cash)
        preview.newAccounts[mortgage].account.kind = .property
        preview.newAccounts[current].account.kind = .loan

        let result = preview.apply(to: Library())
        #expect(result.library.valuations(for: "mutuo").first?.balance == 146_900)
        #expect(result.library.valuations(for: "conto-fineco").first?.balance == dec("-5210.85"))
    }

    @Test func profilesKeepTheSetting() throws {
        var session = try session(positive)
        session.profile.defaults.liabilitySign = .asWritten
        var mapping = try #require(session.mapping(forColumn: 3))
        mapping.format = ImportFormat(liabilitySign: .auto)
        session.setMapping(mapping, forColumn: 3)

        let profile = session.makeProfile(id: "p", name: "P", library: library())
        #expect(profile.defaults.liabilitySign == .asWritten)
        #expect(profile.columns.first { $0.header == "Mutuo casa" }?.format == ImportFormat(liabilitySign: .auto))
        #expect(profile.columns.first { $0.header == "Conto" }?.format == nil)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(profile.defaults), as: UTF8.self)
        #expect(json.contains(#""liabilitySign":"asWritten""#))
        let decoded = try JSONDecoder().decode(ImportProfile.self, from: encoder.encode(profile))
        #expect(decoded == profile)
        let again = try Importer.preview(Data(positive.utf8), profile: decoded, library: library())
        #expect(again.record(.valuation("mutuo-casa", "2026-02-28"))?.imported.balance == -146_250)
    }
}
