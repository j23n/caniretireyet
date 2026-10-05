import Foundation
import Model
import Observation
import Planner

/// *Export Calculations…* (UI.md, "Export calculations"): every input and
/// calculation behind a plan's answer as a Markdown file
/// (`Planner.calculations`, PLANNER.md, "Calculations"), to check it or give
/// it to someone else, anonymized by default. Taken from the plan as the
/// Plan screen shows it: its unsaved edits and the what-if in use.
@MainActor
@Observable
final class PlanCalculationsExport: Identifiable {
    /// What the report runs: the plan, the library and the start date.
    struct Source: Sendable {
        var plan: PlanDocument
        var library: Library
        /// The date the plan starts from when it has no check-in.
        var asOf: CalendarDate
    }

    /// The file, once written.
    struct File: Hashable, Sendable {
        var url: URL
        var name: String { url.lastPathComponent }
    }

    /// What anonymized amounts can be rounded to.
    static let roundings: [Double] = [1, 100, 1_000, 10_000]

    /// Under the anonymize switch.
    static let anonymizeNote = "Leaves out names, account and plan names and exact dates, and rounds amounts, so the "
        + "file can be given to someone else. Your ages and the shape of the plan stay."

    /// Under the switch, when it's off.
    static let exactNote = "Keeps every name and date, with exact amounts: for yourself."

    let source: Source
    var anonymizes = true
    var rounding: Double = 100
    private(set) var file: File?
    private(set) var error: String?
    private var requests = 0

    init(source: Source) {
        self.source = source
    }

    /// The plan on screen, with the what-if in use applied.
    static func source(session: PlanSession, library: LibraryStore) -> Source? {
        guard let plan = session.plan else { return nil }
        let saving = session.baseResults?.details?.focus.monthlySaving
        let shown = session.whatIf.isEmpty ? plan : session.whatIf.applied(to: plan, baseMonthlySaving: saving)
        return Source(plan: shown, library: library.library, asOf: library.asOfDate)
    }

    /// The options in effect, which the file follows.
    var options: CalculationsOptions {
        CalculationsOptions(anonymize: anonymizes, rounding: rounding, today: source.asOf)
    }

    /// Writes the report with the current options to a file of its own. A
    /// newer request wins over one still running.
    func prepare() async {
        requests += 1
        let request = requests
        file = nil
        error = nil
        let source = source
        let options = options
        do {
            let url = try await Task.detached(priority: .userInitiated) {
                let text = try await Planner.calculations(plan: source.plan, library: source.library, options: options)
                return try Self.write(text, name: Self.fileName(plan: source.plan, anonymized: options.anonymize))
            }.value
            guard request == requests else { return }
            file = File(url: url)
        } catch {
            guard request == requests else { return }
            self.error = (error as? PlannerError).map(PlannerPlanEngine.message(for:))
                ?? "The calculations couldn't be written: \(error.localizedDescription)"
        }
    }

    /// "Base case calculations.md", or "Plan calculations.md" anonymized.
    nonisolated static func fileName(plan: PlanDocument, anonymized: Bool) -> String {
        let name = anonymized ? "Plan" : plan.name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(name) calculations.md"
    }

    /// Where the files go: a folder of their own in the temporary directory.
    nonisolated static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Plan calculations", isDirectory: true)
    }

    /// Writes `text` as `name` in a new folder (so two exports never write
    /// the same file), removing earlier ones.
    nonisolated static func write(_ text: String, name: String, in folder: URL = folder) throws -> URL {
        let manager = FileManager.default
        if let old = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for item in old { try? manager.removeItem(at: item) }
        }
        let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }
}
