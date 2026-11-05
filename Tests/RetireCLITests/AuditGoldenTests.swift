import Foundation
import Testing
import TestSupport

/// Every number `retire audit --json --plan base` gives for the example
/// library, against `Golden/example-library-audit.json`: a change in it is
/// a change in what the app shows. Review the diff, and when the change is
/// meant, write the file again:
///
///     UPDATE_GOLDEN=1 swift test --filter RetireCLITests.AuditGoldenTests
struct AuditGoldenTests {
    static let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Golden/example-library-audit.json")

    @Test func everyNumberOfTheExampleLibraryMatchesTheGoldenFile() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let arguments = ["audit", "--json", "--plan", "base", "--library", library.path]
        let run = await retire(arguments)
        #expect(run.status == 0, "\(run.all)")
        #expect(run.errors.isEmpty, "\(run.errors)")
        // The same twice: nothing depends on the clock or on what ran before.
        let again = await retire(arguments)
        #expect(again.output == run.output)

        if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(at: Self.golden.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(run.output.utf8).write(to: Self.golden)
            return
        }
        let expected = try String(contentsOf: Self.golden, encoding: .utf8)
        if run.output != expected {
            // Name the first line that differs, as the whole file is long.
            let lines = run.output.split(separator: "\n", omittingEmptySubsequences: false)
            let golden = expected.split(separator: "\n", omittingEmptySubsequences: false)
            let index = zip(lines, golden).enumerated().first { $0.element.0 != $0.element.1 }?.offset
                ?? min(lines.count, golden.count)
            let got = index < lines.count ? String(lines[index]) : "(end)"
            let wanted = index < golden.count ? String(golden[index]) : "(end)"
            Issue.record("""
                The audit differs from Golden/example-library-audit.json from line \(index + 1): \
                got \(got), expected \(wanted). If the change is meant, run \
                UPDATE_GOLDEN=1 swift test --filter RetireCLITests.AuditGoldenTests and review the diff.
                """)
        }
    }
}
