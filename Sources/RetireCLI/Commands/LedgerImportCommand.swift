import ArgumentParser
import Foundation
import Importer
import Model
import Storage

/// `retire import`: a spreadsheet (the default, `retire import csv`) or
/// ledger journals (`retire import ledger`).
struct ImportGroupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import a spreadsheet (CSV or TSV) or ledger-cli / hledger journals into the library.",
        discussion: """
            retire import <file>             a CSV or TSV file (`retire import csv`)
            retire import ledger <files…>    ledger-cli or hledger journals
            retire import --undo             undo the latest import

            Common options: --library <path>, --profile <id>, --save-profile <id>, --apply, \
            --accept-new-accounts, --accept-new-instruments, --accept-closings, and --on-conflict \
            keep|overwrite|ask. `retire help import csv` and `retire help import ledger` list them all.
            """,
        subcommands: [ImportCommand.self, LedgerImportCommand.self],
        defaultSubcommand: ImportCommand.self)
}

/// `retire import ledger <files…>`: previews or imports ledger-cli and
/// hledger journals (IMPORT.md, "Ledger journals"), with a proposed mapping
/// or a saved ledger profile, and undoes imports.
struct LedgerImportCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "ledger",
        abstract: "Import ledger-cli or hledger journals into the library.",
        discussion: """
            Give one journal or several (e.g. one per year); the files they include are read too. \
            Assets and liabilities become valuations at month ends (or --frequency quarter or \
            activity), with flows (money added or taken out) and purchase costs; P directives and \
            @ prices become prices and exchange rates. A library account that records trades gets \
            the journal's trades instead: buys and sells at their @ or {} prices with their fees, \
            dividends, interest, fees, taxes, deposits and withdrawals, and no valuations (its cash \
            comes from its trades), unless you pass --cash-checks.

            Without --profile, the importer matches ledger accounts and commodities to the library \
            by name and proposes new ones; the preview shows where each goes. Save the mapping with \
            --save-profile <id>, edit imports/<id>.json if needed (matches, ledger.ignore, \
            ledger.returns), and import with --profile <id>.

            Nothing is written unless you pass --apply. Then the files that change are backed up \
            first, and `retire import --undo` puts them back. New accounts and instruments, and \
            closings, need --accept-new-accounts, --accept-new-instruments and --accept-closings.
            """)

    enum Frequency: String, ExpressibleByArgument, CaseIterable {
        case month, quarter, activity

        var value: LedgerSnapshotFrequency { LedgerSnapshotFrequency(rawValue: rawValue) }
    }

    @Argument(help: ArgumentHelp("The journal files.", valueName: "files"))
    var files: [String] = []

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("Read the journal with a saved ledger profile, imports/<id>.json.", valueName: "id"))
    var profile: String?

    @Option(help: ArgumentHelp("Save the mapping as imports/<id>.json, to reuse with --profile.", valueName: "id"))
    var saveProfile: String?

    @Option(help: ArgumentHelp("The saved profile's name. Default: the first file's name.", valueName: "name"))
    var profileName: String?

    @Option(help: ArgumentHelp("When valuations are written: month (ends), quarter (ends) or activity (every date with a "
        + "posting). Default: the profile's, else month."))
    var frequency: Frequency?

    @Option(help: ArgumentHelp("Leave out records dated after this day. Default: today.", valueName: "YYYY-MM-DD"))
    var until: String?

    @Flag(inversion: .prefixedNo, help: "Whether @ prices on transactions become price records too. Default: yes.")
    var transactionPrices: Bool?

    @Flag(inversion: .prefixedNo,
          help: ArgumentHelp("Whether accounts that record trades also get valuations with the journal's cash, as "
                                 + "checks. Default: the profile's, else no."))
    var cashChecks: Bool?

    @Flag(help: "Only preview; write nothing. This is the default.")
    var dryRun = false

    @Flag(help: "Import: back up the files that change, then write them.")
    var apply = false

    @Flag(help: "With --apply, create the new accounts the journal needs.")
    var acceptNewAccounts = false

    @Flag(help: "With --apply, create the new instruments the journal needs.")
    var acceptNewInstruments = false

    @Flag(help: "With --apply, close accounts whose balance goes to zero and stays there.")
    var acceptClosings = false

    @Option(name: [.customLong("on-conflict"), .customLong("policy")],
            help: ArgumentHelp("Records that differ from the library: keep, overwrite or ask (kept). "
                + "Default: the profile's.", valueName: "policy"))
    var onConflict: ImportCommand.Conflicts?

    @Flag(help: "Undo the latest import that hasn't been undone (the same as `retire import --undo`).")
    var undo = false

    @Option(help: ArgumentHelp("How many records and conflicts the preview lists.", valueName: "count"))
    var rows = 10

    func validate() throws {
        if apply, dryRun { throw ValidationError("Choose --dry-run or --apply, not both.") }
        if undo {
            if !files.isEmpty { throw ValidationError("--undo takes no files.") }
            if apply { throw ValidationError("--undo restores right away; it takes no --apply.") }
        } else if files.isEmpty {
            throw ValidationError("Give the journal files to import, or --undo.")
        }
        if let saveProfile, !Slug.isValid(saveProfile) {
            throw ValidationError("--save-profile needs an ID such as my-journal: lowercase letters, digits and "
                + "hyphens.")
        }
        _ = try parseDate(until, option: "--until")
        if rows < 0 { throw ValidationError("--rows can't be negative.") }
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        if undo {
            try ImportCommand.runUndo(options: options, dryRun: dryRun, in: context)
            return
        }
        let loaded = try options.load(in: context)
        let urls = files.map(context.url(forPath:))
        let journal = LedgerReader.read(urls, files: LocalLedgerFiles())
        guard !journal.files.isEmpty else {
            throw CLIError(journal.diagnostics.map(\.description).joined(separator: "\n"))
        }
        let session = try makeSession(journal, library: loaded.library)
        let ledgerPreview = session.preview(against: loaded.library,
                                            until: try parseDate(until, option: "--until") ?? context.today)
        var preview = ledgerPreview.preview
        decide(&preview)

        var report = LedgerImportReport(
            session: session, ledger: ledgerPreview, preview: preview, library: loaded.library, profileID: profile,
            apply: apply, rows: rows,
            flags: .init(newAccounts: acceptNewAccounts, newInstruments: acceptNewInstruments,
                         closings: acceptClosings, conflictsGiven: onConflict != nil, tradesMode: false))
        if apply {
            let result = preview.applyFollowingFlows(to: loaded.library)
            report.outcome = try write(result, session: session, ledgerPreview: ledgerPreview, loaded: loaded,
                                       context: context)
        } else if let saveProfile {
            try loaded.checkWritable()
            report.savedProfile = try save(session.makeProfile(id: ImportProfileID(saveProfile),
                                                               name: profileName(loaded.library), from: ledgerPreview,
                                                               library: loaded.library), in: loaded)
        }
        context.console.print(lines: report.lines())
    }

    /// The session, with the saved profile and the options that override it.
    func makeSession(_ journal: LedgerJournal, library: Library) throws -> LedgerImportSession {
        var saved: ImportProfile?
        if let profile {
            guard let found = library.importProfiles[ImportProfileID(profile)] else {
                let known = library.importProfiles.values.filter(\.isLedger).map(\.id.rawValue).sorted()
                throw CLIError("There's no import profile \"\(profile)\" in imports/. "
                    + (known.isEmpty ? "The library has no ledger profile yet: save one with --save-profile <id>."
                        : "Ledger profiles: \(known.joined(separator: ", "))."))
            }
            guard found.isLedger else {
                throw CLIError("imports/\(profile).json reads spreadsheets, not journals: use it with "
                    + "`retire import <file> --profile \(profile)`.")
            }
            saved = found
        }
        var session = LedgerImportSession(journal: journal, profile: saved)
        if let frequency { session.setFrequency(frequency.value) }
        if let transactionPrices { session.setTransactionPrices(transactionPrices) }
        if let cashChecks { session.setCashChecks(cashChecks) }
        if let onConflict { session.profile.onConflict = onConflict.policy }
        return session
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
        return URL(fileURLWithPath: files.first ?? "Journal").deletingPathExtension().lastPathComponent
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

    /// Backs up the files the import changes, writes them (and the profile,
    /// if asked), and records in the backup what was written, as the
    /// spreadsheet import does, so `retire import --undo` works the same.
    private func write(_ result: ImportResult, session: LedgerImportSession, ledgerPreview: LedgerImportPreview,
                       loaded: LoadedLibrary, context: CLIContext) throws -> ImportReport.Outcome {
        var outcome = ImportReport.Outcome(result: result)
        let newProfile = saveProfile.map {
            session.makeProfile(id: ImportProfileID($0), name: profileName(loaded.library), from: ledgerPreview,
                                library: result.library)
        }
        guard result.hasChanges || newProfile != nil else { return outcome }
        try loaded.checkWritable()
        if let newProfile, loaded.library.importProfiles[newProfile.id] != nil, newProfile.id.rawValue != profile {
            throw CLIError("\(LibraryFile.importProfile(newProfile.id).path) already exists. Choose another ID, or "
                + "update it with --profile \(newProfile.id) --save-profile \(newProfile.id).")
        }
        var backup: Backup?
        if result.hasChanges {
            var paths = result.library.files(changedFrom: loaded.library).map(\.path)
            if let newProfile { paths.append(LibraryFile.importProfile(newProfile.id).path) }
            backup = try loaded.folder.backup(paths: paths, label: ImportCommand.backupLabel, date: context.now())
            outcome.backup = backup?.path
            let saved = try loaded.folder.save(result.library, previous: loaded.library)
            outcome.written = saved.written
            outcome.deleted = saved.deleted
        }
        if let newProfile {
            let path = try save(newProfile, in: loaded)
            outcome.savedProfile = path
            if !outcome.written.contains(path) { outcome.written.append(path) }
        }
        if let backup { try loaded.folder.recordResult(of: backup) }
        return outcome
    }
}
