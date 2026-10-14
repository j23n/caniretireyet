import Foundation
import Model
import Storage
import Testing
import TestSupport
import Tracker

/// `retire import` with `Samples/sheet.csv` against the example library. The
/// sheet has August to October 2026 for Conto Fineco and Conto deposito (one
/// value differs from the library), the mortgage written as positive amounts,
/// a new account "Conto Arancio" whose values stop in September, and notes.
struct ImportTests {
    /// The day the imports run: after the samples' last dates (`sheet.csv`'s
    /// 31 October 2026, `broken.csv`'s December, `ambiguous.csv`'s 2027), as
    /// a date more than a week after today is a cell problem.
    private static let today: CalendarDate = "2027-04-30"

    /// `retire` on ``today``.
    private func runCLI(_ arguments: [String], clock: TestClock = TestClock()) async -> CLIRun {
        await retire(arguments, today: Self.today, clock: clock)
    }

    private func sheet() throws -> String {
        try Samples.url("sheet.csv").path
    }

    @Test func dryRunWritesNothing() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let before = try library.snapshot()
        let run = await runCLI(["import", try sheet(), "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        #expect(try library.snapshot() == before)
        #expect(!library.exists("backups"))
    }

    @Test func applyRoundTripAndUndo() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let clock = TestClock()
        let original = try library.snapshot()

        // Without the accept flags: the new account's records are left out,
        // and the undecided conflict keeps the library's value.
        let first = await runCLI(["import", try sheet(), "--library", library.path, "--apply"], clock: clock)
        #expect(first.status == 0, "\(first.all)")
        var loaded = try library.load()
        #expect(loaded.valuations(for: "mutuo-casa").last?.balance == -140_400)
        #expect(loaded.valuations(for: "conto-deposito").first { $0.date == "2026-09-30" }?.balance
            == d("17365.55"))
        #expect(loaded.accounts["conto-arancio"] == nil)
        var backups = try library.backups()
        #expect(backups.map(\.label) == ["import"])
        #expect(backups[0].files.isEmpty)
        #expect(backups[0].absentFiles == ["history/2026/2026-10.json"])
        // Only the new month file changed.
        var changed = try library.snapshot().filter { original[$0.key] != $0.value }.keys.sorted()
        #expect(changed == ["history/2026/2026-10.json"])

        // Again without the flags: the conflict is all that differs, and it is kept.
        let kept = await runCLI(["import", try sheet(), "--library", library.path, "--apply"], clock: clock)
        #expect(kept.status == 0, "\(kept.all)")
        #expect(try library.backups().count == 1)

