import ArgumentParser
import Foundation
import Importer
import Model
import Storage

/// `retire import statements <file>…`: several bank statements at once
/// (IMPORT.md, "Several statements at once"), each file's account found,
/// the transfers between them paired, and the files applied in order.
struct ImportStatementsCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "statements",
        abstract: "Import several bank statements at once.",
        discussion: """
            Each file is one cash or savings account's statement, read with the first saved \
            statement profile that reads all its columns, else with a proposed mapping. Its account \
            is the profile's, else the one account its balance follows on from, else the one account \
            or bank its name or title rows name; give the others with --account "<file>=<id>". \
            A line out of one account and a line in of another, the same amount within 4 days, are \
            a transfer between them. The files are previewed and imported by account, then date, so \
            each month follows on from the one before, and listed with the days one account's files \
            leave out or cover twice.

            Nothing is written unless you pass --apply, and then only when every file has an account \
            and no two files of an account cover the same days. One --undo takes the whole import back.
            """)

    @Argument(help: ArgumentHelp("The statements' CSV or TSV files.", valueName: "file"))
    var files: [String] = []

    @OptionGroup var options: LibraryOptions

    @Option(name: .customLong("account"), parsing: .singleValue,
            help: ArgumentHelp("The account of a file, by its path or name, e.g. --account \"export.csv=conto\". "
                                   + "Repeatable.", valueName: "file=id"))
    var accounts: [String] = []

    @Option(name: .customLong("class"), parsing: .singleValue,
            help: ArgumentHelp("Make every line of the files whose text has these words income, spending, oneOff, "
                                   + "tax, transfer, interest or ignore. Repeatable.", valueName: "words=class"))
    var classes: [String] = []

    @Option(name: .customLong("move"), parsing: .singleValue,
            help: ArgumentHelp("Every line of the files whose text has these words moves money to or from this "
                                   + "account, a transfer; a tax pot's values follow from it. Repeatable.",
                               valueName: "words=account"))
    var moves: [String] = []

    @Option(name: .customLong("purchase"), parsing: .singleValue,
            help: ArgumentHelp("A line out, by words only it has, or <file>:<row>, is a purchase you keep: it starts an "
                                   + "account of this kind (belongings, property or other) and name. Repeatable.",
                               valueName: "line=kind:name"))
    var purchases: [String] = []

    @Option(name: .customLong("sale"), parsing: .singleValue,
            help: ArgumentHelp("A line in, by words only it has, or <file>:<row>, is the sale of this account: it's "
                                   + "worth nothing after it, and closes. Repeatable.", valueName: "line=account"))
    var sales: [String] = []

    @Option(help: ArgumentHelp("Which month ends before the library's first check-in get a value: months (every "
                                   + "one), quarters or none (the lines are one stretch up to the file's last day). "
                                   + "Month ends from the first check-in on always do. Default: months.",
                               valueName: "ends"))
    var beforeFirstCheckIn: CheckInEnds?

    /// ``Importer/StatementCheckIns/Ends``, as an option.
    enum CheckInEnds: String, ExpressibleByArgument, CaseIterable {
        case months
        case quarters
        case never = "none"

        var ends: StatementCheckIns.Ends {
            switch self {
            case .months: .months
            case .quarters: .quarters
            case .never: .never
            }
        }
    }

    @Option(help: ArgumentHelp("The date pattern of every file, e.g. dd/MM/yyyy or MM/dd/yyyy. Default: each "
                                   + "file's profile, else detected.", valueName: "pattern"))
    var dateFormat: String?

    @Option(help: ArgumentHelp("Records that differ from the library: keep, overwrite or ask (kept). "
                                   + "Default: each profile's.", valueName: "policy"))
    var onConflict: ImportCommand.Conflicts?

    @Flag(help: "Only preview; write nothing. This is the default.")
    var dryRun = false

    @Flag(help: "Import: back up the files that change, then write them.")
    var apply = false

    @Flag(help: "With --apply, close accounts whose values stop before a file's last date.")
    var acceptClosings = false

    @Flag(help: "With --apply, import even if some formats are guesses (see “Formats to confirm”).")
    var acceptGuesses = false

    @Option(help: ArgumentHelp("How many lines and records each file lists.", valueName: "count"))
    var rows = 5

    @Flag(help: "Print JSON.")
    var json = false

    func validate() throws {
        if files.isEmpty { throw ValidationError("Give the statements to import.") }
        if apply, dryRun { throw ValidationError("Choose --dry-run or --apply, not both.") }
        for mapping in accounts where Self.accountMapping(mapping) == nil {
            throw ValidationError("--account needs a file and an account ID, e.g. --account \"export.csv=conto\", "
                + "not “\(mapping)”.")
        }
        for rule in classes where ImportCommand.classRule(rule) == nil {
            throw ValidationError("--class needs words and a class (income, spending, oneOff, tax, transfer, "
                + "interest or ignore), e.g. --class \"Giroconto=transfer\", not “\(rule)”.")
        }
        for move in moves where ImportCommand.moveRule(move) == nil {
            throw ValidationError("--move needs words and an account ID, e.g. --move \"Steuer-Rücklage=tax-pot\", "
                + "not “\(move)”.")
        }
        for purchase in purchases where ImportCommand.assetAnswer(purchase, sale: false) == nil {
            throw ValidationError("--purchase needs a line, a kind (belongings, property or other) and a name, e.g. "
                + "--purchase \"Autosalone=belongings:Car\", not “\(purchase)”.")
        }
        for sale in sales where ImportCommand.assetAnswer(sale, sale: true) == nil {
            throw ValidationError("--sale needs a line and an account ID, e.g. --sale \"Rogito=casa\", not “\(sale)”.")
        }
        if rows < 0 { throw ValidationError("--rows can't be negative.") }
    }

    /// `export.csv=conto` → the file and the account; `nil` unless the ID is valid.
    static func accountMapping(_ text: String) -> (file: String, account: AccountID)? {
        guard let equals = text.lastIndex(of: "=") else { return nil }
        let file = text[..<equals].trimmingCharacters(in: .whitespaces)
        let account = text[text.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard !file.isEmpty, Slug.isValid(account) else { return nil }
        return (file, AccountID(account))
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let library = loaded.library
        var read: [(name: String, data: Data)] = []
        for path in files {
            let url = context.url(forPath: path)
            do {
                read.append((url.lastPathComponent, try Data(contentsOf: url)))
            } catch {
                throw CLIError("Can't read \(url.path): \(error.localizedDescription)")
            }
        }
        var statements = StatementImport(StatementBatch(files: read, library: library, today: context.today),
                                         paths: files)
        try chooseAccounts(&statements.batch, library: library, today: context.today)
        if let beforeFirstCheckIn {
            let checkIns = StatementCheckIns(ends: beforeFirstCheckIn.ends, before: library)
            statements.batch.setCheckIns(checkIns, library: library, today: context.today)
        }
        statements.batch.editSessions(library: library, today: context.today) { _, session in
            for rule in classes {
                if let (words, statementClass) = ImportCommand.classRule(rule) {
                    session.setStatementRule(statementClass, for: words)
                }
            }
            for move in moves {
                if let (words, account) = ImportCommand.moveRule(move) {
                    session.setStatementRule(movingTo: account, for: words)
                }
            }
            if let dateFormat {
                var date = session.profile.defaults.date ?? ImportDateFormat()
                date.pattern = dateFormat
                session.profile.defaults.date = date
            }
            if let onConflict { session.profile.onConflict = onConflict.policy }
        }
        try statements.answer(purchases: purchases, sales: sales, library: library, today: context.today)

        let previews = statements.batch.previews(against: library, today: context.today) { _, preview in
            preview = ImportDecisions(acceptsNewAccounts: false, acceptsClosings: acceptClosings).applied(to: preview)
        }
        var report = ImportStatementsReport(batch: statements.batch, previews: previews,
                                            gaps: StatementBatch.gaps(in: previews, batch: statements.batch),
                                            library: library, apply: apply, rows: rows)
        let blocked = report.blockers(acceptGuesses: acceptGuesses)
        if apply, blocked.isEmpty {
            let result = statements.batch.apply(previews.map(\.preview), to: library, remembering: false).result
            var outcome = ImportReport.Outcome(result: result)
            if result.hasChanges {
                try loaded.checkWritable()
                let saved = try loaded.save(result.library, backupLabel: Backup.importLabel, in: context)
                outcome.written = saved.written
                outcome.deleted = saved.deleted
                outcome.backup = saved.backup
            }
            report.outcome = outcome
        }
        try context.console.print(report, json: json)
        if apply, let first = blocked.first {
            throw CLIError("Nothing was imported: \(first)")
        }
    }

    /// Gives the files --account names their accounts.
    private func chooseAccounts(_ batch: inout StatementBatch, library: Library, today: CalendarDate) throws {
        let candidates = Set(StatementBatch.statementAccounts(in: library).map(\.id))
        for mapping in accounts {
            guard let (named, account) = Self.accountMapping(mapping) else { continue }
            let matches = batch.files.filter { file in
                file.name == named || files[file.id] == named
            }
            guard let file = matches.first, matches.count == 1 else {
                throw CLIError(matches.isEmpty ? "--account: no file is “\(named)”."
                    : "--account: “\(named)” is \(matches.count) files; name one by its path.")
            }
            guard candidates.contains(account) else {
                throw CLIError("--account: “\(account)” isn't an open cash or savings account of the library that "
                    + "doesn't record trades.")
            }
            batch.setAccount(account, forFile: file.id, library: library, today: today)
        }
    }
}

