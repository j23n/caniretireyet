import Foundation
import Model
import Observation
import Planner

/// What the plan debugger runs: the plan as shown on the Plan screen (its
/// unsaved edits too), the what-if in use, and the library as the plan's
/// runs read it, from the latest check-in. Taken when *Calculate* is
/// pressed, so the debugger always runs what's on screen.
struct PlanDebugSource: Sendable {
    var plan: PlanDocument
    var library: Library
    /// The date the plan starts from: the latest check-in.
    var asOf: CalendarDate
    /// `LibraryStore.revision`, to tell when the library changed.
    var revision: Int
    /// The what-if in use (empty when none).
    var whatIf = PlanWhatIf()
    /// The plan's own monthly saving, from its latest results: a what-if's
    /// saving is applied as a change from it.
    var baseMonthlySaving: Decimal?
    /// The age the Plan screen's charts are for, when one was chosen.
    var focusAge: Int?

    /// The plan on screen, from the Plan screen's session.
    @MainActor
    static func current(session: PlanSession, library: LibraryStore) -> PlanDebugSource? {
        guard let plan = session.plan else { return nil }
        return PlanDebugSource(
            plan: plan, library: library.library, asOf: library.asOfDate, revision: library.revision,
            whatIf: session.whatIf, baseMonthlySaving: session.baseResults?.details?.focus.monthlySaving,
            focusAge: session.shownFocusAge)
    }

    var hasWhatIf: Bool { !whatIf.isEmpty }

    /// Today's age, from the library's birth date.
    var ageToday: Int? {
        library.settings.person?.age(on: asOf)
    }

    /// The ages the details can be for: today's to the year before the plan ends.
    var ages: ClosedRange<Int>? {
        guard let today = ageToday else { return nil }
        return today...max(today, plan.effectiveEndAge - 1)
    }

    /// The plan to run and what to say about it: the what-if applied when
    /// it's in use and `includingWhatIf`.
    func plan(includingWhatIf: Bool) -> (plan: PlanDocument, notes: [String]) {
        guard hasWhatIf else { return (plan, []) }
        guard includingWhatIf else {
            return (plan, ["Calculated for the plan as it is, without your what-if."])
        }
        var notes: [String] = []
        var changes: [String] = []
        if let age = whatIf.retirementAge { changes.append("retiring at \(age)") }
        if whatIf.retiredSpending != nil { changes.append("its spending in retirement") }
        if whatIf.monthlySaving != nil {
            if baseMonthlySaving != nil {
                changes.append("its monthly saving")
            } else {
                notes.append("The what-if's saving isn't included: calculate the plan first, so its own saving "
                    + "is known.")
            }
        }
        if let equity = whatIf.equityReturn {
            changes.append("an equity return of \(PlanDebugText.number((equity.doubleValue * 1000).rounded() / 10))%")
        }
        if !changes.isEmpty {
            notes.insert("Calculated with your what-if, which isn't saved in the plan: "
                + PlanDebugText.list(changes) + ".", at: 0)
        }
        return (whatIf.applied(to: plan, baseMonthlySaving: baseMonthlySaving), notes)
    }

    /// What a report depends on besides the debugger's options: the plan
    /// run and the library's data.
    func fingerprint(includingWhatIf: Bool) -> String {
        "\(Planner.planHash(plan(includingWhatIf: includingWhatIf).plan))|\(revision)|\(asOf)"
    }
}

/// How the debugger runs a plan: `Planner.debugReport` with the app's tax
/// systems (`AppTaxRegistry.standard`), the same registry and inputs as
/// the Plan screen's runs (`PlannerPlanEngine`).
typealias PlanDebugRunner = @Sendable (PlanDocument, Library, PlanDebugOptions) async throws -> PlanDebugReport

/// The plan debugger's screen (UI.md, "Calculations (plan debugger)"):
/// its options, the run (only on *Calculate*, cancellable), the report
/// laid out (``content``), which sections are open, the traced run and
/// year chosen, and the export.
@Observable @MainActor
final class PlanDebugModel {
    /// The options of the controls.
    var choices = PlanDebugChoices()
    /// The export's options.
    var export = PlanDebugExportSettings()
    /// The sections opened.
    var expanded: Set<PlanDebugSection> = []
    /// The traced run shown (an index into ``PlanDebugContent/paths``).
    var selectedPath = 0 {
        didSet { if selectedPath != oldValue { selectedPathYear = content?.paths.first { $0.id == selectedPath }?.defaultYear } }
    }
    /// The traced run's year shown in detail.
    var selectedPathYear: Int?
    /// Which of the traced run's tables shows.
    var pathTable = PlanDebugPathTable.flows
    /// The schedule's year shown in detail.
    var selectedScheduleYear: Int?

