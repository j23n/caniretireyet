import Foundation
import Model
import Storage

/// What upgrading the library's format did as the app opened it
/// (docs/schema/README.md, "Versioning"; Storage's `MigrationReport`).
/// ``LibraryStore/upgrade`` keeps it until it's dismissed: a banner on the
/// screens that show the library's state (`LibraryStatusBanners`) says so,
/// and its details (`LibraryUpgradeSheet`) list the steps and the notes.
/// An upgrade runs once, so it's shown once.
struct LibraryUpgrade: Hashable, Sendable, Identifiable {
    /// The format version before.
    var fromVersion: Int
    /// The format version now.
    var toVersion: Int
    /// What each step did, in plain words, in order.
    var steps: [String]
    /// What the steps had to estimate or point out, in plain words. They can
    /// name the person's accounts.
    var notes: [String]
    /// The copy of the library taken before, relative to the library
    /// folder: `backups/2026-10-11-v4`.
    var backupPath: String

    /// One upgrade per backup.
    var id: String { backupPath }

    init(fromVersion: Int, toVersion: Int, steps: [String], notes: [String] = [], backupPath: String) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.steps = steps
        self.notes = notes
        self.backupPath = backupPath
    }

    init(_ report: MigrationReport) {
        self.init(fromVersion: report.fromVersion, toVersion: report.toVersion, steps: report.steps,
                  notes: report.notes, backupPath: report.backup.path)
    }

    /// The banner's title.
    static let title = "Your library was upgraded"

    /// The banner's sentence: "This version of the app keeps your library in
    /// a newer format, so it upgraded it and kept a copy from before. 2
    /// notes say what to check."
    var message: String {
        let text = "This version of the app keeps your library in a newer format, so it upgraded it and kept a copy "
            + "from before."
        guard !notes.isEmpty else { return text }
        return text + " " + (notes.count == 1 ? "A note says" : "\(Wording.count(notes.count, "note")) say")
            + " what to check."
    }

    /// The details' footer under the backup: "A copy of the library from
    /// before is in backups/2026-10-11-v4, in the library's folder."
    var backupNote: String {
        "A copy of the library from before is in \(backupPath), in the library's folder."
    }
}

extension LibraryUpgrade {
    /// A made-up upgrade from format version 4, for previews (and so
    /// compiled in every configuration, as previews are).
    static let example = LibraryUpgrade(
        fromVersion: 4, toVersion: 5,
        steps: [
            "New money is stored only where it was typed: other values work it out from what's recorded. "
                + "Crypto is priced from Yahoo Finance, not CoinGecko.",
        ],
        notes: ["Old bank: the new money of 2 values wasn't the change in balance; it's now worked out from the "
            + "balances."],
        backupPath: "backups/2026-10-11-v4")
}
