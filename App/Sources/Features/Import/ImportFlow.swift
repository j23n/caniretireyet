import Foundation
import Importer
import Model

/// A step of the import, shown along the top (UI.md, "Import"; IMPORT.md, "Steps").
/// A journal import has Commodities instead of Format and Columns.
enum ImportStep: Int, Hashable, Sendable, CaseIterable, Comparable, Identifiable {
    case file
    case format
    case columns
    case accounts
    case commodities
    case preview
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .file: "File"
        case .format: "Format"
        case .columns: "Columns"
        case .accounts: "Accounts"
        case .commodities: "Commodities"
        case .preview: "Preview"
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
    /// What the user decided about proposals and conflicts.
    private(set) var decisions = ImportDecisions()
    /// Why the file, or the last change to how it's read, didn't work.
    private(set) var problem: String?
    /// The saved profiles, the ones that fit the file best first.
    private(set) var profileFits: [ProfileFit] = []
    /// The step on screen.
    private(set) var step: ImportStep = .file
    /// iPhone's "Import with profile…": the file and a saved profile, then
    /// the preview. Otherwise every step (the Mac-first flow).
    private(set) var isGuided: Bool
    /// The journal import, when the files are ledger journals rather than a
    /// spreadsheet (ImportFlow+Ledger.swift); `session` is `nil` then.
    private(set) var ledger: LedgerImportState?

    init(library: Library = Library(), guided: Bool = false) {
        self.library = library
        isGuided = guided
    }

    // MARK: - The file

    /// Reads a file. A saved profile that fits it exactly is used right away;
    /// otherwise the importer proposes a mapping.
    mutating func open(_ data: Data, fileName: String) {
        self = ImportFlow(library: library, guided: isGuided)
        self.data = data
        self.fileName = fileName
        profileFits = ProfileFit.rank(data, profiles: Array(library.importProfiles.values))
        if let best = profileFits.first, best.fits {
            load(profile: best.profile)
        } else {
            load(profile: nil)
        }
    }

    /// Records that a file couldn't be opened at all (e.g. no permission).
    mutating func failToOpen(fileName: String, message: String) {
        self = ImportFlow(library: library, guided: isGuided)
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
        self = ImportFlow(library: library, guided: isGuided)
    }

    /// Whether a file (or a journal) has been read.
    var hasFile: Bool { session != nil || ledger != nil }

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

    /// The steps shown along the top.
    var steps: [ImportStep] {
        if isGuided { return [.file, .preview, .done] }
        if ledger != nil { return [.file, .accounts, .commodities, .preview, .done] }
        return [.file, .format, .columns, .accounts, .preview, .done]
    }

    /// Whether `step` can be shown now: every step but the first needs a
    /// file, Done comes only from importing, and nothing goes back from Done.
    func canShow(_ step: ImportStep) -> Bool {
        guard steps.contains(step) else { return false }
        switch step {
        case .done: return self.step == .done
        case .file: return self.step != .done
        case .preview where isGuided:
            // "Import with profile…" needs a profile; the full flow is the fallback.
            return hasFile && source != .proposed && self.step != .done
        default: return hasFile && self.step != .done
        }
    }

    /// Shows a step, if it can be shown.
    mutating func show(_ step: ImportStep) {
        if canShow(step) { self.step = step }
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
        if let nextStep { step = nextStep }
    }

    mutating func goBack() {
        if let previousStep { step = previousStep }
    }

    /// Switches between "Import with profile…" (iPhone) and every step.
    mutating func setGuided(_ guided: Bool) {
        isGuided = guided
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
        } catch {
            problem = Self.describe(error)
        }
        refreshPreview()
    }

    /// Changes the decisions and applies them to the preview (which isn't
    /// made again: decisions don't change what the file says).
    mutating func editDecisions(_ edit: (inout ImportDecisions) -> Void) {
        edit(&decisions)
        setPreview(basePreview)
    }

    /// Makes the preview again from the mapping and the library.
    mutating func refreshPreview() {
        if var ledger {
            ledger.refresh(against: library)
            self.ledger = ledger
            setPreview(ledger.result?.preview)
            return
        }
        setPreview(session?.preview(against: library))
    }

    // MARK: - Journals

    /// Starts over with journals read from files, and the mapping they're
    /// read with (a saved ledger profile, or proposed).
    mutating func openLedger(_ state: LedgerImportState, source: ImportSource) {
        self = ImportFlow(library: library, guided: isGuided)
        ledger = state
        fileName = state.fileName
        self.source = source
        refreshPreview()
    }

    /// Reads the journal with a saved ledger profile, or a mapping the
    /// importer proposes (`nil`). Decisions start over.
    mutating func useLedgerProfile(_ id: ImportProfileID?) {
        guard var ledger else { return }
        let profile = id.flatMap { library.importProfiles[$0] }
        ledger.session = LedgerImportSession(journal: ledger.journal, profile: profile)
        self.ledger = ledger
        source = profile.map { .profile($0.id) } ?? .proposed
        decisions = ImportDecisions()
        refreshPreview()
    }

    /// Changes the journal's mapping, then makes the preview again.
    mutating func editLedger(_ edit: (inout LedgerImportState) -> Void) {
        guard var ledger else { return }
        edit(&ledger)
        self.ledger = ledger
        refreshPreview()
    }

    private mutating func setPreview(_ base: ImportPreview?) {
        basePreview = base
        preview = base.map { decisions.applied(to: $0) }
        planned = preview?.applyFollowingFlows(to: library)
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
    var account: AccountID
    var closes: Bool

    init(_ proposal: AccountChangeProposal) {
        account = proposal.account
        if case .close = proposal.change { closes = true } else { closes = false }
    }
}

private extension Instrument {
    /// The instrument with another kind, and the asset class and unit that
    /// usually go with it (e.g. a metal is gold, weighed in grams).
    func changingKind(to kind: InstrumentKind) -> Instrument {
        var instrument = self
        instrument.kind = kind
        switch kind {
        case .etf, .fund, .stock: instrument.assetClasses = .single(.equity)
        case .bond: instrument.assetClasses = .single(.bonds)
        case .crypto: instrument.assetClasses = .single(.crypto)
        case .metal:
            instrument.assetClasses = .single(.gold)
            instrument.unit = .gram
        default: break
        }
        if kind != .metal, kind != .crypto, instrument.unit == .gram { instrument.unit = .share }
        return instrument
    }
}
