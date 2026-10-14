import Foundation
import Importer
import Model

/// A step of the import, shown along the top (UI.md, "Import"; IMPORT.md, "Steps").
/// A broker's transactions (the trades layout) have Types after Columns. Bank
/// statements (the statement layout) have Files, Income and Review, with
/// Format and Columns in a sheet the Files step opens. Done follows the last
/// step, and isn't one along the top (``ImportFlow/barSteps``).
enum ImportStep: Int, Hashable, Sendable, Comparable {
    case file
    case format
    case columns
    case types
    case classify
    case accounts
    case preview
    case done

    var title: String {
        switch self {
        case .file: "Files"
        case .format: "Format"
        case .columns: "Columns"
        case .types: "Types"
        case .classify: "Income"
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
/// Every change to the mapping makes the preview again, and the user's
/// decisions (``ImportDecisions``: proposed accounts edited, closings
/// rejected, conflicts decided) are applied to each new preview.
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
    /// What the import would do, with ``decisions`` applied.
    private(set) var preview: ImportPreview?
    /// The preview as the importer made it, before ``decisions``.
    private var basePreview: ImportPreview?
    /// What importing would do now: the preview applied to ``library``,
    /// with the later values' new money in step (``ImportPreview/applyFollowingFlows(to:)``).
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
    /// iPhone's "Import with profile…": the file and a saved profile, then
    /// the preview. Otherwise every step (the Mac-first flow), as always
    /// for bank statements, which need Files' accounts and Income.
    var isGuided: Bool { prefersGuided && batch == nil }
    /// Whether one file opens as "Import with profile…".
    private(set) var prefersGuided: Bool
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
    /// The previews of the batch's files that have an account, with
    /// ``decisions`` applied, in the order they're imported, each against
    /// the library with the files before it imported.
    private(set) var batchPreviews: [(file: Int, preview: ImportPreview)] = []

    /// The date of the check-in the import is for, when it's opened from
    /// one: a bank statement then covers through that date
    /// (``ImportSession/statementCheckIn``).
    private(set) var checkIn: CalendarDate?

    init(library: Library = Library(), guided: Bool = false, checkIn: CalendarDate? = nil) {
        self.library = library
        prefersGuided = guided
        self.checkIn = checkIn
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
        self = ImportFlow(library: library, guided: prefersGuided, checkIn: checkIn)
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
        self = ImportFlow(library: library, guided: prefersGuided, checkIn: checkIn)
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
    /// its lines on Income, its preview on Preview, how it's read.
    mutating func showBatchFile(_ id: Int) {
        guard let file = batch?.files.first(where: { $0.id == id }) else { return }
        batchFile = id
        fileName = file.name
        session = file.session
        source = library.importProfiles[file.session.profile.id] == nil ? .proposed : .profile(file.session.profile.id)
        if batchPreviews.isEmpty {
            refreshPreview()
        } else {
            preview = batchPreviews.first { $0.file == id }?.preview
            statementCharts = makeStatementCharts()
        }
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

    /// Records that a file couldn't be opened at all (e.g. no permission).
    mutating func failToOpen(fileName: String, message: String) {
        self = ImportFlow(library: library, guided: prefersGuided, checkIn: checkIn)
        self.fileName = fileName
        problem = message
    }

    /// Reads the file again with a saved profile, or with a mapping the
    /// importer proposes (`nil`). Decisions start over.
    mutating func useProfile(_ id: ImportProfileID?) {
        load(profile: id.flatMap { library.importProfiles[$0] })
    }

    /// Forgets the file: back to the first step.
    mutating func reset() {
        self = ImportFlow(library: library, guided: prefersGuided, checkIn: checkIn)
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
        if isGuided { return [.file, .preview, .done] }
        if session?.profile.layout == .trades { return [.file, .format, .columns, .types, .accounts, .preview, .done] }
        if session?.profile.layout == .statement {
            // Accounts only for a proposed opening or closing; Income answers a sale's.
            let previews: [ImportPreview?] = batch == nil ? [preview] : batchPreviews.map { $0.preview }
            let proposed = previews.contains(where: Self.proposesAccountChange)
            let accounts: [ImportStep] = proposed ? [.accounts] : []
            return [.file, .classify] + accounts + [.preview, .done]
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
        case .preview where isGuided:
            // "Import with profile…" needs a profile; the full flow is the fallback.
            return hasFile && source != .proposed && !needsStatementAccount && self.step != .done
        default: return hasFile && !needsStatementAccount && self.step != .done
        }
    }

    /// Whether the file is a bank statement without an account it can be
    /// of: none chosen yet, or one a saved profile or another layout left
    /// that isn't a choice (``statementAccountChoices``). No step after
    /// File can be shown until it is.
    var needsStatementAccount: Bool {
        if batch != nil { return batchFileWithoutAccount != nil }
        return hasFile && layout == .statement && !statementAccountChoices.contains { $0.id == constants.account }
    }

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
              let first = batchPreviews.first(where: { Self.proposesAccountChange($0.preview) }) else { return }
        showBatchFile(first.file)
    }

    /// Whether `preview` proposes opening an account earlier or closing one,
    /// which Accounts answers; Income answers a sale's.
    static func proposesAccountChange(_ preview: ImportPreview?) -> Bool {
        preview?.accountChanges.contains { $0.statementRow == nil } ?? false
    }

    /// Switches between "Import with profile…" (iPhone) and every step.
    mutating func setGuided(_ guided: Bool) {
        prefersGuided = guided
        if !steps.contains(step) { step = .file }
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

    /// Changes the decisions and applies them to the preview (which isn't
    /// made again: decisions don't change what the file says).
    mutating func editDecisions(_ edit: (inout ImportDecisions) -> Void) {
        edit(&decisions)
        if batch != nil {
            refreshBatch()
        } else {
            setPreview(basePreview)
        }
    }

    /// Makes the preview again from the mapping and the library.
    mutating func refreshPreview() {
        if batch != nil {
            refreshBatch()
        } else {
            setPreview(session?.preview(against: library))
        }
    }

    /// Makes every file's preview of the batch again, and what importing
    /// them all would do.
    private mutating func refreshBatch() {
        guard let batch else { return }
        let chosen = self.decisions
        batchPreviews = batch.previews(against: library, decide: { _, preview in
            preview = chosen.applied(to: preview)
        }, apply: { $0.applyFollowingFlows(to: $1) })
        basePreview = nil
        preview = batchPreviews.first { $0.file == batchFile }?.preview
        planned = StatementBatch.apply(batchPreviews.map(\.preview), to: library) { $0.applyFollowingFlows(to: $1) }
        statementCharts = makeStatementCharts()
        showNearestStep()
    }

    private mutating func setPreview(_ base: ImportPreview?) {
        basePreview = base
        preview = base.map { decisions.applied(to: $0) }
        planned = preview?.applyFollowingFlows(to: library)
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

// MARK: - Decisions

/// What the user decided in the Accounts and Preview steps. Kept apart from
/// the preview, so it survives the preview being made again after the
/// mapping changes.
struct ImportDecisions: Hashable, Sendable {
    /// Changes to proposed accounts, by ID.
    var accounts: [AccountID: ProposalEdit<AccountKind>] = [:]
    /// Changes to proposed instruments, by ID.
    var instruments: [InstrumentID: ProposalEdit<InstrumentKind>] = [:]
    /// Proposed account changes accepted (`true`) or rejected (`false`).
    var accountChanges: [AccountChangeKey: Bool] = [:]
    /// The policy for every conflict; `nil` keeps the profile's.
    var conflictPolicy: ConflictPolicy?
    /// Conflicts decided one by one, used while the policy is `ask`.
    var resolutions: [ImportRecordKey: ConflictPolicy] = [:]

    /// `preview` with these decisions applied.
    func applied(to preview: ImportPreview) -> ImportPreview {
        var preview = preview
        for index in preview.newAccounts.indices {
            guard let edit = accounts[preview.newAccounts[index].account.id] else { continue }
            var account = preview.newAccounts[index].account
            if let name = edit.name { account.name = name }
            if let kind = edit.kind { account.kind = kind }
            if let currency = edit.currency { account.currency = currency }
            preview.newAccounts[index].account = account
            if let accepted = edit.isAccepted { preview.newAccounts[index].isAccepted = accepted }
        }
        for index in preview.newInstruments.indices {
            guard let edit = instruments[preview.newInstruments[index].instrument.id] else { continue }
            var instrument = preview.newInstruments[index].instrument
            if let name = edit.name { instrument.name = name }
            if let kind = edit.kind, kind != instrument.kind { instrument = instrument.changingKind(to: kind) }
            if let currency = edit.currency { instrument.currency = currency }
            preview.newInstruments[index].instrument = instrument
            if let accepted = edit.isAccepted { preview.newInstruments[index].isAccepted = accepted }
        }
        for index in preview.accountChanges.indices {
            if let accepted = accountChanges[AccountChangeKey(preview.accountChanges[index])] {
                preview.accountChanges[index].isAccepted = accepted
            }
        }
        let policy = conflictPolicy ?? preview.conflictPolicy
        for index in preview.records.indices where preview.records[index].status == .conflict {
            preview.records[index].resolution = policy == .ask
                ? resolutions[preview.records[index].id] ?? .ask
                : policy
        }
        return preview
    }
}

/// Changes to a proposed account or instrument. Fields left `nil` keep the
/// proposal's.
struct ProposalEdit<Kind: Hashable & Sendable>: Hashable, Sendable {
    var name: String?
    var kind: Kind?
    var currency: CurrencyCode?
    var isAccepted: Bool?
}

/// A proposed account change by account and kind of change (its date can
/// move when the mapping changes).
struct AccountChangeKey: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case close, openEarlier, recordTrades
    }

    var account: AccountID
    var kind: Kind

    init(_ proposal: AccountChangeProposal) {
        account = proposal.account
        kind = switch proposal.change {
        case .close: .close
        case .openEarlier: .openEarlier
        case .recordTrades: .recordTrades
        }
    }
}

private extension Instrument {
    /// The instrument with another kind, and the asset class and unit that
    /// usually go with it (``InstrumentKind/usualAssetClass(name:)``: a metal
    /// is gold, weighed in grams, unless its name says another metal). A
    /// crypto instrument keeps its unit.
    func changingKind(to kind: InstrumentKind) -> Instrument {
        var instrument = self
        instrument.kind = kind
        instrument.assetClasses = .single(kind.usualAssetClass(name: name))
        if let unit = kind.usualUnit { instrument.unit = unit }
        return instrument
    }
}
