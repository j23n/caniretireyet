import CloudSync
import Foundation
import Importer
import Model

/// Reads journal files the app was given access to: files chosen or
/// dropped, and folders granted for their includes. Each read uses the
/// security-scoped access of the grant that holds the file, and file
/// coordination, so a journal in iCloud Drive is downloaded first. An
/// include outside every grant can't be read in the sandbox, and the
/// journal lists it (`LedgerJournal.missingIncludes`).
struct SandboxLedgerFiles: LedgerFileProvider {
    let grants: [URL]

    func data(at url: URL) throws -> Data {
        try withAccess(to: url) { try CoordinatedFileAccess().readData(at: url) }
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try withAccess(to: url) { try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) }
    }

    func isDirectory(_ url: URL) -> Bool {
        (try? withAccess(to: url) {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }) ?? false
    }

    /// Runs `body` with the security-scoped access of the grant holding `url`.
    private func withAccess<Value>(to url: URL, _ body: () throws -> Value) throws -> Value {
        let path = url.standardizedFileURL.path
        let grant = grants.first { grant in
            let folder = grant.standardizedFileURL.path
            return path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
        }
        #if canImport(Darwin)
        let isScoped = grant?.startAccessingSecurityScopedResource() ?? false
        defer {
            if isScoped { grant?.stopAccessingSecurityScopedResource() }
        }
        #endif
        return try body()
    }
}

/// Starting a journal import, and reading it again once the app may read
/// its folder. Reading happens off the main thread.
extension ImportController {
    /// Reads journal files (and what they include) and starts importing
    /// them. A saved ledger profile that knows the journal's accounts is
    /// used right away; otherwise the importer proposes the mapping.
    func openLedger(_ files: [URL]) async {
        let journal = await Self.readJournal(files, grants: files)
        guard !journal.files.isEmpty else {
            openFailed(fileName: files.first?.lastPathComponent ?? "Journal",
                       message: journal.diagnostics.map(\.message).joined(separator: "\n"))
            return
        }
        let fits = LedgerProfileFit.rank(journal, profiles: Array(flow.library.importProfiles.values))
        let profile = fits.first(where: \.fits)?.profile
        open(ledger: LedgerImportState(roots: files, grants: files, journal: journal, profile: profile),
             source: profile.map { .profile($0.id) } ?? .proposed)
    }

    /// Reads the journal again, now that the app may read `folder`: for the
    /// included files it couldn't read before. The mapping is kept.
    func grantLedgerFolder(_ folder: URL) async {
        guard let ledger = flow.ledger else { return }
        let grants = ledger.grants + [folder]
        let journal = await Self.readJournal(ledger.roots, grants: grants)
        open(ledger: LedgerImportState(roots: ledger.roots, grants: grants, journal: journal,
                                       profile: ledger.session.profile),
             source: flow.source)
    }

    private static func readJournal(_ files: [URL], grants: [URL]) async -> LedgerJournal {
        await Task.detached(priority: .userInitiated) {
            LedgerReader.read(files, files: SandboxLedgerFiles(grants: grants))
        }.value
    }
}
