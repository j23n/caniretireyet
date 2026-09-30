import ArgumentParser
import Foundation
import Importer
import Model
import Storage

/// `retire import <file>`: previews or imports a spreadsheet, with a
/// proposed mapping or a saved profile, and undoes imports.
struct ImportCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import a spreadsheet (CSV or TSV) into the library.",
        discussion: """
            Without --profile, the importer detects the file's format and proposes a mapping; \
            the preview shows the detected settings, what each column becomes, the formats to \
            confirm, sample records and the cells that can't be read. Save the mapping with \
            --save-profile <id>, edit imports/<id>.json by hand or in the app if needed, and \
            import with --profile <id>.

            Nothing is written unless you pass --apply. Then the files that change are backed up \
            to backups/ first, and --undo puts them back, leaving edits made after the import \
            in place. New accounts and instruments, and \
            closing accounts whose values stop, happen only with --accept-new-accounts, \
            --accept-new-instruments and --accept-closings; otherwise those records are left \
            out. Records that differ from the library follow --on-conflict (default: the \
            profile's policy; undecided conflicts keep the library's values).
            """)

    enum Layout: String, ExpressibleByArgument, CaseIterable {
        case wide, long

        var value: ImportLayout { self == .wide ? .wide : .long }
    }

    enum Conflicts: String, ExpressibleByArgument, CaseIterable {
        case keep, overwrite, ask

        var policy: ConflictPolicy { ConflictPolicy(rawValue: rawValue) }
    }

    enum DebtSign: String, ExpressibleByArgument, CaseIterable {
        case auto
        case asWritten = "as-written"

        var value: LiabilitySign { self == .auto ? .auto : .asWritten }
    }

    @Argument(help: ArgumentHelp("The CSV or TSV file to import.", valueName: "file"))
    var file: String?

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("Read the file with a saved import profile, imports/<id>.json.", valueName: "id"))
    var profile: String?

    @Option(help: ArgumentHelp("Save the mapping as imports/<id>.json, to edit and reuse with --profile.",
                               valueName: "id"))
    var saveProfile: String?

    @Option(help: ArgumentHelp("The saved profile's name. Default: the file's name.", valueName: "name"))
    var profileName: String?

    @Option(help: ArgumentHelp("Text encoding: utf-8, utf-16, windows-1252 or iso-8859-1. Default: detected.",
                               valueName: "name"))
    var encoding: String?

    @Option(help: ArgumentHelp("Field delimiter: \",\", \";\", \"|\" or tab. Default: detected.", valueName: "char"))
    var delimiter: String?

    @Option(help: ArgumentHelp("The 1-based row with the column headers; 0 for none. Default: detected.",
                               valueName: "row"))
    var headerRow: Int?

    @Option(help: "Without a profile: wide (a row per date) or long (a row per record). Default: detected.")
    var layout: Layout?

    @Option(help: ArgumentHelp("The date pattern, e.g. dd/MM/yyyy, MM/dd/yyyy, MMM yyyy or excel-serial. "
                                   + "Default: detected.", valueName: "pattern"))
    var dateFormat: String?

    @Option(help: ArgumentHelp("The decimal separator: \".\" or \",\". Default: detected.", valueName: "char"))
    var decimal: String?

    @Option(help: ArgumentHelp("The thousands separator: \".\", \",\", \"'\", space or none. Default: detected.",
                               valueName: "char"))
    var thousands: String?

    @Option(help: ArgumentHelp("How debt balances are signed in the file: auto (a positive amount is a debt) or "
                                   + "as-written. Default: the profile's, else auto.", valueName: "sign"))
    var liabilitySign: DebtSign?

    @Flag(help: "Only preview; write nothing. This is the default.")
    var dryRun = false

    @Flag(help: "Import: back up the files that change, then write them.")
    var apply = false

    @Flag(help: "With --apply, create the new accounts the file needs.")
    var acceptNewAccounts = false

    @Flag(help: "With --apply, create the new instruments the file needs.")
    var acceptNewInstruments = false

    @Flag(help: "With --apply, close accounts whose values stop before the file's last date.")
    var acceptClosings = false

    @Option(help: ArgumentHelp("Records that differ from the library: keep, overwrite or ask (kept). "
                                   + "Default: the profile's.", valueName: "policy"))
    var onConflict: Conflicts?

    @Flag(help: "With --apply, import even if some formats are guesses (see “Formats to confirm”).")
    var acceptGuesses = false

    @Flag(help: ArgumentHelp("Undo the latest import that hasn't been undone, from its backup in backups/. Edits "
                                 + "made after the import stay."))
    var undo = false

    @Option(help: ArgumentHelp("How many records and conflicts the preview lists.", valueName: "count"))
    var rows = 10

    @Flag(help: "Print JSON.")
    var json = false

    /// The backup label of imports.
    static let backupLabel = "import"
    /// The backup label of the copy taken before an undo.
    static let undoLabel = "undo-import"

    func validate() throws {
        if apply, dryRun { throw ValidationError("Choose --dry-run or --apply, not both.") }
        if undo {
            if file != nil { throw ValidationError("--undo takes no file.") }
            if apply { throw ValidationError("--undo restores right away; it takes no --apply.") }
        } else if file == nil {
            throw ValidationError("Give the file to import, or --undo.")
        }
        if layout != nil, profile != nil {
            throw ValidationError("--layout proposes a new mapping; a profile has its own layout.")
        }
        if let saveProfile, !Slug.isValid(saveProfile) {
            throw ValidationError("--save-profile needs an ID such as my-sheet: lowercase letters, digits and hyphens.")
        }
        if let delimiter, delimiterCharacter(delimiter) == nil {
            throw ValidationError("--delimiter must be one character, or tab.")
        }
        if let decimal, decimal != ".", decimal != "," { throw ValidationError("--decimal must be \".\" or \",\".") }
        if let thousands, thousandsSeparator(thousands) == nil {
            throw ValidationError("--thousands must be \".\", \",\", \"'\", space or none.")
        }
        if let headerRow, headerRow < 0 { throw ValidationError("--header-row can't be negative.") }
        if rows < 0 { throw ValidationError("--rows can't be negative.") }
    }

    private func delimiterCharacter(_ text: String) -> String? {
        switch text.lowercased() {
        case "tab", "\\t", "\t": "\t"
        default: text.count == 1 ? text : nil
        }
    }

    private func thousandsSeparator(_ text: String) -> String? {
        switch text.lowercased() {
        case "none", "": ""
        case "space", " ": " "
        case "nbsp": "\u{A0}"
        case ".", ",", "'": text
        default: nil
        }
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        if undo {
            try runUndo(in: context)
            return
        }
        let loaded = try options.load(in: context)
        let fileURL = context.url(forPath: file!)
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CLIError("Can't read \(fileURL.path): \(error.localizedDescription)")
        }
        let session = try makeSession(data, library: loaded.library)
        var preview = session.preview(against: loaded.library)
        decide(&preview)

        var report = ImportReport(fileName: fileURL.lastPathComponent, profileID: profile, session: session,
                                  preview: preview, library: loaded.library, apply: apply, rows: rows,
                                  flags: .init(newAccounts: acceptNewAccounts, newInstruments: acceptNewInstruments,
                                               closings: acceptClosings, conflictsGiven: onConflict != nil))
        let blocked = apply && !preview.ambiguities.isEmpty && !acceptGuesses

        if apply, !blocked {
            let result = preview.apply(to: loaded.library)
            report.outcome = try write(result, session: session, loaded: loaded, context: context)
        } else if let saveProfile {
            try loaded.checkWritable()
            report.savedProfile = try save(session.makeProfile(id: ImportProfileID(saveProfile),
                                                               name: profileName(loaded.library),
                                                               library: loaded.library), in: loaded)
        }

        if json {
            context.console.print(try JSONOutput.string(report.json))
        } else {
            context.console.print(lines: report.lines())
        }
        if blocked {
            throw CLIError("Nothing was imported: some formats are guesses (see “Formats to confirm”). Settle them "
                + "with --date-format, --decimal or --delimiter, or pass --accept-guesses.")
        }
    }

    // MARK: - Session

    /// Reads the file with the saved profile, or proposes a mapping, and
    /// applies the options that override what was detected or saved.
    func makeSession(_ data: Data, library: Library) throws -> ImportSession {
        var session: ImportSession
        if let profile {
            guard var saved = library.importProfiles[ImportProfileID(profile)] else {
                let known = library.importProfiles.keys.sorted().map(\.rawValue)
                throw CLIError("There's no import profile \"\(profile)\" in imports/. "
                    + (known.isEmpty ? "The library has none yet: save one with --save-profile <id>."
                        : "Profiles: \(known.joined(separator: ", "))."))
            }
            overrideFileSettings(&saved.file)
            session = try ImportSession(data: data, profile: saved)
        } else {
            var settings = ImportFileSettings()
            overrideFileSettings(&settings)
            session = try ImportSession(data: data, settings: settings)
            if let layout { session.proposeMapping(layout: layout.value) }
        }
        if let dateFormat {
            var date = session.profile.defaults.date ?? ImportDateFormat()
            date.pattern = dateFormat
            session.profile.defaults.date = date
        }
        if decimal != nil || thousands != nil {
            var number = session.profile.defaults.number ?? ImportNumberFormat()
            if let decimal { number.decimal = decimal }
            if let thousands { number.thousands = thousandsSeparator(thousands) }
            session.profile.defaults.number = number
        }
        if let liabilitySign { session.profile.defaults.liabilitySign = liabilitySign.value }
        if let onConflict { session.profile.onConflict = onConflict.policy }
        return session
    }

    private func overrideFileSettings(_ settings: inout ImportFileSettings) {
        if let encoding { settings.encoding = TextEncodingName(encoding.lowercased()) }
        if let delimiter { settings.delimiter = delimiterCharacter(delimiter) }
        if let headerRow { settings.headerRow = headerRow }
    }

    /// Accepts or rejects the proposals by the flags, so a dry run shows
    /// exactly what the same command with --apply would do.
    func decide(_ preview: inout ImportPreview) {
        for index in preview.newAccounts.indices { preview.newAccounts[index].isAccepted = acceptNewAccounts }
        for index in preview.newInstruments.indices { preview.newInstruments[index].isAccepted = acceptNewInstruments }
        for index in preview.accountChanges.indices {
            if case .close = preview.accountChanges[index].change {
                preview.accountChanges[index].isAccepted = acceptClosings
            }
        }
    }

    private func profileName(_ library: Library) -> String {
        if let profileName { return profileName }
        if let saveProfile, let existing = library.importProfiles[ImportProfileID(saveProfile)] { return existing.name }
        return URL(fileURLWithPath: file ?? "Import").deletingPathExtension().lastPathComponent
    }

    // MARK: - Writing

    /// Saves a profile, refusing to replace one other than `--profile`'s.
    private func save(_ profile: ImportProfile, in loaded: LoadedLibrary) throws -> String {
        let path = LibraryFile.importProfile(profile.id).path
        if loaded.library.importProfiles[profile.id] != nil, profile.id.rawValue != self.profile {
            throw CLIError("\(path) already exists. Choose another ID, or update it with "
                + "--profile \(profile.id) --save-profile \(profile.id).")
        }
        try loaded.folder.save(profile)
        return path
    }

    /// Backs up the files the import changes, then writes them (and the
    /// profile, if asked), and records in the backup what was written, so
    /// `--undo` can leave later edits alone.
    private func write(_ result: ImportResult, session: ImportSession, loaded: LoadedLibrary,
                       context: CLIContext) throws -> ImportReport.Outcome {
        var outcome = ImportReport.Outcome(result: result)
        let newProfile = saveProfile.map {
            session.makeProfile(id: ImportProfileID($0), name: profileName(loaded.library), library: result.library)
        }
        guard result.hasChanges || newProfile != nil else { return outcome }
        try loaded.checkWritable()
        if let newProfile, loaded.library.importProfiles[newProfile.id] != nil, newProfile.id.rawValue != profile {
            throw CLIError("\(LibraryFile.importProfile(newProfile.id).path) already exists. Choose another ID, or "
                + "update it with --profile \(newProfile.id) --save-profile \(newProfile.id).")
        }
        var backup: Backup?
        if result.hasChanges {
            // Exactly the files the save writes, and the profile.
            var paths = result.library.files(changedFrom: loaded.library).map(\.path)
            if let newProfile { paths.append(LibraryFile.importProfile(newProfile.id).path) }
            backup = try loaded.folder.backup(paths: paths, label: Self.backupLabel, date: context.now())
            outcome.backup = backup?.path
            let saved = try loaded.folder.save(result.library, previous: loaded.library)
            outcome.written = saved.written
            outcome.deleted = saved.deleted
        }
        if let newProfile {
            outcome.savedProfile = try save(newProfile, in: loaded)
            if !outcome.written.contains(outcome.savedProfile!) { outcome.written.append(outcome.savedProfile!) }
        }
        if let backup { try loaded.folder.recordResult(of: backup) }
        return outcome
    }

    // MARK: - Undo

    /// The latest import backup not undone yet: imports and undos are
    /// paired in time order, like a stack.
    static func latestImport(in backups: [Backup]) -> Backup? {
        var stack: [Backup] = []
        for backup in backups {
            if backup.label == backupLabel {
                stack.append(backup)
            } else if backup.label == undoLabel, !stack.isEmpty {
                stack.removeLast()
            }
        }
        return stack.last
    }

    private func runUndo(in context: CLIContext) throws {
        let loaded = try options.load(in: context)
        let folder = loaded.folder
        guard let backup = Self.latestImport(in: try folder.backups()) else {
            throw CLIError("There's no import to undo: backups/ has no import backup that hasn't been undone.")
        }
        let console = context.console
        let created = backup.created.formatted(.iso8601)
        try loaded.checkWritable()
        if dryRun {
            let plan = try folder.undo(backup, dryRun: true)
            console.print("Would undo the import of \(created) from \(backup.path):")
            console.print(lines: plan.written.map { "  restore \($0)" } + plan.deleted.map { "  delete  \($0)" })
            console.print(lines: Self.undoNotes(plan, would: true))
            console.print("Dry run: nothing was written.")
            return
        }
        let safety = try folder.backup(paths: backup.paths, label: Self.undoLabel, date: context.now())
        let undone = try folder.undo(backup)
        console.print("Undid the import of \(created) from \(backup.path).")
        console.print(lines: undone.written.map { "  restored \($0)" } + undone.deleted.map { "  deleted  \($0)" })
        console.print(lines: Self.undoNotes(undone, would: false))
        console.print("The files as they were before undoing are in \(safety.path).")
    }

    /// What an undo left in place, or why it put the files back over later edits.
    static func undoNotes(_ report: UndoReport, would: Bool) -> [String] {
        if report.restoredWholesale {
            return ["This backup doesn't record what the import wrote, so its files \(would ? "would be" : "were") "
                + "put back as they were, over any later edits."]
        }
        guard !report.isComplete else { return [] }
        return ["Changed after the import, so \(would ? "it would be" : "it was") left in place:"]
            + report.keptChanges.map { "  \($0.summary)" }
    }
}
