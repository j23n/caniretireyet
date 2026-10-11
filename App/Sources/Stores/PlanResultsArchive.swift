import Foundation
import Model
#if canImport(os)
import os
#endif

/// Each plan's latest results, kept on this device between launches (UI.md,
/// "Calculating"), so reopening the app shows them without calculating
/// again.
///
/// They're kept outside the library, in the app's caches: results are
/// worked out from the library, never part of it, so they don't sync and
/// each device keeps its own. Each library has a folder of its own, so a
/// plan of the same ID in another library never shows them.
///
/// A file holds a plan's own results (not a what-if's or another age's)
/// and what they were calculated from: the plan, a fingerprint of the
/// library data the run read (``PlanRunInputs/fingerprint``), the start
/// date, the mode and the engine. `PlanStore` writes one after every run of
/// a plan, and reads them when a library opens: files of another format or
/// engine, and of plans the library no longer has, are deleted then.
actor PlanResultsArchive {
    /// A plan's results and what they were calculated from. The results
    /// say the engine that calculated them (`PlanEngine.version`; results
    /// of another engine are dropped) and the mode.
    struct Entry: Codable, Sendable {
        /// The format this version writes; files of another are dropped.
        /// 2: full results include the pace age (`agesWithout.pace`).
        static let currentFormat = 2

        var format: Int
        /// The plan as it was calculated.
        var plan: PlanDocument
        /// The library data the run read, as ``PlanRunInputs/fingerprint``.
        var inputs: String
        /// The date the plan started from.
        var asOf: CalendarDate
        var results: PlanResults
    }

    /// Results found when a library opens, and whether the library data the
    /// run read is still the same.
    struct Restored: Sendable {
        var entry: Entry
        var inputsMatch: Bool
    }

    /// Where the libraries' folders are.
    let root: URL

    init(root: URL) {
        self.root = root
    }

    /// The app's: `Caches/<bundle id>/PlanResults`. The system may clear
    /// it when space runs low; the plans are then calculated again on request.
    static func standard() -> PlanResultsArchive? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return PlanResultsArchive(root: caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "CanIRetireYet", isDirectory: true)
            .appendingPathComponent("PlanResults", isDirectory: true))
    }

    /// The folder for the library at `library`: named by a hash of its path
    /// (``libraryKey(_:home:)``).
    nonisolated func folder(forLibraryAt library: URL) -> URL {
        root.appendingPathComponent(FNV1a.hexHash(Data(Self.libraryKey(library).utf8)), isDirectory: true)
    }

    /// What names the library at `library` from one launch to the next: its
    /// path in the app's home (`~/Library/Application Support/…`) when it's
    /// there, else its full path (iCloud Drive's). A library on this device
    /// is in the app's container, whose full path changes when the app is
    /// installed again (each run from Xcode) or updated, so it can't name it.
    static func libraryKey(_ library: URL, home: String = NSHomeDirectory()) -> String {
        let path = library.standardizedFileURL.resolvingSymlinksInPath().path
        let home = URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
        guard !home.isEmpty, home != "/", path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// Keeps `results`, calculated from `basis`, as their plan's in the
    /// library at `library`, replacing what was kept. Nothing is kept for a
    /// basis without its inputs (results restored from a changed library).
    func save(_ results: PlanResults, basis: PlanRunBasis, library: URL) throws {
        guard let inputs = basis.inputs else { return }
        let entry = Entry(format: Entry.currentFormat, plan: basis.plan, inputs: inputs.fingerprint,
                          asOf: basis.asOf, results: results)
        let folder = folder(forLibraryAt: library)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try Self.encoder().encode(entry)
        try data.write(to: file(for: results.plan, in: folder), options: .atomic)
        PlanResultsLog.notice("Kept \(results.plan)'s results (\(data.count / 1_024) KB) for the library at "
                              + "\(Self.libraryKey(library)).")
    }

    /// The results kept for the plans of `library`, found at `url`, each
    /// with whether the library data its run read is the same now. Files of
    /// another format or engine, that can't be read, or of a plan the
    /// library doesn't have are deleted.
    func restore(forLibraryAt url: URL, library: Library, engine: String) -> [Restored] {
        let folder = folder(forLibraryAt: url)
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else {
            PlanResultsLog.notice("No results kept for the library at \(Self.libraryKey(url)).")
            return []
        }
        let decoder = Self.decoder()
        var entries: [Entry] = []
        for file in files where file.pathExtension == "json" {
            let entry: Entry
            do {
                entry = try decoder.decode(Entry.self, from: Data(contentsOf: file))
            } catch {
                drop(file, because: "it can't be read: \(error)")
                continue
            }
            if entry.format != Entry.currentFormat {
                drop(file, because: "it's in format \(entry.format), not \(Entry.currentFormat)")
            } else if entry.results.engine != engine {
                drop(file, because: "engine \(entry.results.engine) calculated it, not \(engine)")
            } else if library.plans[entry.results.plan] == nil {
                drop(file, because: "the library has no plan \(entry.results.plan)")
            } else if file.lastPathComponent != self.file(for: entry.results.plan, in: folder).lastPathComponent {
                drop(file, because: "it holds the results of \(entry.results.plan)")
            } else {
                entries.append(entry)
            }
        }
        guard !entries.isEmpty else { return [] }
        let current = PlanRunInputs(library).fingerprint
        return entries.sorted { $0.results.plan < $1.results.plan }
            .map { Restored(entry: $0, inputsMatch: $0.inputs == current) }
    }

    /// Deletes a kept file that can't be shown, saying why.
    private func drop(_ file: URL, because reason: String) {
        PlanResultsLog.notice("Dropped the kept results \(file.lastPathComponent): \(reason).")
        try? FileManager.default.removeItem(at: file)
    }

    private func file(for plan: PlanID, in folder: URL) -> URL {
        folder.appendingPathComponent("\(plan.rawValue).json")
    }

    // MARK: JSON

    /// Doubles that aren't numbers (a NaN from the planner) are written as strings.
    private static let nonConforming = (positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: nonConforming.positiveInfinity, negativeInfinity: nonConforming.negativeInfinity,
            nan: nonConforming.nan)
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: nonConforming.positiveInfinity, negativeInfinity: nonConforming.negativeInfinity,
            nan: nonConforming.nan)
        return decoder
    }
}

