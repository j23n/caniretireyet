import Foundation
import Testing
import TestSupport

/// `retire plan debug`: the plan debugger's report on the example library.
struct PlanDebugCommandTests {
    /// A copy of the example library whose plans run 30 times, so a full
    /// report is quick in a debug build.
    func library() throws -> TemporaryFolder {
        let library = try TemporaryFolder.exampleLibrary()
        let plan = try library.text("plans/base.json").replacingOccurrences(of: #""runs": 2000"#, with: #""runs": 30"#)
        try library.write("plans/base.json", plan)
        return library
    }

    @Test func markdownHasEverySection() async throws {
        let library = try library()
        let run = await retire(["plan", "debug", "--library", library.path, "--paths", "2"])
        #expect(run.status == 0, "\(run.all)")
        for heading in ["# Plan debugger: Base case", "## Diagnosis", "## 1. What was run",
                        "## 2. The person and the plan as read", "### Assumptions", "## 3. Starting portfolio",
                        "## 4. Year-by-year schedule (retiring at 38)", "## 5. Simulation summary",
                        "## 6. Percentiles by year (retiring at 38)", "## 7. Traced paths", "## 8. Issues"] {
            #expect(run.output.contains(heading), "\(heading)")
        }
        #expect(run.output.contains("### The deterministic run (expected returns every year)"))
        #expect(run.output.contains("### The median outcome"))
        #expect(run.output.contains("Crypto is "))
        #expect(run.output.contains("| Report made on | 2026-09-30 |"))
        // Names as they are.
        #expect(run.output.contains("Ledger wallet (`ledger-wallet`)"))
    }

    @Test func jsonParsesAndCanGoToAFile() async throws {
        let library = try library()
        let run = await retire(["plan", "debug", "--library", library.path, "--age", "target", "--format", "json",
                                "--output", "reports/base.json", "--path-index", "3", "11"],
                               currentDirectory: library.url)
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output == "Wrote the report on base to reports/base.json.\n")
        let json = try parseJSON(try library.text("reports/base.json"))
        let header = try #require(json["header"] as? [String: Any])
        #expect(header["retirementAge"] as? Int == 55)
        #expect(header["retirementAgeChoice"] as? String == "target")
        #expect(header["runs"] as? Int == 30)
        let paths = try #require(json["paths"] as? [[String: Any]])
        #expect(paths.compactMap { $0["run"] as? Int } == [3, 11])
        #expect(paths.allSatisfy { $0["matchesMainRun"] as? Bool == true })
        for key in ["diagnosis", "person", "plan", "assumptions", "start", "schedule", "simulation", "percentiles",
                    "issues"] {
            #expect(json[key] != nil, "\(key)")
        }
    }

    @Test func anonymizedOutputHasNoNamesOrIDs() async throws {
        let library = try library()
        for format in ["md", "json"] {
            let run = await retire(["plan", "debug", "--library", library.path, "--anonymize", "--format", format,
                                    "--paths", "2"])
            #expect(run.status == 0, "\(run.all)")
            // The example library's names and IDs, except the tax systems'
            // own words they share (the TFR account and the `it.tfr`
            // wrapper, the gold instrument and the asset class).
            let names = ["casa", "Home", "conto-deposito", "Conto deposito", "conto-fineco", "Conto Fineco", "directa",
                         "Directa", "fondo-pensione", "Fondo pensione", "gold-coins", "Gold coins", "ledger-wallet",
                         "Ledger wallet", "mutuo-casa", "Mutuo casa", "old-bank", "Old bank", "btc", "Bitcoin", "vwce",
                         "Vanguard FTSE All-World UCITS ETF (Acc)", "Gold (coins and bars)", "IE00BK5BQT80",
                         "FinecoBank", "Directa SIM", "Banca Esempio", "base", "Base case", "part-time-from-50",
                         "State pension from previous country", "New car", "Alex Example", "1988-04-12"]
            for name in names {
                #expect(!Self.containsWord(name, in: run.output), "\(name) in the \(format) output")
            }
            #expect(run.output.contains("Account 7 (ordinary, crypto)"))
        }
        let json = try parseJSON(await retire(["plan", "debug", "--library", library.path, "--anonymize",
                                               "--round", "100", "--format", "json", "--paths", "1"]).output)
        let header = try #require(json["header"] as? [String: Any])
        let anonymization = try #require(header["anonymization"] as? [String: Any])
        #expect(anonymization["rounding"] as? String == "100")
        let start = try #require(json["start"] as? [String: Any])
        let assets = try #require(start["planAssets"] as? Double)
        #expect(assets.truncatingRemainder(dividingBy: 100) == 0)
    }

    @Test func badOptionsAreRefused() async throws {
        let library = try library()
        let age = await retire(["plan", "debug", "--library", library.path, "--age", "soon"])
        #expect(age.status != 0)
        #expect(age.errors.contains("--age takes today, target or an age"))
        let round = await retire(["plan", "debug", "--library", library.path, "--round", "100"])
        #expect(round.status != 0)
        #expect(round.errors.contains("--round goes with --anonymize"))
        let format = await retire(["plan", "debug", "--library", library.path, "--format", "pdf"])
        #expect(format.errors.contains("--format takes md or json"))
        let scale = await retire(["plan", "debug", "--library", library.path, "--scale", "-2"])
        #expect(scale.status != 0)
    }

    /// Whether `word` appears in `text` as a whole word, ignoring case: not
    /// inside a longer word or ID (letters, digits, `_`, `-`, or a `.` between them).
    static func containsWord(_ word: String, in text: String) -> Bool {
        let lowered = text.lowercased()
        let needle = word.lowercased()
        var searchStart = lowered.startIndex
        func isWord(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "-"
        }
        while let range = lowered.range(of: needle, range: searchStart..<lowered.endIndex) {
            searchStart = lowered.index(after: range.lowerBound)
            if let first = needle.first, isWord(first), range.lowerBound > lowered.startIndex {
                let before = lowered.index(before: range.lowerBound)
                if isWord(lowered[before]) { continue }
                if lowered[before] == ".", before > lowered.startIndex, isWord(lowered[lowered.index(before: before)]) {
                    continue
                }
            }
            if let last = needle.last, isWord(last), range.upperBound < lowered.endIndex {
                if isWord(lowered[range.upperBound]) { continue }
                let next = lowered.index(after: range.upperBound)
                if lowered[range.upperBound] == ".", next < lowered.endIndex, isWord(lowered[next]) { continue }
            }
            return true
        }
        return false
    }
}