    /// The report, and when it was made from.
    private(set) var report: PlanDebugReport?
    /// The report laid out for the screen.
    private(set) var content: PlanDebugContent?
    /// The options and inputs the report was calculated with.
    private(set) var calculated: (choices: PlanDebugChoices, fingerprint: String)?
    private(set) var isRunning = false
    /// Why the last run failed.
    private(set) var error: String?

    /// The file written for the export's options, ready to share.
    private(set) var exportFile: PlanDebugExportFile?
    private(set) var isPreparingExport = false
    private(set) var exportError: String?

    @ObservationIgnored private let source: @MainActor () -> PlanDebugSource?
    @ObservationIgnored private let runner: PlanDebugRunner
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Counts reports, so an export of an older one is dropped.
    @ObservationIgnored private var generation = 0
    /// Counts exports, so only the latest one's file is kept.
    @ObservationIgnored private var exportRequests = 0

    /// `source` gives the plan on screen when asked; `runner` runs it (the
    /// Planner with the app's tax systems by default).
    init(source: @escaping @MainActor () -> PlanDebugSource?, runner: @escaping PlanDebugRunner = PlanDebugModel.planner) {
        self.source = source
        self.runner = runner
        if let current = source() {
            let ages = current.ages
            let preferred: Int? = if case .age(let age) = current.plan.retirement.age { age } else { current.focusAge }
            if let ages {
                choices.customAge = min(max(preferred ?? ages.lowerBound + 10, ages.lowerBound), ages.upperBound)
            }
        }
    }

    /// The Planner with the app's tax systems.
    static let planner: PlanDebugRunner = { plan, library, options in
        do {
            return try await Planner.debugReport(for: plan, library: library, registry: AppTaxRegistry.standard,
                                                 options: options)
        } catch let error as PlannerError {
            throw PlanEngineError.invalidPlan(PlannerPlanEngine.message(for: error))
        }
    }

    // MARK: The plan on screen

    /// The plan on screen now.
    var currentSource: PlanDebugSource? { source() }

    /// Whether a what-if is in use on the Plan screen.
    var hasWhatIf: Bool { currentSource?.hasWhatIf ?? false }

    /// The ages the stepper offers.
    var ages: ClosedRange<Int> {
        currentSource?.ages ?? 18...94
    }

    // MARK: Running

    /// Calculate: runs the plan on screen with the chosen options, off the
    /// main actor. The report shown stays until the new one is ready.
    func calculate() {
        guard let source = source() else {
            error = "There's no plan to calculate."
            return
        }
        task?.cancel()
        let choices = choices
        let (plan, notes) = source.plan(includingWhatIf: choices.includesWhatIf)
        let fingerprint = source.fingerprint(includingWhatIf: choices.includesWhatIf)
        let options = choices.options(asOf: source.asOf, runDate: .today())
        let library = source.library
        let runner = runner
        isRunning = true
        error = nil
        task = Task { [weak self] in
            do {
                let report = try await runner(plan, library, options)
                try Task.checkCancellation()
                self?.show(report, notes: notes, choices: choices, fingerprint: fingerprint)
            } catch {
                guard let self, !Task.isCancelled, !(error is CancellationError) else { return }
                self.isRunning = false
                self.error = Self.describe(error)
            }
        }
    }

    /// Cancel: stops the run; the report shown stays.
    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func show(_ report: PlanDebugReport, notes: [String], choices: PlanDebugChoices, fingerprint: String) {
        let content = PlanDebugContent(report: report, notes: notes)
        generation += 1
        self.report = report
        self.content = content
        calculated = (choices, fingerprint)
        isRunning = false
        task = nil
        exportFile = nil
        exportError = nil
        let path = content.paths.first { $0.label == "The median outcome" } ?? content.paths.first
        selectedPath = path?.id ?? 0
        selectedPathYear = path?.defaultYear
        selectedScheduleYear = nil
    }

    /// Why the report shown no longer fits, if it doesn't: the options or
    /// the plan and data changed since.
    var staleReason: String? {
        guard let calculated, !isRunning else { return nil }
        if calculated.choices != choices { return "The options changed since this was calculated." }
        if let source = source(), source.fingerprint(includingWhatIf: choices.includesWhatIf) != calculated.fingerprint {
            return "The plan or your data changed since this was calculated."
        }
        return nil
    }

