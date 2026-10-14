import Foundation
import Model

/// Remembering how a batch's files are read (docs/IMPORT.md, "Remembering
/// banks and senders"): the profiles to save with the import, so the next
/// statement of each bank is read the same way, with its account and the
/// rules of every file.
extension StatementBatch {
    /// A profile to save with the import, and the files it reads.
    public struct RememberedProfile: Hashable, Sendable {
        /// The profile, made from the first of ``files``.
        public var profile: ImportProfile
        /// The files it reads, by ``StatementBatch/File/id``, in the batch's order.
        public var files: [Int]
        /// Whether the library has no profile with its ID yet.
        public var isNew: Bool

        public init(profile: ImportProfile, files: [Int], isNew: Bool) {
            self.profile = profile
            self.files = files
            self.isNew = isNew
        }
    }

    /// The profiles that remember how the files with an account are read,
    /// made with ``ImportSession/makeProfile(id:name:library:)``. Pass the
    /// library the import is applied to; the profiles it has are compared
    /// with it.
    ///
    /// - A file read with a saved profile updates that profile, under its ID
    ///   and name. When several files are read with it, the one of the
    ///   profile's own account does (else the first), and so do the others
    ///   of that account.
    /// - Every other file gets a new profile, one per account, named after
    ///   the account's bank and the account ("Fineco, Conto corrente"), or
    ///   after the file without its extension when its bank isn't known.
    /// - Every profile gets the rules of every file: its own first, then the
    ///   others' for words it has no rule for. A rule that moves money to or
    ///   from the profile's own account is left out of it.
    /// - Every profile remembers the classes chosen for single lines of its
    ///   files (``ImportProfile/answers``), with those a saved profile had.
    public func rememberedProfiles(in library: Library, today: CalendarDate = .today()) -> [RememberedProfile] {
        let read = files.filter { $0.account != nil }
        // Which file updates each saved profile.
        var owners: [ImportProfileID: File] = [:]
        for file in read {
            let id = file.session.profile.id
            guard let saved = library.importProfiles[id], saved.layout == .statement else { continue }
            if let owner = owners[id] {
                if owner.account != saved.constants.account, file.account == saved.constants.account {
                    owners[id] = file
                }
            } else {
                owners[id] = file
            }
        }
        var remembered: [RememberedProfile] = []
        var taken = Set(library.importProfiles.keys)
        for file in read {
            let id = file.session.profile.id
            if let owner = owners[id], owner.account == file.account,
               let index = remembered.firstIndex(where: { $0.profile.id == id }) {
                remembered[index].files.append(file.id)
                continue
            }
            if let owner = owners[id], owner.id == file.id, let saved = library.importProfiles[id] {
                let profile = file.session.makeProfile(id: id, name: saved.name, library: library)
                remembered.append(RememberedProfile(profile: profile, files: [file.id], isNew: false))
                continue
            }
            if let index = remembered.firstIndex(where: { $0.isNew && $0.profile.constants.account == file.account }) {
                remembered[index].files.append(file.id)
                continue
            }
            let name = Self.profileName(for: file, library: library)
            let newID = ImportProfileID.make(from: name, existing: taken)
            taken.insert(newID)
            let profile = file.session.makeProfile(id: newID, name: name, library: library)
            remembered.append(RememberedProfile(profile: profile, files: [file.id], isNew: true))
        }
        let rules = read.flatMap(\.session.profile.rules)
        for index in remembered.indices {
            remembered[index].profile.rules = Self.rules(rules, addedTo: remembered[index].profile)
            if remembered[index].isNew { remembered[index].profile.answers = [] }
            for id in remembered[index].files {
                guard let file = files.first(where: { $0.id == id }) else { continue }
                remembered[index].profile.answers = Self.answers(of: file, addedTo: remembered[index].profile,
                                                                 library: library, today: today)
            }
        }
        return remembered
    }

    /// `profile`'s answers with the classes chosen for single lines of
    /// `file` added.
    static func answers(of file: File, addedTo profile: ImportProfile, library: Library,
                        today: CalendarDate) -> [StatementAnswer] {
        guard !file.session.statementLineClasses.isEmpty else { return profile.answers }
        var session = file.session
        session.profile.answers = profile.answers
        return session.statementAnswers(adding: file.session.preview(against: library, today: today).statementLines)
    }

    /// A new profile's name: the account's bank and its name, "Fineco,
    /// Conto corrente", or the file's name without its extension.
    static func profileName(for file: File, library: Library) -> String {
        let account = file.account.flatMap { library.accounts[$0] }
        if let account, let bank = account.institution.map(TextTools.trim), !bank.isEmpty {
            return "\(bank), \(account.name)"
        }
        let name = (file.name as NSString).deletingPathExtension
        if !TextTools.trim(name).isEmpty { return name }
        return account?.name ?? "Statement"
    }

    /// `profile`'s rules, then those of `rules` for words it has no rule
    /// for yet, leaving out moves to or from its own account.
    static func rules(_ rules: [StatementRule], addedTo profile: ImportProfile) -> [StatementRule] {
        var result = profile.rules
        var words = Set(result.map { TextTools.words($0.match) })
        for rule in rules {
            let ruleWords = TextTools.words(rule.match)
            guard !ruleWords.isEmpty, !words.contains(ruleWords) else { continue }
            if let account = rule.account, account == profile.constants.account { continue }
            words.insert(ruleWords)
            result.append(rule)
        }
        return result
    }
}
