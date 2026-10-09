import ArgumentParser
import Foundation
import Model
import Storage

/// `retire validate`: loads every file and reports what's wrong, per file.
struct ValidateCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Check every file in a library folder.",
        discussion: """
            Loads the library and prints each file's errors (a file or records that couldn't be \
            read) and warnings (everything loaded, but something should be fixed), the format \
            version and whether the library is read-only. It also checks references between \
            files: records of unknown accounts, valuations outside an account's dates, debts \
            with positive balances, missing prices, and plans or import profiles naming what \
            doesn't exist. Exits with status 1 when there are errors (with --strict, warnings too).
            """)

    @OptionGroup var options: LibraryOptions

    @Flag(help: "Exit with status 1 on warnings too.")
    var strict = false

    @Flag(help: "Print the report as JSON.")
    var json = false

    func run(in context: CLIContext) async throws {
        let folder = try options.folder(in: context)
        guard folder.files.fileExists(at: folder.root) else {
            throw CLIError("The library folder \(folder.root.path) doesn't exist.")
        }
        let loaded = try folder.load()
        var issues = loaded.report.issues
        if folder.containsLibrary {
            issues += LibraryChecks(library: loaded.library).issues()
        }
        // By path, then errors before warnings, keeping the order found (the sort is stable).
        issues.sort { ($0.path, $0.severity == .error ? 0 : 1) < ($1.path, $1.severity == .error ? 0 : 1) }
        let report = Report(folder: folder, library: loaded.library, load: loaded.report, issues: issues)

        try context.console.print(report, json: json)
        if report.errors > 0 || (strict && report.warnings > 0) { throw ExitCode.failure }
    }

    /// What `validate` found.
    struct Report: CommandReport {
        var folder: LibraryFolder
        var library: Library
        var load: LoadReport
        var issues: [LoadIssue]

        var errors: Int { issues.filter { $0.severity == .error }.count }
        var warnings: Int { issues.filter { $0.severity == .warning }.count }

        /// The format version and what it means for this app version.
        var versionText: String {
            let current = LibrarySettings.currentSchemaVersion
            guard let version = load.schemaVersion else { return "unknown (library.json can't be read)" }
            if load.isNewerSchema { return "\(version), newer than this version understands (\(current))" }
            if load.needsMigration { return "\(version), older than this version's \(current): upgrade before saving" }
            return "\(version) (current)"
        }

        /// Whether the library is read-only, and what to do about it.
        var readOnlyText: String {
            if load.isNewerSchema { return "yes: update the app to make changes" }
            if load.settingsUnreadable { return "yes: library.json can't be read; fix it or restore it from backups/" }
            return "no"
        }

        var contentsText: String {
            let closed = library.accounts.values.filter(\.isClosed).count
            var parts = [Wording.count(library.accounts.count, "account") + (closed > 0 ? " (\(closed) closed)" : ""),
                         Wording.count(library.instruments.count, "instrument")]
            let months = library.months.filter { !$0.value.isEmpty }.keys.sorted()
            if let first = months.first, let last = months.last {
                parts.append(Wording.count(months.count, "month") + " of history (\(first) to \(last))")
            } else {
                parts.append("no history")
            }
            parts.append(Wording.count(library.plans.count, "plan"))
            parts.append(Wording.count(library.importProfiles.count, "import profile"))
            return parts.joined(separator: ", ")
        }

        func lines() -> [String] {
            var lines = ["Library \(folder.root.path)"]
            var table = TextTable([.left(""), .left("")], showsHeader: false)
            table.add(["Format version", versionText])
            table.add(["Read-only", readOnlyText])
            table.add(["Files read", "\(load.filesRead)"])
            table.add(["Contents", contentsText])
            lines += table.lines()
            lines.append("")
            if issues.isEmpty {
                lines.append("No problems found.")
                return lines
            }
            var path: String?
            for issue in issues {
                if issue.path != path {
                    if path != nil { lines.append("") }
                    lines.append(issue.path)
                    path = issue.path
                }
                lines.append("  \(issue.severity == .error ? "error  " : "warning") \(issue.message)")
            }
            lines.append("")
            lines.append("\(Wording.count(errors, "error")), \(Wording.count(warnings, "warning")).")
            return lines
        }

        var json: JSON {
            JSON(library: folder.root.path, schemaVersion: load.schemaVersion,
                 currentSchemaVersion: LibrarySettings.currentSchemaVersion, readOnly: load.isReadOnly,
                 needsMigration: load.needsMigration, filesRead: load.filesRead, errors: errors, warnings: warnings,
                 issues: issues.map { JSON.Issue(path: $0.path, severity: $0.severity.rawValue, message: $0.message) })
        }

        struct JSON: Encodable {
            struct Issue: Encodable {
                var path: String
                var severity: String
                var message: String
            }

            var library: String
            var schemaVersion: Int?
            var currentSchemaVersion: Int
            var readOnly: Bool
            var needsMigration: Bool
            var filesRead: Int
            var errors: Int
            var warnings: Int
            var issues: [Issue]
        }
    }
}
