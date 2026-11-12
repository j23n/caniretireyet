import Foundation
import Testing
import TestSupport

/// `retire plan debug`: every calculation behind a plan's answer, as
/// Markdown (`Planner.calculations`), on the example library.
struct PlanDebugCommandTests {
    /// A copy of the example library whose plans run 30 times, so a full
    /// report is quick in a debug build.
    func library() throws -> TemporaryFolder {
        let library = try TemporaryFolder.exampleLibrary()
        let plan = try library.text("plans/base.json").replacingOccurrences(of: #""runs": 2000"#, with: #""runs": 30"#)
        try library.write("plans/base.json", plan)
        return library
    }

    @Test func theReportCanGoToAFile() async throws {
        let library = try library()
        let run = await retire(["plan", "debug", "--library", library.path, "--output", "reports/base.md"],
                               currentDirectory: library.url)
        #expect(run.status == 0, "\(run.all)")
        #expect(try library.text("reports/base.md").hasPrefix("# Calculations: Base case\n"))
    }

    @Test func anonymizedOutputHasNoNamesOrIDs() async throws {
        let library = try library()
        let run = await retire(["plan", "debug", "--library", library.path, "--anonymize"])
        #expect(run.status == 0, "\(run.all)")
        let names = ["casa", "Home", "conto-deposito", "Conto deposito", "conto-fineco", "Conto Fineco", "directa",
                     "Directa", "fondo-pensione", "Fondo pensione", "gold-coins", "Gold coins", "ledger-wallet",
                     "Ledger wallet", "mutuo-casa", "Mutuo casa", "old-bank", "Old bank", "btc", "Bitcoin", "vwce",
                     "Vanguard FTSE All-World UCITS ETF (Acc)", "Gold (coins and bars)", "IE00BK5BQT80",
                     "FinecoBank", "Directa SIM", "Banca Esempio", "base", "Base case", "part-time-from-50",
                     "State pension from previous country", "New car", "Inheritance", "Self-employed", "Alex Example",
                     "1988-04-12", "2026-09-30"]
        for name in names {
            #expect(!Self.containsWord(name, in: run.output), "\(name) in the output")
        }
        #expect(run.output.contains("# Calculations: Plan\n"))
        #expect(run.output.contains("| Accounts available later 1 | 67 |"))

        // Amounts are rounded, to 100 or to --round.
        let rounded = await retire(["plan", "debug", "--library", library.path, "--anonymize", "--round", "1000"])
        #expect(rounded.output.contains("| Work 1 | 2026 | 2028 | 40,000 | 1% |"))
        #expect(rounded.output.contains("| Pension 2 | 67 | 5,000 |"))
    }

    /// `--json` prints the deterministic run alone, unrounded, at the plan's
    /// age or at `--age`, without running the simulation.
    @Test func jsonIsTheDeterministicRun() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["plan", "debug", "--library", library.path, "--json"])
        #expect(run.status == 0, "\(run.all)")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(run.output.utf8)) as? [String: Any])
        #expect(json["plan"] as? String == "base")
        #expect(json["retirementAge"] as? Int == 55)
        #expect(json["startDate"] as? String == "2026-09-30")
        let groups = try #require(json["groups"] as? [[String: Any]])
        #expect(groups.map { $0["name"] as? String } == ["Money you can draw", "Fondo pensione"])
        #expect(groups[1]["availableFromAge"] as? Int == 67)
        let years = try #require(json["years"] as? [[String: Any]])
        #expect(years.first?["year"] as? Int == 2026)
        #expect(years.last?["year"] as? Int == 2083)
        #expect((years.first?["fraction"] as? Double).map { abs($0 - 92.0 / 365) < 1e-12 } == true)

        let early = await retire(["plan", "debug", "--library", library.path, "--json", "--age", "45"])
        let earlyJSON = try #require(try JSONSerialization.jsonObject(with: Data(early.output.utf8)) as? [String: Any])
        #expect(earlyJSON["retirementAge"] as? Int == 45)
        #expect((earlyJSON["failure"] as? [String: Any])?["reason"] as? String == "depleted")
    }

    @Test func badOptionsAreRefused() async throws {
        let library = try library()
        let round = await retire(["plan", "debug", "--library", library.path, "--round", "100"])
        #expect(round.status != 0)
        let zero = await retire(["plan", "debug", "--library", library.path, "--anonymize", "--round", "0"])
        #expect(zero.status != 0)
        let old = await retire(["plan", "debug", "--library", library.path, "--format", "json"])
        #expect(old.status == 64)
        let anonymized = await retire(["plan", "debug", "--library", library.path, "--json", "--anonymize"])
        #expect(anonymized.status != 0)
        let age = await retire(["plan", "debug", "--library", library.path, "--age", "50"])
        #expect(age.status != 0)
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