extension PlanRunInputs {
    /// A fingerprint of the library data a run reads, the same on every
    /// launch for the same data: FNV-1a (64-bit) of its JSON with sorted
    /// keys (decimals in their exact file form), as the Planner's plan hash
    /// is, with accounts, instruments and months in order. Data that can't
    /// be encoded gets a fingerprint nothing else has.
    var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(Fingerprinted(self)) else { return UUID().uuidString }
        return FNV1a.hexHash(data)
    }

    /// The inputs with their dictionaries as lists in a fixed order.
    private struct Fingerprinted: Encodable {
        var settings: LibrarySettings
        var accounts: [Account]
        var instruments: [Instrument]
        var months: [MonthFile]

        init(_ inputs: PlanRunInputs) {
            settings = inputs.settings
            accounts = inputs.accounts.values.sorted { $0.id < $1.id }
            instruments = inputs.instruments.values.sorted { $0.id < $1.id }
            months = inputs.months.values.sorted { $0.month < $1.month }
        }
    }
}

/// What happens to the results kept on the device, in the app's log
/// (category `plans`; Xcode's console shows it): kept, restored and
/// whether they're up to date, or dropped and why.
enum PlanResultsLog {
    #if canImport(os)
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CanIRetireYet", category: "plans")
    #endif

    static func notice(_ message: @autoclosure () -> String) {
        #if canImport(os)
        let text = message()
        logger.notice("\(text, privacy: .public)")
        #endif
    }
}