/// Bank statements being imported from the command line, as a batch:
/// `retire import statements`, and `retire import` with one statement.
struct StatementImport {
    var batch: StatementBatch
    /// The paths the files were given by, by their place, the files' IDs.
    var paths: [String]

    init(_ batch: StatementBatch, paths: [String]) {
        self.batch = batch
        self.paths = paths
    }

    /// Answers the lines --purchase and --sale name, each by words only one
    /// line of the files has, by `<file>:<row>`, or with one file by its row.
    mutating func answer(purchases: [String], sales: [String], library: Library, today: CalendarDate) throws {
        let answers = purchases.compactMap { ImportCommand.assetAnswer($0, sale: false) }
            + sales.compactMap { ImportCommand.assetAnswer($0, sale: true) }
        guard !answers.isEmpty else { return }
        var lines: [(file: StatementBatch.File, line: StatementLine)] = []
        for file in batch.files {
            lines += batch.preview(of: file, against: library, today: today).statementLines.map { (file, $0) }
        }
        // Without lines the report says why: the account, the layout or the file.
        guard !lines.isEmpty else { return }
        let one = batch.files.count == 1
        func place(_ match: (file: StatementBatch.File, line: StatementLine)) -> String {
            one ? "row \(match.line.row)" : "\(match.file.name):\(match.line.row)"
        }
        var answered: [String: String] = [:]
        var assets: [Int: [Int: StatementAsset]] = [:]
        for (named, asset) in answers {
            let matches: [(file: StatementBatch.File, line: StatementLine)]
            if one, let row = Int(named) {
                matches = lines.filter { $0.line.row == row }
            } else if !one, let colon = named.lastIndex(of: ":"), let row = Int(named[named.index(after: colon)...]) {
                let file = String(named[..<colon])
                matches = lines.filter { ($0.file.name == file || paths[$0.file.id] == file) && $0.line.row == row }
            } else {
                matches = lines.filter { $0.line.hasWords(named) }
            }
            let option = if case .sale = asset { "--sale" } else { "--purchase" }
            guard let match = matches.first, matches.count == 1 else {
                let places = matches.map(place)
                throw CLIError(matches.isEmpty
                    ? "\(option): no line of the \(one ? "statement" : "files") is “\(named)”."
                    : one ? "\(option): “\(named)” is in \(matches.count) lines (rows "
                        + matches.map { "\($0.line.row)" }.joined(separator: ", ") + "): name one by its row."
                    : "\(option): “\(named)” is in \(matches.count) lines (" + places.joined(separator: ", ")
                        + "): name one as <file>:<row>.")
            }
            let key = place(match)
            if let earlier = answered[key] {
                throw CLIError("“\(earlier)” and “\(named)” both answer \(key): give it one answer.")
            }
            answered[key] = named
            assets[match.file.id, default: [:]][match.line.row] = asset
        }
        batch.editSessions(library: library, today: today) { id, session in
            for (row, asset) in assets[id] ?? [:] {
                session.setStatementAsset(asset, forRow: row)
            }
        }
    }
}

