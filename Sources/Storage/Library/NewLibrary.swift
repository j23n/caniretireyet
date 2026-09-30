import Foundation
import Model

extension LibraryFolder {
    /// `README.md`, written by the app into every library folder.
    public static let readmePath = "README.md"

    /// The folders a new library starts with. The others (`imports/`,
    /// `projections/`, `backups/`) appear when they're first needed.
    public static let initialFolders = ["accounts", "instruments", "history", "plans"]

    /// Creates a new, empty library in the folder: `library.json` with
    /// `settings`, the README, and the empty folders. The folder itself is
    /// created if needed. Throws ``StorageError/libraryAlreadyExists(path:)``
    /// if it already holds a `library.json`.
    public func createLibrary(settings: LibrarySettings = LibrarySettings()) throws {
        guard !containsLibrary else { throw StorageError.libraryAlreadyExists(path: root.path) }
        try checkWritable(schemaVersion: settings.schemaVersion)
        try files.createDirectory(at: root)
        for folder in Self.initialFolders {
            try files.createDirectory(at: url(for: folder))
        }
        try files.writeData(Data(Self.readme.utf8), to: url(for: Self.readmePath))
        try files.writeData(CanonicalJSON.data(encoding: settings), to: url(for: LibraryFile.settings))
    }

    /// Writes the README if it's missing or differs from this app version's.
    /// Returns whether it was written.
    @discardableResult
    public func updateReadme() throws -> Bool {
        let data = Data(Self.readme.utf8)
        let url = url(for: Self.readmePath)
        if files.fileExists(at: url), (try? files.readData(at: url)) == data { return false }
        try files.writeData(data, to: url)
        return true
    }

    /// The text of `README.md`: what the folder is and how its files are
    /// organised, for someone who opens it in Files, Finder or a text editor.
    public static let readme = """
        # Can I Retire Yet? library

        This folder holds everything the app "Can I Retire Yet?" knows about your \
        money: your accounts, what they were worth at each check-in, the prices \
        and exchange rates used, and your retirement plans. The apps on your iPhone \
        and your Mac both read and write this folder through iCloud Drive.

        The files are plain text (JSON), so the data outlives the app. You can read \
        them, back them up, keep them in git, or edit them by hand. If you delete \
        the app and keep this folder, nothing is lost.

        ## What's where

        | File or folder | What it holds |
        | --- | --- |
        | `library.json` | Settings: base currency, who the library belongs to, the main plan, and the format version. |
        | `accounts/` | One file per account, open or closed. The file name is the account's ID. |
        | `instruments/` | One file per thing you hold a quantity of (ETFs, crypto, gold), with where its prices come from. |
        | `history/YYYY/YYYY-MM.json` | One file per month: what each account was worth, and the prices, exchange rates and inflation figures used, all dated in that month. |
        | `plans/` | One file per retirement scenario. |
        | `projections/<plan>/` | Saved projections (`baselines/`) and the answer recorded at each check-in (`headlines/`). They record what you expected at the time, so they're never recalculated. |
        | `imports/` | Saved import settings for spreadsheets and CSV files. |
        | `backups/` | Copies taken before an upgrade or an import, and of files the app had to replace because they were changed elsewhere or couldn't be read. "Undo import" uses them. Safe to delete. |

        ## Editing by hand

        - IDs are lowercase words joined by hyphens (`conto-fineco`), and each file's \
        name is its ID. Other files refer to accounts, instruments and plans by ID, \
        so don't rename files; change the `name` inside instead.
        - Dates are written `YYYY-MM-DD`. A record goes in the month file of its date.
        - Amounts are written as text, like `"1234.56"`, so they're exact; negative \
        for debts. Plain numbers work too. `"0.26"` means 26%.
        - The app keeps fields it doesn't know about, so you can add your own notes \
        (for example `"myNote": "..."`) and they'll survive the app's edits.
        - If a file has a mistake, the app tells you which file and where, and loads \
        everything else.
        - The app writes the files in a fixed layout (sorted keys, one record per \
        line), so if you keep the folder in git, a change shows up as a clean diff.

        ## Format version

        `schemaVersion` in `library.json` is the format version. When a new version \
        of the app changes the format, it upgrades the library after copying it to \
        `backups/`. An older version of the app opens a newer library read-only, so \
        it can't damage it.

        """
}