    /// The words for an error.
    static func describe(_ error: any Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription { return description }
        return "The calculation failed: \(error.localizedDescription)"
    }

    // MARK: Sections

    func isExpanded(_ section: PlanDebugSection) -> Bool {
        expanded.contains(section)
    }

    func setExpanded(_ section: PlanDebugSection, _ isExpanded: Bool) {
        if isExpanded { expanded.insert(section) } else { expanded.remove(section) }
    }

    /// The traced run shown.
    var path: PlanDebugPath? {
        content?.paths.first { $0.id == selectedPath }
    }

    // MARK: Export

    /// Writes the report to a file for the export's options, to share or
    /// save, off the main actor; a newer call wins.
    func prepareExport() async {
        guard let report else { return }
        let settings = export
        let generation = generation
        exportRequests += 1
        let request = exportRequests
        isPreparingExport = true
        exportError = nil
        defer {
            if request == exportRequests { isPreparingExport = false }
        }
        do {
            let file = try await Task.detached(priority: .userInitiated) {
                try PlanDebugExport.write(report, settings)
            }.value
            guard request == exportRequests, settings == export, generation == self.generation else { return }
            exportFile = file
        } catch {
            guard request == exportRequests, settings == export, generation == self.generation else { return }
            exportError = "The file couldn't be written: \(error.localizedDescription)"
        }
    }

    /// The file for the export's options, once it's written.
    var readyExportFile: PlanDebugExportFile? {
        guard let exportFile, exportFile.settings == export else { return nil }
        return exportFile
    }

    /// The report as Markdown, anonymized as the export says: *Copy as Markdown*.
    func markdown() async -> String? {
        guard let report else { return nil }
        var settings = export
        settings.format = .markdown
        return try? await Task.detached(priority: .userInitiated) {
            try PlanDebugExport.text(report, settings)
        }.value
    }
}

/// The export's format.
enum PlanDebugExportFormat: String, CaseIterable, Hashable, Identifiable, Sendable {
    /// Readable, with every section explained; long tables skip some years.
    case markdown
    /// Every year and every detail.
    case json

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: "Markdown"
        case .json: "JSON"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .json: "json"
        }
    }

    var explanation: String {
        switch self {
        case .markdown: "Readable, each section explained; long tables skip some years."
        case .json: "Every year and every detail, for a program or a closer look."
        }
    }
}

/// How the report is exported: anonymized (by default) and rounded, as
/// Markdown or JSON.
struct PlanDebugExportSettings: Hashable, Sendable {
    var anonymizes = true
    var rounding = PlanDebugAnonymization.Rounding.significantFigures
    var format = PlanDebugExportFormat.markdown

    /// The roundings offered, the default first.
    static let roundings: [PlanDebugAnonymization.Rounding] = [.significantFigures, .hundreds, .none]
}

/// A report written to a file, and how.
struct PlanDebugExportFile: Hashable, Sendable {
    var url: URL
    var settings: PlanDebugExportSettings

    var name: String { url.lastPathComponent }
}

/// Writing the report for sharing.
enum PlanDebugExport {
    /// The report as `settings` says: anonymized with its rounding, as
    /// Markdown or JSON.
    static func text(_ report: PlanDebugReport, _ settings: PlanDebugExportSettings) throws -> String {
        let shared = settings.anonymizes ? report.anonymized(PlanDebugAnonymization(rounding: settings.rounding)) : report
        switch settings.format {
        case .markdown: return shared.markdown()
        case .json: return try shared.json() + "\n"
        }
    }

    /// "plan-calculations-2026-10-04.md": the day the report was made.
    static func fileName(_ report: PlanDebugReport, format: PlanDebugExportFormat) -> String {
        "plan-calculations-\(report.header.runDate).\(format.fileExtension)"
    }

    /// The folder exports are written to, in the temporary directory.
    static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Plan calculations", isDirectory: true)
    }

    /// Writes the report as `settings` says to a file of its own (a new
    /// folder each time, so two exports never write the same file), and
    /// removes earlier ones.
    static func write(_ report: PlanDebugReport, _ settings: PlanDebugExportSettings, in folder: URL = folder) throws
        -> PlanDebugExportFile {
        let text = try text(report, settings)
        let manager = FileManager.default
        if let old = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for item in old { try? manager.removeItem(at: item) }
        }
        let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName(report, format: settings.format))
        try Data(text.utf8).write(to: url, options: .atomic)
        return PlanDebugExportFile(url: url, settings: settings)
    }
}