/// What `retire import statements` prints: each file with its account and
/// days, the gaps between an account's files, then each file's lines and
/// preview, and what was written.
struct ImportStatementsReport: CommandReport {
    let batch: StatementBatch
    let previews: [(file: Int, preview: ImportPreview)]
    let gaps: [StatementGap]
    let library: Library
    let apply: Bool
    let rows: Int
    var outcome: ImportReport.Outcome?

    private func file(_ id: Int) -> StatementBatch.File? { batch.files.first { $0.id == id } }

    private func preview(_ id: Int) -> ImportPreview? { previews.first { $0.file == id }?.preview }

    /// What stops --apply, as sentences: files without an account, days two
    /// files cover, and guessed formats.
    func blockers(acceptGuesses: Bool) -> [String] {
        var blockers: [String] = []
        let unknown = batch.files.filter { $0.account == nil }.map(\.name)
        if !unknown.isEmpty {
            blockers.append("\(Wording.list(unknown)) \(unknown.count == 1 ? "has" : "have") no account. Give it with "
                + "--account \"<file>=<id>\".")
        }
        for gap in gaps where gap.isOverlap {
            blockers.append("\(name(gap.before)) and \(name(gap.after)) both cover \(gap.from) to \(gap.through) of "
                + "\(gap.account), so their lines would count twice. Leave one out, or import them one at a time "
                + "with --from and --through.")
        }
        if !acceptGuesses, previews.contains(where: { !$0.preview.ambiguities.isEmpty }) {
            blockers.append("some formats are guesses (see “Formats to confirm”). Settle them with --date-format, "
                + "or pass --accept-guesses.")
        }
        return blockers
    }

