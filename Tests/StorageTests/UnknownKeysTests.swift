import Foundation
import Model
import Storage
import Testing
import TestSupport

/// Keys the model doesn't know (added by hand, or by a newer app) survive a
/// rewrite by the app.
struct UnknownKeysTests {
    @Test func aHandAddedNoteInAnAccountSurvivesAnEdit() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("accounts/directa.json", """
            {
              "country": "IT",
              "currency": "EUR",
              "id": "directa",
              "includeIn": { "futureFlag": 1, "plan": true },
              "institution": "Directa SIM",
              "kind": "brokerage",
              "myNote": "Opened with a welcome bonus.",
              "name": "Directa",
              "opened": "2021-03-01",
              "tags": ["fire"],
              "tax": { "wrapper": "it.ordinary" }
            }
            """)
        let previous = try folder.library.load().library
        var library = previous
        library.accounts["directa"]?.name = "Directa SIM"
        library.accounts["directa"]?.includeIn = IncludeIn(netWorth: false, plan: true)

        let report = try folder.library.save(library, previous: previous)
        #expect(report.written == ["accounts/directa.json"])
        #expect(try folder.text("accounts/directa.json") == """
            {
              "country": "IT",
              "currency": "EUR",
              "id": "directa",
              "includeIn": { "futureFlag": 1, "netWorth": false, "plan": true },
              "institution": "Directa SIM",
              "kind": "brokerage",
              "myNote": "Opened with a welcome bonus.",
              "name": "Directa SIM",
              "opened": "2021-03-01",
              "tags": ["fire"],
              "tax": { "wrapper": "it.ordinary" }
            }

            """)
    }

    @Test func removingAKnownFieldDoesNotBringItBack() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        var account = try folder.library.load().library.accounts["casa"]!
        account.notes = nil
        account.includeIn = nil
        try folder.library.save(account)
        let json = try folder.json("accounts/casa.json")
        #expect(json["notes"] == nil)
        #expect(json["includeIn"] == nil)
    }

    @Test func unknownKeysInRecordsFollowTheirRecordByKey() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("history/2026/2026-10.json", """
            {
              "checkedBy": "me",
              "month": "2026-10",
              "valuations": [
                { "account": "casa", "balance": "310000", "date": "2026-10-31", "appraisal": "agency" },
                {
                  "account": "directa",
                  "date": "2026-10-31",
                  "positions": [{ "instrument": "vwce", "lot": "A", "quantity": "420" }]
                },
                { "account": "tfr", "balance": "9000", "date": "2026-10-31" }
              ]
            }
            """)
        let previous = try folder.library.load().library
        var library = previous
        // Insert a record before the others, change one, and delete one.
        library.upsert(Valuation(account: "conto-fineco", date: "2026-10-15", balance: 100))
        library.upsert(Valuation(account: "casa", date: "2026-10-31", balance: 315_000))
        library.removeValuation(ValuationKey(account: "tfr", date: "2026-10-31"))
        library.months["2026-10"]?.valuations[2].positions[0].quantity = 425

        try folder.library.save(library, previous: previous)
        #expect(try folder.text("history/2026/2026-10.json") == """
            {
              "checkedBy": "me",
              "fx": [],
              "indices": [],
              "month": "2026-10",
              "prices": [],
              "valuations": [
                { "account": "conto-fineco", "balance": "100", "date": "2026-10-15" },
                { "account": "casa", "appraisal": "agency", "balance": "315000", "date": "2026-10-31" },
                { "account": "directa", "date": "2026-10-31", "positions": [{ "instrument": "vwce", "lot": "A", "quantity": "425" }] }
              ]
            }

            """)
    }

    @Test func recordsTheModelCannotReadAreKeptOnRewrite() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("history/2026/2026-10.json", """
            {
              "month": "2026-10",
              "valuations": [
                { "account": "casa", "balance": "310000", "date": "2026-10-31" },
                { "account": "tfr", "balance": "9000,50", "date": "2026-10-31" }
              ]
            }
            """)
        let result = try folder.library.load()
        #expect(result.report.errors.count == 1)
        var library = result.library
        library.upsert(Valuation(account: "conto-fineco", date: "2026-10-31", balance: 100))

        try folder.library.save(library, previous: result.library)
        let valuations = try #require(folder.json("history/2026/2026-10.json")["valuations"]?.arrayValue)
        #expect(valuations.count == 3)
        #expect(valuations.last?["balance"] == "9000,50")

        // Entering the record again in the app replaces the unreadable one.
        let reloaded = try folder.library.load().library
        var fixed = reloaded
        fixed.upsert(Valuation(account: "tfr", date: "2026-10-31", balance: .d("9000.5")))
        try folder.library.save(fixed, previous: reloaded)
        let final = try folder.library.load()
        #expect(final.report.issues.isEmpty)
        #expect(final.library.months["2026-10"]?.valuations.count == 3)
    }

    @Test func anEmptiedMonthWithUnknownKeysIsKept() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("history/2026/2026-10.json", """
            { "month": "2026-10", "myNote": "keep me", "valuations": [{ "account": "casa", "balance": "1", "date": "2026-10-31" }] }
            """)
        let previous = try folder.library.load().library
        var library = previous
        library.removeValuation(ValuationKey(account: "casa", date: "2026-10-31"))

        let report = try folder.library.save(library, previous: previous)
        #expect(report.written == ["history/2026/2026-10.json"])
        #expect(report.deleted.isEmpty)
        #expect(try folder.json("history/2026/2026-10.json")["myNote"] == "keep me")
        #expect(try folder.json("history/2026/2026-10.json")["valuations"] == [])
    }

    @Test func settingsAndNestedObjectsKeepUnknownKeys() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try folder.write("library.json", """
            {
              "baseCurrency": "EUR",
              "person": { "birthDate": "1988-04-12", "name": "Alex Example", "nickname": "Al" },
              "schemaVersion": 1,
              "theme": "dark"
            }
            """)
        var settings = try folder.library.load().library.settings
        settings.person?.name = "Alex"
        settings.person?.birthDate = nil
        try folder.library.save(settings)
        #expect(try folder.text("library.json") == """
            {
              "baseCurrency": "EUR",
              "person": { "name": "Alex", "nickname": "Al" },
              "schemaVersion": 1,
              "theme": "dark"
            }

            """)
    }

    @Test func headlinesKeepUnknownKeysByDate() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        var file = try Fixtures.decode(HeadlineFile.self, from: "projections/base/headlines/2026.json")
        var json = try CanonicalJSON.json(encoding: file)
        var headlines = json["headlines"]!.arrayValue!
        headlines[0] = headlines[0].objectValue.map { var o = $0; o["comment"] = "first"; return .object(o) }!
        json = ["headlines": .array(headlines)]
        try folder.write("projections/base/headlines/2026.json", CanonicalJSON.data(for: json))

        file.headlines.insert(Headline(date: "2026-01-15", engine: "0.1.0", planHash: "x"), at: 0)
        try folder.library.save(file, year: 2026, plan: "base")
        let saved = try #require(folder.json("projections/base/headlines/2026.json")["headlines"]?.arrayValue)
        #expect(saved[0]["comment"] == nil)
        #expect(saved[1]["comment"] == "first")
        #expect(saved[1]["date"] == "2026-01-31")
    }
}
