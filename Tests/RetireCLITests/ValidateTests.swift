import Foundation
import Testing

struct ValidateTests {
    @Test func theExampleLibraryIsClean() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["validate", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output == """
            Library \(library.path)
              Format version  2 (current)
              Read-only       no
              Files read      31
              Contents        10 accounts (1 closed), 3 instruments, 12 months of history (2025-10 to 2026-09), \
            2 plans, 1 import profile

            No problems found.

            """)
    }

    /// A library with a broken file, and references between files that don't hold.
    private func brokenLibrary() throws -> TemporaryFolder {
        let library = try TemporaryFolder.exampleLibrary()
        // An amount that isn't a decimal: an error, the record is left out.
        var october = try library.text("history/2025/2025-10.json")
        october = october.replacingOccurrences(of: #""balance": "4820.3""#, with: #""balance": "4.820,30""#)
        try library.write("history/2025/2025-10.json", october)
        // A valuation of an account that doesn't exist, a positive mortgage,
        // and one after an account closed.
        var september = try library.text("history/2026/2026-09.json")
        september = september.replacingOccurrences(of: #""balance": "-141050""#, with: #""balance": "141050""#)
        september = september.replacingOccurrences(of: #"  "valuations": ["#, with: """
              "valuations": [
                { "account": "ghost", "balance": "1", "date": "2026-09-30" },
                { "account": "old-bank", "balance": "10", "date": "2026-09-30" },
            """)
        try library.write("history/2026/2026-09.json", september)
        // A plan naming a tax system and an account that don't exist.
        var plan = try library.text("plans/base.json")
        plan = plan.replacingOccurrences(of: #""system": "it""#, with: #""system": "xx""#)
        plan = plan.replacingOccurrences(of: #""account": "fondo-pensione""#, with: #""account": "fondo-vecchio""#)
        try library.write("plans/base.json", plan)
        return library
    }

    @Test func reportsErrorsAndWarningsPerFile() async throws {
        let library = try brokenLibrary()
        let run = await retire(["validate", "--library", library.path])
        #expect(run.status == 1)
        let output = run.output
        #expect(output.contains("""
            history/2025/2025-10.json
              error   valuations[2].balance: Expected a decimal such as "1234.56", found "4.820,30".
            """))
        #expect(output.contains("""
            history/2026/2026-09.json
              warning Refers to accounts that don't exist: ghost.
              warning old-bank has a valuation on 2026-09-30 but closed on 2025-11-15, so it doesn't count.
              warning mutuo-casa is a debt (mortgage) but has a positive balance on 2026-09-30. \
            Debts are recorded as negative amounts.
            """))
        #expect(output.contains("""
            plans/base.json
              warning contributions[0].account: the account "fondo-vecchio" doesn't exist.
              warning tax.residence[0].system: "xx" isn't a tax system this version knows (it, generic).
            """))
        #expect(output.hasSuffix("\n1 error, 5 warnings.\n"))
    }

    @Test func warningsAloneExitZeroUnlessStrict() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        var account = try library.text("accounts/directa.json")
        account = account.replacingOccurrences(of: "it.ordinary", with: "it.nothing")
        try library.write("accounts/directa.json", account)

        let run = await retire(["validate", "--library", library.path])
        #expect(run.status == 0)
        #expect(run.output.contains("""
            accounts/directa.json
              warning tax.wrapper: "it.nothing" isn't a wrapper any tax system defines.
            """))
        #expect(run.output.hasSuffix("0 errors, 1 warning.\n"))
        let strict = await retire(["validate", "--library", library.path, "--strict"])
        #expect(strict.status == 1)
    }

    @Test func missingPricesAreWarnings() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        var october = try library.text("history/2025/2025-10.json")
        october = october.replacingOccurrences(
            of: #"    { "currency": "EUR", "date": "2025-10-31", "instrument": "vwce", "price": "128.1", "source": "yahoo" }"#,
            with: "")
        october = october.replacingOccurrences(of: #""source": "gold-api" },"#, with: #""source": "gold-api" }"#)
        try library.write("history/2025/2025-10.json", october)
        let run = await retire(["validate", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("""
            history/2025/2025-10.json
              warning Net worth can't be fully computed on 2025-10-31: directa: no price for vwce.
            """))
    }

    @Test func jsonReport() async throws {
        let library = try brokenLibrary()
        let run = await retire(["validate", "--library", library.path, "--json"])
        #expect(run.status == 1)
        let json = try parseJSON(run.output)
        #expect(json["schemaVersion"] as? Int == 2)
        #expect(json["readOnly"] as? Bool == false)
        #expect(json["errors"] as? Int == 1)
        #expect(json["warnings"] as? Int == 5)
        let issues = try #require(json["issues"] as? [[String: Any]])
        #expect(issues.first?["path"] as? String == "history/2025/2025-10.json")
        #expect(issues.first?["severity"] as? String == "error")
    }

    @Test func aNewerLibraryIsReadOnly() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let settings = try library.text("library.json").replacingOccurrences(of: #""schemaVersion": 2"#,
                                                                              with: #""schemaVersion": 3"#)
        try library.write("library.json", settings)
        let run = await retire(["validate", "--library", library.path])
        #expect(run.output.contains("  Format version  3, newer than this version understands (2)\n"))
        #expect(run.output.contains("  Read-only       yes: update the app to make changes\n"))
    }

    @Test func tradesThatNeedMoreThanTheirFileAreChecked() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        // A statement listing one VWCE too few, and a sale of more than Directa holds.
        var september = try library.text("history/2026/2026-09.json")
        september = september.replacingOccurrences(
            of: #"{ "account": "directa", "cash": "312.1", "date": "2026-09-30", "flow": "11.3" }"#,
            with: #"{ "account": "directa", "cash": "312.1", "date": "2026-09-30", "flow": "11.3", "#
                + #""positions": [{ "instrument": "vwce", "quantity": "411.5" }] }"#)
        september = september.replacingOccurrences(of: "  \"valuations\": [\n", with: """
              "trades": [
                { "account": "directa", "amount": "60000", "date": "2026-09-29", "id": "toomuch1", "instrument": "vwce", "quantity": "500", "type": "sell" }
              ],
              "valuations": [

            """)
        try library.write("history/2026/2026-09.json", september)
        let run = await retire(["validate", "--library", library.path])
        #expect(run.output.contains("warning The sell of vwce in directa on 2026-09-29 (toomuch1) takes away 87.5 "
            + "more than the account held then (412.5). Is a buy or an opening missing, or the date wrong?"),
                "\(run.all)")
        #expect(run.output.contains("warning directa: The valuation on 2026-09-30 lists 411.5 vwce, but the trades "
            + "give -87.5. Is a trade missing or wrong?"), "\(run.all)")
    }

    @Test func aFolderWithoutALibrary() async throws {
        let folder = try TemporaryFolder()
        let run = await retire(["validate", "--library", folder.path])
        #expect(run.status == 1)
        #expect(run.output.contains("library.json\n  error   The file is missing, so this folder may not be a library."))

        let missing = await retire(["validate", "--library", folder.url("nope").path])
        #expect(missing.status == 1)
        #expect(missing.errors.contains("doesn't exist"))
    }
}