    private func name(_ id: Int) -> String { file(id)?.name ?? "file \(id + 1)" }

    static func foundBy(_ source: StatementBatch.AccountSource?) -> String {
        switch source {
        case .profile?: "its profile"
        case .balance(let date)?: "follows on from \(date)"
        case .named?: "named in the file"
        case .chosen?: "--account"
        case nil: "—"
        }
    }

    private func paired(_ id: Int) -> Int {
        preview(id)?.statementLines.filter { if case .paired = $0.source { true } else { false } }.count ?? 0
    }

    // MARK: - Text

    func lines() -> [String] {
        var table = TextTable([.left("File"), .left("Account"), .left("Found by"), .left("Days"), .right("Lines"),
                               .right("Paired")])
        for file in batch.files {
            let period = preview(file.id)?.statementPeriod.map { "\($0.from) to \($0.through)" } ?? ""
            table.add([ImportReport.clip(file.name, 32), file.account?.rawValue ?? "—",
                       Self.foundBy(file.accountSource), period,
                       preview(file.id).map { "\($0.statementLines.count)" } ?? "", "\(paired(file.id))"])
        }
        var lines = ["Files"] + table.lines()
        let unknown = batch.files.filter { $0.account == nil }
        if !unknown.isEmpty {
            lines.append("  Give a file's account with --account \"<file>=<id>\": "
                + StatementBatch.statementAccounts(in: library).map(\.id.rawValue).joined(separator: ", ") + ".")
        }
        lines += section("Can't read", batch.unreadable.map { "  \($0.name): \($0.error)" })
        lines += section("Gaps and overlaps", gaps.map { gap in
            gap.isOverlap
                ? "  \(gap.account): \(gap.from) to \(gap.through) is in both \(name(gap.before)) and "
                    + "\(name(gap.after)); its lines would count twice."
                : "  \(gap.account): \(gap.from) to \(gap.through) is in no file (between \(name(gap.before)) and "
                    + "\(name(gap.after))), so the next value's money in and out leave it out."
        })
        for (id, preview) in previews {
            guard let file = file(id) else { continue }
            let report = fileReport(file, preview)
            lines += ["", "\(file.name) → \(file.account?.rawValue ?? "?")"]
            lines += report.statementLines()
            lines += section("  Formats to confirm", report.ambiguityLines())
            lines += section("  Problems", report.problems.map { "  \($0)" })
            lines += section("  Notes", report.noteLines())
            lines += section("  " + report.newAccountsTitle, report.newAccountLines())
            lines += section("  Account changes", report.accountChangeLines())
            lines += section("  Preview: \(preview.summary)", report.previewLines())
            lines += section("  " + report.conflictsTitle, report.conflictLines())
            lines += section("  Cells that can't be read (\(preview.cellErrors.count))", report.cellErrorLines())
        }
        lines.append("")
        lines.append("  Correct a class with --class \"<words in the text>=<class>\" (income, spending, oneOff, "
            + "tax, transfer, interest or ignore). Money moved to or from an account: --move \"<words>=<account>\". "
            + "A line out for something you keep: --purchase "
            + "\"<words or file:row>=belongings:<name>\"; a line in from selling one: --sale \"<words or file:row>="
            + "<account>\".")
        lines.append("")
        if let outcome {
            lines += ImportReport.outcomeLines(outcome, files: previews.count)
        } else if apply {
            lines.append("Nothing was written.")
        } else {
            lines.append("Dry run: nothing was written. To import, run again with --apply.")
        }
        return lines
    }

