import Foundation
import Importer
import Model

/// A step of the import, shown along the top (UI.md, "Import"; IMPORT.md, "Steps").
/// A broker's transactions (the trades layout) have Types after Columns. Bank
/// statements (the statement layout) have Files and Review, with
/// Format and Columns in a sheet the Files step opens. Done follows the last
/// step, and isn't one along the top (``ImportFlow/barSteps``).
enum ImportStep: Int, Hashable, Sendable, Comparable {
    case file
    case format
    case columns
    case types
    case accounts
    case preview
    case done

    var title: String {
        switch self {
        case .file: "Files"
        case .format: "Format"
        case .columns: "Columns"
        case .types: "Types"
        case .accounts: "Accounts"
        case .preview: "Review"
        case .done: "Done"
        }
    }

    static func < (lhs: ImportStep, rhs: ImportStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Where an import's mapping comes from.
enum ImportSource: Hashable, Sendable {
    /// Proposed by the importer from the headers and the values.
    case proposed
    /// A saved profile, `imports/<id>.json`.
    case profile(ImportProfileID)

    var profileID: ImportProfileID? {
        if case .profile(let id) = self { id } else { nil }
    }
}

/// An import in progress, as plain values: the file, the mapping being
/// built (an `ImportSession`), the preview it gives against the library,
/// and what the user decided along the way. The Import screen shows it and
/// edits it through its methods; ``ImportController`` does the writing.
///
/// Every bank statement is read as part of a batch (``batch``), one file
/// or many; any other file is one ``session``. Either way the previews
/// are one list (``previews``), and every change to the mapping or to the
/// user's decisions (``ImportDecisions``: proposed accounts edited,
/// closings rejected, conflicts decided) makes them again.
struct ImportFlow: Sendable {
    /// The file's name, e.g. `net-worth.csv`.
    private(set) var fileName: String?
    /// The file's bytes, kept to read it again with another profile.
    private(set) var data: Data?
    /// The file as read and the mapping; `nil` until a file is read.
    private(set) var session: ImportSession?
    /// Where the mapping came from.
    private(set) var source: ImportSource = .proposed
    /// The library the preview compares with (see ``setLibrary(_:)``).
    private(set) var library: Library
    /// What the import would do, file by file, with ``decisions`` applied,
    /// in the order the files are imported: each of the batch's files that
    /// has an account, by ``StatementBatch/File/id``, against the library
    /// with the files before it imported; or another kind of file's one
    /// preview.
    private(set) var previews: [(file: Int, preview: ImportPreview)] = []
    /// What importing would do now: the previews applied to ``library``.
    private(set) var planned: ImportResult?
    /// A bank statement's charts of ``planned`` (``makeStatementCharts()``),
    /// kept so Preview doesn't work them out again on every redraw.
    private(set) var statementCharts: ImportStatementCharts?
    /// What the user decided about proposals and conflicts.
    private(set) var decisions = ImportDecisions()
    /// Why the file, or the last change to how it's read, didn't work.
    private(set) var problem: String?
    /// The saved profiles, the ones that fit the file best first.
    private(set) var profileFits: [ProfileFit] = []
    /// The step on screen.
    private(set) var step: ImportStep = .file
    /// The bank statements open (IMPORT.md, "Several statements at
    /// once"), one or more; `nil` for another kind of file. ``session`` is
    /// then the file on screen (``batchFile``), kept in step with the batch.
    private(set) var batch: StatementBatch?
    /// Every file given, in order, those that couldn't be read included:
    /// a batch's file `id` is at index `id`. Kept to read the files again
    /// as another kind (``setLayout(_:)``).
    private(set) var givenFiles: [(name: String, data: Data)] = []
    /// The batch's file on screen, by ``StatementBatch/File/id``.
    private(set) var batchFile: Int?

    /// The date of the check-in the import is for, when it's opened from
    /// one: a bank statement then covers through that date
    /// (``ImportSession/statementCheckIn``).
    private(set) var checkIn: CalendarDate?

    init(library: Library = Library(), checkIn: CalendarDate? = nil) {
        self.library = library
        self.checkIn = checkIn
    }

    /// The preview of the file on screen; `nil` while there's none, or the
    /// batch's file on screen has no account.
    var preview: ImportPreview? {
        guard batch != nil else { return previews.first?.preview }
        return previews.first { $0.file == batchFile }?.preview
    }

    // MARK: - The file

    /// Reads a file. A saved profile that fits it exactly is used right away;
    /// otherwise the importer proposes a mapping. A bank statement opens as
    /// a batch of one (``open(statements:)``), so more can be added.
    mutating func open(_ data: Data, fileName: String) {
        openOne(data, fileName: fileName)
        if layout == .statement { open(statements: [(fileName, data)]) }
    }

    /// Reads one file as ``open(_:fileName:)`` does, without making a bank
    /// statement a batch.
    private mutating func openOne(_ data: Data, fileName: String) {
        self = ImportFlow(library: library, checkIn: checkIn)
        self.data = data
        self.fileName = fileName
        givenFiles = [(fileName, data)]
        profileFits = ProfileFit.rank(data, profiles: Array(library.importProfiles.values))
        if let best = profileFits.first, best.fits {
            load(profile: best.profile)
        } else {
            load(profile: nil)
        }
    }

    /// Reads `file` alone, as `layout`. The files given stay, to read
    /// them as statements again.
    mutating func reopen(_ file: (name: String, data: Data), as layout: ImportLayout) {
        let given = givenFiles
        openOne(file.data, fileName: file.name)
        givenFiles = given
        if self.layout != layout { editSession { $0.proposeMapping(layout: layout) } }
    }

    /// Reads several files at once as bank statements: each file's account
    /// is found and the transfers between them paired (``StatementBatch``),
    /// and the first file is shown. One file opens as ``open(_:fileName:)``
    /// does: a statement, or another kind of file.
    mutating func open(files: [(name: String, data: Data)]) {
        guard files.count > 1 else {
            if let file = files.first { open(file.data, fileName: file.name) }
            return
        }
        open(statements: files)
    }

    /// Reads `files` as bank statements, however many.
    mutating func open(statements files: [(name: String, data: Data)]) {
        self = ImportFlow(library: library, checkIn: checkIn)
        givenFiles = files
        let batch = StatementBatch(files: files, library: library, checkIn: checkIn)
        guard let first = batch.order(against: library).first ?? batch.files.first?.id else {
            fileName = files.count == 1 ? files[0].name : Wording.count(files.count, "file")
            problem = (files.count == 1 ? "The file can't be read as a bank statement. "
                : "None of the files can be read as a bank statement. ")
                + batch.unreadable.map { "\($0.name): \(Self.describe($0.error))" }.joined(separator: " ")
            return
        }
        self.batch = batch
        showBatchFile(first)
        refreshPreview()
    }

    /// Adds files to the bank statements open: the files already open keep
    /// their accounts and answers (``StatementBatch/add(files:library:checkIn:today:)``).
    /// With no file open they're opened; with another kind of file open,
    /// they take its place.
    mutating func add(files: [(name: String, data: Data)]) {
        guard !files.isEmpty else { return }
        guard var batch, step != .done else {
            open(files: files)
            return
        }
        batch.add(files: files, library: library, checkIn: checkIn)
        givenFiles += files
        self.batch = batch
        problem = nil
        refreshPreview()
        if batchFile == nil, let first = batch.files.first?.id { showBatchFile(first) }
    }

    /// Takes the batch's file `id` out of the import. Taking out the last
    /// file starts over.
    mutating func remove(file id: Int) {
        guard var batch else { return }
        batch.remove(file: id, library: library)
        guard let next = batch.order(against: library).first ?? batch.files.first?.id else {
            reset()
            return
        }
        self.batch = batch
        if batchFile == id {
            batchFile = nil
            showBatchFile(next)
        }
        refreshPreview()
    }

    /// Shows one of the batch's files on the steps that show one file:
    /// its preview on Review, how it's read.
    mutating func showBatchFile(_ id: Int) {
        guard let file = batch?.files.first(where: { $0.id == id }) else { return }
        batchFile = id
        fileName = file.name
        session = file.session
        source = library.importProfiles[file.session.profile.id] == nil ? .proposed : .profile(file.session.profile.id)
    }

    /// Makes `account` the account of the batch's file `id`, or takes it
    /// away, and pairs the transfers between the files again.
    mutating func setBatchAccount(_ account: AccountID?, forFile id: Int) {
        guard var batch else { return }
        batch.setAccount(account, forFile: id, library: library)
        if let file = batch.files.first(where: { $0.id == batchFile }) { session = file.session }
        self.batch = batch
        refreshPreview()
    }

    /// Sets where the values before the library's first check-in go, in
    /// every file.
    mutating func setFirstCheckInEnds(_ ends: StatementCheckIns.Ends) {
        guard var batch else { return }
        let checkIns = ends == .months ? nil : StatementCheckIns(ends: ends, before: library)
        batch.setCheckIns(checkIns, library: library)
        if let file = batch.files.first(where: { $0.id == batchFile }) { session = file.session }
        self.batch = batch
        refreshPreview()
    }

    /// Records that a file couldn't be opened at all (e.g. no permission).
    mutating func failToOpen(fileName: String, message: String) {
        self = ImportFlow(library: library, checkIn: checkIn)
        self.fileName = fileName
        problem = message
    }

    /// Reads the file again with a saved profile, or with a mapping the
    /// importer proposes (`nil`). Decisions start over. A bank statement's
    /// profile makes the file a batch of one, as every statement is.
    mutating func useProfile(_ id: ImportProfileID?) {
        load(profile: id.flatMap { library.importProfiles[$0] })
        guard layout == .statement, let session, let fileName else { return }
        let batch = StatementBatch(sessions: [(fileName, session)], library: library)
        self.batch = batch
        if let first = batch.files.first?.id { showBatchFile(first) }
        refreshPreview()
    }

    /// Forgets the file: back to the first step.
    mutating func reset() {
        self = ImportFlow(library: library, checkIn: checkIn)
    }

    /// Whether a file has been read.
    var hasFile: Bool { session != nil }

    /// The saved profile the mapping came from, if any.
    var sourceProfile: ImportProfile? {
        source.profileID.flatMap { library.importProfiles[$0] }
    }

    private mutating func load(profile: ImportProfile?) {
        guard let data else { return }
        decisions = ImportDecisions()
        batch = nil
        batchFile = nil
        do {
            if let profile {
                session = try ImportSession(data: data, profile: profile)
                source = .profile(profile.id)
            } else {
                session = try ImportSession(data: data)
                source = .proposed
            }
            session?.statementCheckIn = checkIn
            problem = nil
        } catch {
            session = nil
            problem = Self.describe(error)
        }
        refreshPreview()
    }

    // MARK: - The library

    /// Keeps the preview in step with the library, which can change while
    /// the import is open (a sync from the other device, a profile saved).
    /// After importing, the preview is left as it was.
    mutating func setLibrary(_ library: Library) {
        // Making every preview again is slow; the same library changes none of them.
        guard library != self.library else { return }
        let profilesChanged = library.importProfiles != self.library.importProfiles
        self.library = library
        guard step != .done else { return }
        if profilesChanged, let data {
            profileFits = ProfileFit.rank(data, profiles: Array(library.importProfiles.values))
        }
        refreshPreview()
    }

    // MARK: - Steps

    /// The steps along the top: ``steps`` without Done.
    var barSteps: [ImportStep] { steps.filter { $0 != .done } }

    /// The steps, in order: those along the top, then Done.
    var steps: [ImportStep] {
        if session?.profile.layout == .trades { return [.file, .format, .columns, .types, .accounts, .preview, .done] }
        if session?.profile.layout == .statement {
            // Accounts only for a proposed opening or closing.
            let proposed = previews.contains { Self.proposesAccountChange($0.preview) }
            let accounts: [ImportStep] = proposed ? [.accounts] : []
            return [.file] + accounts + [.preview, .done]
        }
        return [.file, .format, .columns, .accounts, .preview, .done]
    }

    /// Whether `step` can be shown now: every step but the first needs a
    /// file (and a bank statement its account), Done comes only from
    /// importing, and nothing goes back from Done.
    func canShow(_ step: ImportStep) -> Bool {
        guard steps.contains(step) else { return false }
        switch step {
        case .done: return self.step == .done
        case .file: return self.step != .done
        default: return hasFile && !needsStatementAccount && self.step != .done
        }
    }

    /// Whether a bank statement is without an account it can be of: none
    /// chosen yet, or one a saved profile left that isn't a choice
    /// (``statementAccountChoices``). No step after File can be shown
    /// until each has one.
    var needsStatementAccount: Bool { batchFileWithoutAccount != nil }

    /// The first of the batch's files without an account it can be of.
    var batchFileWithoutAccount: StatementBatch.File? {
        batch?.files.first { file in !statementAccountChoices.contains { $0.id == file.account } }
    }

    /// Why Continue waits, next to it; `nil` when it doesn't wait for you.
    var continueHint: String? {
        if let file = batchFileWithoutAccount { return "Choose the account of \(file.name) to continue." }
        return needsStatementAccount ? "Choose the account this statement is of." : nil
    }

    /// Shows a step, if it can be shown.
    mutating func show(_ step: ImportStep) {
        if canShow(step) { enter(step) }
    }

    /// The step after this one; `nil` from Preview (next is importing) and Done.
    var nextStep: ImportStep? {
        guard step < .preview, let index = steps.firstIndex(of: step), index + 1 < steps.count else { return nil }
        let next = steps[index + 1]
        return canShow(next) ? next : nil
    }

    /// The step before this one; `nil` on the first step and on Done.
    var previousStep: ImportStep? {
        guard step != .done, let index = steps.firstIndex(of: step), index > 0 else { return nil }
        return steps[index - 1]
    }

    mutating func goForward() {
        if let nextStep { enter(nextStep) }
    }

    mutating func goBack() {
        if let previousStep { enter(previousStep) }
    }

    /// Shows `step`. With several files, Accounts lists one file's opening
    /// or closing, so it opens on the first file that proposes one when the
    /// file on screen doesn't.
    private mutating func enter(_ step: ImportStep) {
        self.step = step
        guard step == .accounts, batch != nil, !Self.proposesAccountChange(preview),
              let first = previews.first(where: { Self.proposesAccountChange($0.preview) }) else { return }
        showBatchFile(first.file)
    }

    /// Whether `preview` proposes opening an account earlier or closing one,
    /// which Accounts answers; Income answers a sale's.
    static func proposesAccountChange(_ preview: ImportPreview?) -> Bool {
        preview?.accountChanges.contains { $0.statementRow == nil } ?? false
    }

    /// Moves to Done, after the import was applied.
    mutating func finish() {
        step = .done
    }

    // MARK: - Editing

    /// Changes the mapping, then makes the preview again. A change that makes
    /// the file unreadable (e.g. a header row past the end) is undone, and
    /// ``problem`` says why.
    mutating func editSession(_ edit: (inout ImportSession) throws -> Void) {
        guard var edited = session else { return }
        do {
            try edit(&edited)
            session = edited
            problem = nil
            // The batch pairs its files' transfers again with this file's change.
            if let id = batchFile, var batch {
                let account = edited.profile.constants.account
                if account != batch.files.first(where: { $0.id == id })?.account {
                    // Chosen in How It's Read…, as on the File step.
                    batch.setAccount(account, forFile: id, library: library)
                }
                batch.editSession(ofFile: id, library: library) { $0 = edited }
                session = batch.files.first { $0.id == id }?.session ?? edited
                self.batch = batch
            }
        } catch {
            problem = Self.describe(error)
        }
        refreshPreview()
    }

    /// Changes the session of the batch's file `id`, then makes the
    /// previews again.
    mutating func editSession(ofFile id: Int, _ edit: (inout ImportSession) -> Void) {
        editBatchSessions { file, session in
            if file == id { edit(&session) }
        }
    }

    /// Changes the sessions of every file of the batch at once, each given
    /// with its ID (a rule for every statement, a sender's lines in several
    /// files), then makes the previews again once.
    mutating func editBatchSessions(_ edit: (Int, inout ImportSession) -> Void) {
        guard var batch else { return }
        batch.editSessions(library: library) { edit($0, &$1) }
        self.batch = batch
        if let file = batch.files.first(where: { $0.id == batchFile }) { session = file.session }
        problem = nil
        refreshPreview()
    }

    /// Changes the decisions, and makes the previews again with them.
    mutating func editDecisions(_ edit: (inout ImportDecisions) -> Void) {
        edit(&decisions)
        refreshPreview()
    }

    /// Makes the previews again from the mapping and the library: the
    /// batch's in the order its files are imported, or the one file's; then
    /// what importing them all would do.
    mutating func refreshPreview() {
        let chosen = decisions
        if let batch {
            previews = batch.previews(against: library) { _, preview in
                preview = chosen.applied(to: preview)
            }
        } else if let session, session.profile.layout != .statement {
            // A statement is previewed only in a batch, which knows its account.
            previews = [(0, chosen.applied(to: session.preview(against: library)))]
        } else {
            previews = []
        }
        planned = previews.isEmpty ? nil : ImportPreview.apply(previews.map(\.preview), to: library)
        statementCharts = makeStatementCharts()
        showNearestStep()
    }

    /// A change of layout, or of what the preview proposes, can take away
    /// the step on screen: shows the nearest one before it.
    private mutating func showNearestStep() {
        if step != .done, !steps.contains(step) {
            step = steps.last { $0 < step } ?? .file
        }
    }

    /// A readable message for an error from the importer or the file system.
    static func describe(_ error: any Error) -> String {
        if let error = error as? ImportError { return error.description }
        return error.localizedDescription
    }
}
