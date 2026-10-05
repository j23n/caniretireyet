import Foundation
import Model
@testable import Storage
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
              "schemaVersion": 3,
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
              "schemaVersion": 3,
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

    // MARK: At any depth

    /// `plans/base.json` with a probe note at every level: the top, nested
    /// objects, dictionary values, and items of every list.
    private func planWithNotes(_ folder: TemporaryFolder) throws {
        var plan = try folder.text("plans/base.json")
        for (original, noted) in [
            ("\"name\": \"Employee\", ", "\"myNote\": \"work note\", \"name\": \"Employee\", "),
            ("{ \"age\": 62, \"amount\"", "{ \"myNote\": \"inheritance note\", \"age\": 62, \"amount\""),
            ("{ \"amount\": \"-25000\"", "{ \"myNote\": \"car note\", \"amount\": \"-25000\""),
            ("{ \"factor\": \"0.9\", \"fromAge\": 75 }", "{ \"factor\": \"0.9\", \"fromAge\": 75, \"myNote\": \"phase note\" }"),
            ("\"equity\": { \"real\": \"0.045\"", "\"equity\": { \"myNote\": \"returns note\", \"real\": \"0.045\""),
            ("{ \"fromAge\": 67, \"name\": \"State pension from", "{ \"fromAge\": 67, \"myNote\": \"pension note\", \"name\": \"State pension from"),
            ("\"tax\": { \"investmentRate\"", "\"tax\": { \"myNote\": \"tax note\", \"investmentRate\""),
            ("\"retirement\": { \"age\": 55 }", "\"retirement\": { \"age\": 55, \"myNote\": \"retirement note\" }"),
        ] {
            #expect(plan.contains(original), "\(original)")
            plan = plan.replacingOccurrences(of: original, with: noted)
        }
        try folder.write("plans/base.json", plan)
    }

    private func notes(in json: JSONValue) -> [String] {
        switch json {
        case .object(let members):
            (members["myNote"]?.stringValue.map { [$0] } ?? []) + members.values.flatMap(notes(in:))
        case .array(let items): items.flatMap(notes(in:))
        default: []
        }
    }

    @Test func notesInListItemsAndDeepObjectsSurviveAnEdit() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try planWithNotes(folder)
        let profile = try folder.text("imports/net-worth-sheet.json").replacingOccurrences(
            of: "{ \"account\": \"directa\", \"header\": \"Directa\"",
            with: "{ \"account\": \"directa\", \"header\": \"Directa\", \"myNote\": \"column note\"")
        try folder.write("imports/net-worth-sheet.json", profile)
        let loaded = try folder.library.load()
        #expect(loaded.report.issues.isEmpty)

        var library = loaded.library
        library.plans["base"]?.name = "Base case (renamed)"
        library.plans["base"]?.work[0].netIncome = 41000
        library.importProfiles["net-worth-sheet"]?.name = "Renamed profile"
        try folder.library.save(library, previous: loaded.library)

        #expect(try notes(in: folder.json("plans/base.json")).sorted() == [
            "car note", "inheritance note", "pension note", "phase note", "retirement note", "returns note",
            "tax note", "work note",
        ])
        let plan = try folder.json("plans/base.json")
        #expect(plan["work"]?[0]?["myNote"] == "work note")
        #expect(plan["work"]?[0]?["netIncome"] == "41000")
        #expect(plan["assumptions"]?["returns"]?["equity"]?["myNote"] == "returns note")
        #expect(try folder.json("imports/net-worth-sheet.json")["columns"]?[1]?["myNote"] == "column note")
        #expect(try folder.library.load().library == library)
    }

    @Test func notesFollowTheirListItemWhenItemsMoveOrGo() throws {
        let folder = try TemporaryFolder.exampleLibrary()
        try planWithNotes(folder)
        let previous = try folder.library.load().library
        var library = previous
        var plan = try #require(library.plans["base"])
        // The first event goes; the second is renamed. A phase is added in front.
        plan.events.removeFirst()
        plan.events[0].name = "Newer car"
        plan.spending.phases.insert(SpendingPhase(fromAge: 60, factor: 1), at: 0)
        // A key the model knows, removed in the app, stays removed.
        plan.pensions[1].name = nil
        library.plans["base"] = plan
        try folder.library.save(library, previous: previous)

        let json = try folder.json("plans/base.json")
        #expect(json["events"]?.arrayValue?.count == 1)
        #expect(json["events"]?[0]?["myNote"] == "car note")
        #expect(json["spending"]?["phases"]?[0]?["myNote"] == nil)
        #expect(json["spending"]?["phases"]?[1]?["myNote"] == "phase note")
        #expect(json["pensions"]?[1]?["name"] == nil)
        #expect(json["pensions"]?[1]?["myNote"] == "pension note")
        #expect(!notes(in: json).contains("inheritance note"))
    }

    @Test func listItemsArePairedByNaturalKeyThenPosition() {
        let old: [JSONValue] = [["name": "a", "x": 1], ["name": "b", "x": 2], ["name": "c", "x": 3]]
        let new: [JSONValue] = [["name": "c"], ["name": "renamed"], ["name": "a"]]
        let pairs = ListMatching.pairs(old: old, new: new).map { [$0.old, $0.new] }
        #expect(pairs == [[2, 0], [1, 1], [0, 2]])
        // Without a natural key, by position.
        let unnamed: [JSONValue] = [["x": 1], ["x": 2]]
        #expect(ListMatching.pairs(old: unnamed, new: [["x": 5]]).map { [$0.old, $0.new] } == [[0, 0]])
        // Numbers and text are the same key.
        #expect(ListMatching.naturalKey([["fromAge": 75]], [["fromAge": "75"]]) == "fromAge")
    }
}
