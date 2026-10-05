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

    @Test func markdownHasEverySection() async throws {
        let library = try library()
        let run = await retire(["plan", "debug", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        for heading in ["# Calculations: Base case", "## The answer", "## The plan as read", "## The starting portfolio",
                        "## Chance of success by retirement age", "## When runs fail"] {
            #expect(run.output.contains(heading + "\n"), "\(heading)")
        }
        #expect(run.output.contains("the day after 2026-09-30"))
        // Names as they are.
        #expect(run.output.contains("| Fondo pensione | 67 |"))
        #expect(run.output.contains("| Employee | 2026-01-01 | 2028-12-31 | 40,000 | 1% |"))
    }

    @Test func theReportCanGoToAFile() async throws {
        let library = try library()
        let run = await retire(["plan", "debug", "--library", library.path, "--output", "reports/base.md"],
                               currentDirectory: library.url)
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output == "Wrote the report on base to reports/base.md.\n")
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

    @Test func badOptionsAreRefused() async throws {
        let library = try library()
        let round = await retire(["plan", "debug", "--library", library.path, "--round", "100"])
        #expect(round.status != 0)
        #expect(round.errors.contains("--round goes with --anonymize"))
        let zero = await retire(["plan", "debug", "--library", library.path, "--anonymize", "--round", "0"])
        #expect(zero.errors.contains("--round takes an amount above 0"))
        let old = await retire(["plan", "debug", "--library", library.path, "--format", "json"])
        #expect(old.status == 64)
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