    private func section(_ title: String, _ body: [String]) -> [String] {
        body.isEmpty ? [] : ["", title] + body
    }

    private func fileReport(_ file: StatementBatch.File, _ preview: ImportPreview) -> ImportReport {
        var report = ImportReport(fileName: file.name, profileID: nil, session: file.session, preview: preview,
                                  library: library, apply: apply, rows: rows)
        report.showsStatementOptions = false
        return report
    }

    // MARK: - JSON

    var json: JSON {
        JSON(
            mode: apply ? "apply" : "dry-run",
            files: batch.files.map { file in
                let found: String? = switch file.accountSource {
                case .profile?: "profile"
                case .balance?: "balance"
                case .named?: "named"
                case .chosen?: "chosen"
                case nil: nil
                }
                return JSON.File(name: file.name, account: file.account?.rawValue, found: found,
                                 report: preview(file.id).map { fileReport(file, $0).json })
            },
            unreadable: batch.unreadable.map { JSON.Unreadable(name: $0.name, error: "\($0.error)") },
            gaps: gaps.map {
                JSON.Gap(account: $0.account.rawValue, before: name($0.before), after: name($0.after),
                         from: $0.from.description, through: $0.through.description, overlap: $0.isOverlap)
            },
            result: outcome.map(ImportReport.JSON.Result.init))
    }

    struct JSON: Encodable {
        struct File: Encodable {
            var name: String
            var account: String?
            /// How the account was found: profile, balance, named or chosen.
            var found: String?
            /// The file's report, as `retire import --json` prints one; `nil` without an account.
            var report: ImportReport.JSON?
        }

        struct Unreadable: Encodable {
            var name: String
            var error: String
        }

        struct Gap: Encodable {
            var account: String
            var before: String
            var after: String
            var from: String
            var through: String
            var overlap: Bool
        }

        var mode: String
        var files: [File]
        var unreadable: [Unreadable]
        var gaps: [Gap]
        var result: ImportReport.JSON.Result?
    }
}
