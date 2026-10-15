import Foundation
import Model
import Testing

struct SlugTests {
    @Test(arguments: [
        ("Conto Fineco", "conto-fineco"),
        ("Più Crédit", "piu-credit"),
        ("  Old bank (DE)  ", "old-bank-de"),
        ("Straße & Søn", "strasse-son"),
        ("İstanbul", "istanbul"),
        ("VWCE", "vwce"),
        ("--a--b--", "a-b"),
        ("日本", "untitled"),
    ])
    func makesSlugs(name: String, slug: String) {
        #expect(Slug.make(from: name) == slug)
        #expect(Slug.isValid(slug))
    }

    @Test func uniquing() {
        #expect(Slug.unique("directa", among: []) == "directa")
        #expect(Slug.unique("directa", among: ["directa"]) == "directa-2")
        #expect(Slug.unique("directa", among: ["directa", "directa-2", "directa-3"]) == "directa-4")
        let existing: [AccountID] = ["conto-fineco"]
        #expect(AccountID.make(from: "Conto Fineco", existing: existing) == "conto-fineco-2")
        #expect(AccountID.make(from: "Directa", existing: existing) == "directa")
    }

    @Test func validity() {
        #expect(!Slug.isValid(""))
        #expect(!Slug.isValid("Conto"))
        #expect(!Slug.isValid("conto fineco"))
        #expect(Slug.isValid("old-bank"))
    }
}

struct StringValueTests {
    @Test func openEnumsKeepUnknownValues() throws {
        let kinds = try JSONDecoder().decode([AccountKind].self, from: Data(#"["cash","yacht"]"#.utf8))
        #expect(kinds == [.cash, "yacht"])
        #expect(kinds[0].isKnown)
        #expect(!kinds[1].isKnown)
        #expect(String(decoding: try JSONEncoder().encode(kinds), as: UTF8.self) == #"["cash","yacht"]"#)
    }

    @Test func accountFileWithUnknownKindDecodes() throws {
        let json = #"{"currency":"EUR","id":"boat","kind":"boat","name":"Boat","opened":"2026-01-01"}"#
        let account = try JSONDecoder().decode(Account.self, from: Data(json.utf8))
        #expect(account.kind == "boat")
        #expect(account.valuationMode == .balance)
    }

    @Test func codes() {
        #expect(CurrencyCode.eur.isWellFormed)
        #expect(!CurrencyCode("eur").isWellFormed)
        #expect(CountryCode.it.rawValue == "IT")
        #expect(!CountryCode("ITA").isWellFormed)
    }
}