        // With the flags: the account is created and closed, the conflict overwritten.
        let second = await runCLI(["import", try sheet(), "--library", library.path, "--apply",
                                   "--accept-new-accounts", "--accept-closings", "--on-conflict", "overwrite"],
                                  clock: clock)
        #expect(second.status == 0, "\(second.all)")
        loaded = try library.load()
        #expect(loaded.accounts["conto-arancio"]?.closed == "2026-10-01")
        #expect(loaded.accounts["conto-arancio"]?.kind == .cash)
        #expect(loaded.valuations(for: "conto-arancio").map(\.balance) == [2000, 2100])
        #expect(loaded.valuations(for: "conto-deposito").first { $0.date == "2026-09-30" }?.balance == 17_400)
        changed = try library.snapshot().filter { original[$0.key] != $0.value }.keys.sorted()
        #expect(changed == ["accounts/conto-arancio.json", "history/2026/2026-08.json", "history/2026/2026-09.json",
                            "history/2026/2026-10.json"])

        // Again: nothing left to do, and no backup.
        let third = await runCLI(["import", try sheet(), "--library", library.path, "--apply",
                                  "--accept-new-accounts", "--accept-closings", "--on-conflict", "overwrite"],
                                 clock: clock)
        #expect(third.status == 0, "\(third.all)")
        #expect(try library.backups().count == 2)

        // Undo twice: back to the library as it was.
        let undo = await runCLI(["import", "--undo", "--library", library.path], clock: clock)
        #expect(undo.status == 0, "\(undo.all)")
        #expect(try library.load().accounts["conto-arancio"] == nil)
        #expect(try library.load().valuations(for: "mutuo-casa").last?.balance == -140_400)
        let undoAgain = await runCLI(["import", "--undo", "--library", library.path], clock: clock)
        #expect(undoAgain.status == 0, "\(undoAgain.all)")
        #expect(try library.snapshot() == original)
        backups = try library.backups()
        #expect(backups.map(\.label) == ["import", "import", "undo-import", "undo-import"])

        let nothing = await runCLI(["import", "--undo", "--library", library.path], clock: clock)
        #expect(nothing.status == 1)
    }

    @Test func undoLeavesEditsMadeAfterTheImportInPlace() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let clock = TestClock()
        let imported = await runCLI(["import", try sheet(), "--library", library.path, "--apply",
                                     "--accept-new-accounts", "--accept-closings", "--on-conflict", "overwrite"],
                                    clock: clock)
        #expect(imported.status == 0, "\(imported.all)")
        #expect(try library.backups().first?.result != nil)

        // Later: a check-in on 2026-10-31 that corrects an imported value and adds another account.
        let before = try library.load()
        var edited = before
        edited.upsert(Valuation(account: "conto-deposito", date: "2026-10-31", balance: 18_000))
        edited.upsert(Valuation(account: "tfr", date: "2026-10-31", balance: 9000))
        try library.library.save(edited, previous: before)

        let undo = await runCLI(["import", "--undo", "--library", library.path], clock: clock)
        #expect(undo.status == 0, "\(undo.all)")
        let after = try library.load()
        #expect(after.accounts["conto-arancio"] == nil)
        #expect(after.valuations(for: "conto-arancio").isEmpty)
        let october = after.months["2026-10"]?.valuations ?? []
        #expect(october.map(\.account) == ["conto-deposito", "tfr"])
        #expect(october.first?.balance == 18_000)
    }

    @Test func undoDryRunShowsWhatItWouldRestore() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        _ = await runCLI(["import", try sheet(), "--library", library.path, "--apply"])
        let after = try library.snapshot()
        let run = await runCLI(["import", "--undo", "--dry-run", "--library", library.path])
        #expect(run.status == 0)
        #expect(run.output.contains("history/2026/2026-10.json"))
        #expect(try library.snapshot() == after)
    }

    @Test func savedProfileIsReused() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let save = await runCLI(["import", try sheet(), "--library", library.path, "--save-profile", "bank-sheet",
                                 "--profile-name", "My bank sheet"])
        #expect(save.status == 0, "\(save.all)")
        let profile = try #require(try library.load().importProfiles["bank-sheet"])
        #expect(profile.name == "My bank sheet")
        #expect(profile.dateColumn == "Data")
        #expect(profile.defaults.date?.pattern == "dd/MM/yyyy")
        #expect(profile.defaults.number == ImportNumberFormat(decimal: ",", thousands: "."))
        #expect(profile.columns.map(\.header) == ["Conto Fineco", "Conto deposito", "Mutuo casa", "Conto Arancio",
                                                  "Note"])
        #expect(profile.columns.map(\.account) == ["conto-fineco", "conto-deposito", "mutuo-casa", nil, nil])

        // The saved profile reads the file the same way.
        let reuse = try parseJSON(await runCLI(["import", try sheet(), "--library", library.path, "--profile",
                                                "bank-sheet", "--json"]).output)
        #expect(reuse["profile"] as? String == "bank-sheet")
        let summary = try #require(reuse["summary"] as? [String: Any])
        #expect(summary["new"] as? Int == 5)
        #expect(summary["identical"] as? Int == 5)
        #expect(summary["conflicts"] as? Int == 1)

        // Another profile isn't replaced by accident.
        let clash = await runCLI(["import", try sheet(), "--library", library.path, "--save-profile",
                                  "net-worth-sheet"])
        #expect(clash.status == 1)
        let unknown = await runCLI(["import", try sheet(), "--library", library.path, "--profile", "nope"])
        #expect(unknown.status == 1)
    }

    /// The wallet's quantities make a new sale on January 31 and a buy on March 31 that differs from the
    /// library's. While that conflict keeps the library's buy, the sale is left out with it, and the report
    /// says why.
    @Test func tradesLeftOutUntilTheirConflictsAreOverwrittenAreNamed() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        try library.write("wallet.csv", "Data;Conto Fineco;Directa;BTC (qtà);Oro;Note\n31/01/2026;;;0,215;;\n"
            + "31/03/2026;;;0,2201;;\n")
        let arguments = ["import", library.path + "/wallet.csv", "--library", library.path, "--profile",
                         "net-worth-sheet", "--encoding", "utf-8"]
        let json = try parseJSON(await runCLI(arguments + ["--json"]).output)
        let summary = try #require(json["summary"] as? [String: Any])
        let leftOut = try #require(summary["tradesLeftOutUntilOverwritten"] as? [[String: Any]])
        #expect(leftOut.map { "\($0["account"] ?? "") \($0["trades"] ?? "")" } == ["ledger-wallet 1"])

        let overwritten = try parseJSON(await runCLI(arguments + ["--on-conflict", "overwrite", "--json"]).output)
        let overwrittenSummary = try #require(overwritten["summary"] as? [String: Any])
        #expect((overwrittenSummary["tradesLeftOutUntilOverwritten"] as? [Any])?.isEmpty == true)
    }

    /// A month inserted between two check-ins writes only its own month:
    /// what the later month saved is worked out from it, not stored.
    @Test func insertingAMonthWritesOnlyItsOwnMonth() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        // February is missing for the current account and the savings account.
        var gap = try library.load()
        let before = gap
        gap.removeValuation(ValuationKey(account: "conto-fineco", date: "2026-02-28"))
        gap.removeValuation(ValuationKey(account: "conto-deposito", date: "2026-02-28"))
        try library.library.save(gap, previous: before)
        let saved = try library.snapshot()

        let files = try TemporaryFolder()
        try files.write("february.csv", "Data;Conto Fineco;Conto deposito\n28/02/2026;4.780,20;15.626,95\n")
        let run = await runCLI(["import", files.url("february.csv").path, "--library", library.path, "--apply"])
        #expect(run.status == 0, "\(run.all)")
        let changed = try library.snapshot().filter { saved[$0.key] != $0.value }.keys.sorted()
        #expect(changed == ["history/2026/2026-02.json"])

        let loaded = try library.load()
        let valuator = Valuator(library: loaded)
        func flow(_ account: AccountID) -> Decimal? {
            let values = loaded.valuations(for: account)
            guard let index = values.firstIndex(where: { $0.date == "2026-03-31" }) else { return nil }
            return valuator.flow(of: values[index], previous: values[index - 1])
        }
        // What March saved is the change since February: 5530.10 − 4780.20.
        #expect(flow("conto-fineco") == d("749.9"))
        // The savings account's is the change less March's interest: 16,159.50 − 15,626.95 − 32.55.
        #expect(flow("conto-deposito") == 500)
    }

    @Test func applyingWithAProfileAndSavingItIsOneUndo() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let original = try library.snapshot()
        let run = await runCLI(["import", try sheet(), "--library", library.path, "--apply", "--accept-new-accounts",
                                "--save-profile", "bank-sheet"])
        #expect(run.status == 0, "\(run.all)")
        // The new account's ID is written into the profile.
        let profile = try #require(try library.load().importProfiles["bank-sheet"])
        #expect(profile.columns.first { $0.header == "Conto Arancio" }?.account == "conto-arancio")
        _ = await runCLI(["import", "--undo", "--library", library.path])
        #expect(try library.snapshot() == original)
    }

    @Test func debtsCanKeepTheirSigns() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let json = try parseJSON(await runCLI(["import", try sheet(), "--library", library.path, "--liability-sign",
                                               "as-written", "--json"]).output)
        let summary = try #require(json["summary"] as? [String: Any])
        #expect(summary["notes"] as? Int == 0)
        // The mortgage's two values the library has become conflicts.
        #expect(summary["identical"] as? Int == 3)
        #expect(summary["conflicts"] as? Int == 3)
    }

    @Test func guessedFormatsBlockApplyUntilSettled() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let file = try Samples.url("ambiguous.csv").path
        let before = try library.snapshot()

        let preview = try parseJSON(await runCLI(["import", file, "--library", library.path, "--json"]).output)
        let ambiguities = try #require(preview["ambiguities"] as? [[String: Any]])
        #expect(ambiguities.contains { Set($0["options"] as? [String] ?? []) == ["dd/MM/yyyy", "MM/dd/yyyy"] })

        let blocked = await runCLI(["import", file, "--library", library.path, "--apply"])
        #expect(blocked.status == 1)
        #expect(try library.snapshot() == before)

        let settled = await runCLI(["import", file, "--library", library.path, "--apply", "--date-format",
                                    "dd/MM/yyyy"])
        #expect(settled.status == 0, "\(settled.all)")
        let dates = try library.load().valuations(for: "conto-fineco").map(\.date).filter { $0.year == 2027 }
        #expect(dates == ["2027-02-01", "2027-03-02", "2027-04-03"])
    }

    @Test func acceptingGuesses() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let file = try Samples.url("ambiguous.csv").path
        let run = await runCLI(["import", file, "--library", library.path, "--apply", "--accept-guesses"])
        #expect(run.status == 0, "\(run.all)")
        #expect(try library.load().valuations(for: "conto-fineco").filter { $0.date.year == 2027 }.count == 3)
    }

    /// On the test day, 30 September 2026, the sheet's 31 October is more
    /// than a week ahead: most likely a typo, so its row is a cell error.
    @Test func datesMoreThanAWeekAheadAreCellErrors() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["import", try sheet(), "--library", library.path, "--json"])
        #expect(run.status == 0, "\(run.all)")
        let cellErrors = try #require(try parseJSON(run.output)["cellErrors"] as? [[String: Any]])
        #expect(cellErrors.map { $0["row"] as? Int } == [4])
    }

    @Test func jsonPreviewAndResult() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let dryRun = try parseJSON(await runCLI(["import", try sheet(), "--library", library.path, "--json"]).output)
        #expect(dryRun["mode"] as? String == "dry-run")
        let summary = try #require(dryRun["summary"] as? [String: Any])
        #expect(summary["new"] as? Int == 5)
        #expect(summary["conflicts"] as? Int == 1)
        #expect(summary["notes"] as? Int == 1)
        #expect(summary["leftOut"] as? Int == 2)
        let settings = try #require(dryRun["settings"] as? [String: Any])
        #expect(settings["datePattern"] as? String == "dd/MM/yyyy")
        let columns = try #require(dryRun["columns"] as? [[String: Any]])
        #expect(columns.map { $0["header"] as? String } == ["Data", "Conto Fineco", "Conto deposito", "Mutuo casa",
                                                           "Conto Arancio", "Note"])
        let records = try #require(dryRun["records"] as? [[String: Any]])
        #expect(records.count == 11)
        let conflict = try #require(records.first { $0["status"] as? String == "conflict" })
        #expect(conflict["existing"] as? String == "balance 17,365.55")
        #expect(dryRun["result"] == nil)

        let applied = try parseJSON(await runCLI(["import", try sheet(), "--library", library.path, "--json",
                                                  "--apply"]).output)
        let result = try #require(applied["result"] as? [String: Any])
        #expect(result["added"] as? Int == 3)
        #expect(result["written"] as? [String] == ["history/2026/2026-10.json"])
        #expect((result["backup"] as? String)?.hasPrefix("backups/") == true)
    }

    @Test func aBankStatementBecomesAValueWithMoneyInAndOut() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let statement = try Samples.url("statement.csv").path
        let arguments = ["import", statement, "--library", library.path, "--account", "conto-fineco",
                         "--class", "Spesa=spending"]
        let run = await runCLI(arguments)
        #expect(run.status == 0, "\(run.all)")

        let json = try parseJSON(await runCLI(arguments + ["--json"]).output)
        let lines = try #require(json["statementLines"] as? [[String: Any]])
        #expect(lines.map { $0["class"] as? String } == ["spending", "income", "transfer", "transfer", "spending"])
        #expect(lines.map { $0["source"] as? String } == ["sign", "usual words", "account", "usual words", "rule"])
        #expect(lines.allSatisfy { $0["value"] as? String == "2026-10-31" })

        let applied = await runCLI(arguments + ["--apply"])
        #expect(applied.status == 0, "\(applied.all)")
        let loaded = try library.load()
        let values = loaded.valuations(for: "conto-fineco")
        let written = try #require(values.last)
        #expect(written == Valuation(account: "conto-fineco", date: "2026-10-31", balance: d("5480.15"),
                                     moneyIn: 3400, moneyOut: d("1380.4"), source: .import))
        // What it saved is worked out from the value before.
        #expect(Valuator(library: loaded).flow(of: written, previous: values.dropLast().last) == d("1269.6"))
        let afterApply = try library.snapshot()
        let again = await runCLI(arguments + ["--apply"])
        #expect(again.status == 0, "\(again.all)")
        #expect(try library.snapshot() == afterApply)
    }

    @Test func aLargeLineInNeedsAnAnswerAndCanBeAOneOff() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let folder = try TemporaryFolder()
        let csv = try String(contentsOf: Samples.url("statement.csv"), encoding: .utf8)
            + "20/10/2026;5.000,00;Bonifico da Notaio Bianchi\n"
        try folder.write("statement.csv", Data(csv.utf8))
        let arguments = ["import", folder.url("statement.csv").path, "--library", library.path,
                         "--account", "conto-fineco"]
        let json = try parseJSON(await runCLI(arguments + ["--json"]).output)
        let lines = try #require(json["statementLines"] as? [[String: Any]])
        let large = try #require(lines.first { $0["text"] as? String == "Bonifico da Notaio Bianchi" })
        #expect(large["sender"] as? String == "Notaio Bianchi")
        #expect(large["needsAnswer"] as? Bool == true)
        #expect(large["class"] as? String == "spending")

        let answered = try parseJSON(await runCLI(arguments + ["--class", "Notaio Bianchi=oneOff", "--json"]).output)
        let answeredLines = try #require(answered["statementLines"] as? [[String: Any]])
        let oneOff = try #require(answeredLines.first { $0["text"] as? String == "Bonifico da Notaio Bianchi" })
        #expect(oneOff["class"] as? String == "oneOff")
        #expect(oneOff["needsAnswer"] as? Bool == false)
    }

    @Test func aLineCanMoveMoneyToAnAccount() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let folder = try TemporaryFolder()
        let csv = try String(contentsOf: Samples.url("statement.csv"), encoding: .utf8)
            + "20/10/2026;-5.000,00;Bonifico a Directa SIM rif 7\n"
            + "22/10/2026;-1.200,00;Pagamento F24 Agenzia delle Entrate\n"
        try folder.write("statement.csv", Data(csv.utf8))
        let arguments = ["import", folder.url("statement.csv").path, "--library", library.path,
                         "--account", "conto-fineco", "--move", "rif 7=directa", "--json"]
        let json = try parseJSON(await runCLI(arguments).output)
        let lines = try #require(json["statementLines"] as? [[String: Any]])
        let moved = try #require(lines.first { $0["text"] as? String == "Bonifico a Directa SIM rif 7" })
        #expect(moved["class"] as? String == "transfer")
        #expect(moved["source"] as? String == "rule")
        #expect(moved["asset"] as? String == "moved")
        #expect(moved["assetAccount"] as? String == "directa")
        let tax = try #require(lines.first { $0["text"] as? String == "Pagamento F24 Agenzia delle Entrate" })
        #expect(tax["class"] as? String == "tax")

        let invalid = await runCLI(["import", folder.url("statement.csv").path, "--library", library.path,
                                    "--account", "conto-fineco", "--move", "rif 7"])
        #expect(invalid.status == 64)
    }

    @Test func aPurchaseStartsAnAccountAndASaleClosesOne() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let folder = try TemporaryFolder()
        let csv = try String(contentsOf: Samples.url("statement.csv"), encoding: .utf8)
            + "21/10/2026;-18.000,00;Bonifico a Autosalone Neri\n"
            + "22/10/2026;320.000,00;Rogito notaio vendita\n"
        try folder.write("statement.csv", Data(csv.utf8))
        let arguments = ["import", folder.url("statement.csv").path, "--library", library.path,
                         "--account", "conto-fineco"]
        let asked = try parseJSON(await runCLI(arguments + ["--json"]).output)
        let askedLines = try #require(asked["statementLines"] as? [[String: Any]])
        #expect(askedLines.first { $0["row"] as? Int == 7 }?["needsAnswer"] as? Bool == true)

        let answered = arguments + ["--purchase", "Autosalone=belongings:Auto", "--sale", "8=casa"]
        let json = try parseJSON(await runCLI(answered + ["--json"]).output)
        let lines = try #require(json["statementLines"] as? [[String: Any]])
        let car = try #require(lines.first { $0["row"] as? Int == 7 })
        #expect(car["class"] as? String == "transfer")
        #expect(car["asset"] as? String == "purchase")
        #expect(car["assetAccount"] as? String == "auto")
        #expect(car["needsAnswer"] as? Bool == false)
        let house = try #require(lines.first { $0["row"] as? Int == 8 })
        #expect(house["asset"] as? String == "sale")
        #expect(house["assetAccount"] as? String == "casa")

        let applied = await runCLI(answered + ["--apply"])
        #expect(applied.status == 0, "\(applied.all)")
        let written = try library.load()
        #expect(written.accounts["auto"]?.kind == .belongings)
        #expect(written.valuations(for: "auto").map(\.balance) == [0, 18000])
        #expect(written.accounts["casa"]?.closed == "2026-10-23")
        #expect(written.valuations(for: "casa").last?.balance == 0)

        let many = await runCLI(arguments + ["--purchase", "Bonifico=belongings:Auto"])
        #expect(many.status == 1)
        let badKind = await runCLI(arguments + ["--purchase", "Autosalone=cash:Auto"])
        #expect(badKind.status == 64)
        let twice = await runCLI(arguments + ["--purchase", "7=belongings:Auto", "--sale", "Autosalone=casa"])
        #expect(twice.status == 1)
    }

    @Test func aStatementNeedsAnAccountThatRecordsMoneyInAndOut() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let statement = try Samples.url("statement.csv").path
        let broker = try parseJSON(await runCLI(["import", statement, "--library", library.path, "--account",
                                                 "directa", "--json"]).output)
        #expect((broker["issues"] as? [Any])?.isEmpty == false)
        let badClass = await runCLI(["import", statement, "--library", library.path, "--class", "Spesa=food"])
        #expect(badClass.status == 64)
        let badBalance = await runCLI(["import", statement, "--library", library.path, "--opening-balance", "1.234,5"])
        #expect(badBalance.status == 64)
    }

    @Test func aStatementsDaysCanBeGiven() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let statement = try Samples.url("statement.csv").path
        let arguments = ["import", statement, "--library", library.path, "--account", "conto-fineco"]
        let through = try parseJSON(await runCLI(arguments + ["--through", "2026-10-29", "--json"]).output)
        let dates = try #require(through["records"] as? [[String: Any]]).compactMap { $0["date"] as? String }
        #expect(dates.contains("2026-10-29"))
        #expect(!dates.contains("2026-10-31"))

        // A line before --from is one more issue than without it.
        func issues(_ extra: [String]) async throws -> Int {
            let json = try parseJSON(await runCLI(arguments + extra + ["--json"]).output)
            return (json["issues"] as? [Any])?.count ?? 0
        }
        let plain = try await issues([])
        let late = try await issues(["--from", "2026-10-02"])
        #expect(late == plain + 1)
        for bad in [["--through", "29/10/2026"], ["--from", "2026-10-20", "--through", "2026-10-10"],
                    ["--through", "2027-05-31"]] {
            let run = await runCLI(arguments + bad)
            #expect(run.status == 64, "\(bad): \(run.all)")
        }
    }

    @Test func aLibraryFromANewerAppIsNotWritten() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let settings = try library.text("library.json").replacingOccurrences(of: #""schemaVersion": 5"#,
                                                                              with: #""schemaVersion": 6"#)
        try library.write("library.json", settings)
        let before = try library.snapshot()
        let run = await runCLI(["import", try sheet(), "--library", library.path, "--apply"])
        #expect(run.status == 1)
        #expect(try library.snapshot() == before)
        #expect(!library.exists("backups"))
    }

    @Test func argumentsAreChecked() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let noFile = await runCLI(["import", "--library", library.path])
        #expect(noFile.status == 64)
        let both = await runCLI(["import", try sheet(), "--library", library.path, "--apply", "--dry-run"])
        #expect(both.status == 64)
        let badID = await runCLI(["import", try sheet(), "--library", library.path, "--save-profile", "My Sheet"])
        #expect(badID.status == 64)
        let layout = await runCLI(["import", try sheet(), "--library", library.path, "--profile", "net-worth-sheet",
                                   "--layout", "long"])
        #expect(layout.status == 64)
        let missing = await runCLI(["import", library.url("nope.csv").path, "--library", library.path])
        #expect(missing.status == 1)
    }
}
