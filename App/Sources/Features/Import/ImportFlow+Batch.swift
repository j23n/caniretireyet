import Foundation
import Importer
import Model

/// Several bank statements opened at once (IMPORT.md, "Several statements
/// at once"; UI.md, "Import"): the files in the order they're imported,
/// the file picker of Income and Review, and what stops the import. The
/// Files step's rows are ``ImportFileRow``s (`ImportFlow+Files`).
extension ImportFlow {
    /// Whether several statements are open.
    var isBatch: Bool { batch != nil }

    /// "3 statements", or the one file's name.
    var displayName: String? {
        guard let batch else { return fileName }
        return Wording.count(batch.files.count, "statement")
    }

    /// The batch's files in the order they're imported (by account, then
    /// date), then those without an account.
    var batchFiles: [StatementBatch.File] {
        guard let batch else { return [] }
        let order = batchPreviews.map(\.file)
        return batch.files.sorted { lhs, rhs in
            (order.firstIndex(of: lhs.id) ?? order.count, lhs.id) < (order.firstIndex(of: rhs.id) ?? order.count, rhs.id)
        }
    }

    /// The file's preview in the batch; `nil` while it has no account.
    func batchPreview(of file: StatementBatch.File) -> ImportPreview? {
        batchPreviews.first { $0.file == file.id }?.preview
    }

    /// "fineco-2025.csv · Conto Fineco", for the file picker.
    func batchFileTitle(_ file: StatementBatch.File) -> String {
        file.name + " · " + (file.account.map(accountName) ?? "No account yet")
    }

    /// How many lines of the files are transfers paired with a line of
    /// another file, counted once per pair.
    var batchPairedTransfers: Int {
        let lines = batchPreviews.flatMap(\.preview.statementLines)
        return lines.filter { if case .paired = $0.source { $0.amount < 0 } else { false } }.count
    }

    /// Days one account's files leave out or cover twice.
    var batchGaps: [StatementGap] {
        guard let batch else { return [] }
        return StatementBatch.gaps(in: batchPreviews, batch: batch)
    }

    /// The File step's sentences under the files (``betweenFilesNotes(locale:)``).
    var batchNotes: [StatementNote] {
        betweenFilesNotes().map { StatementNote(text: $0.text, isProblem: $0.isProblem) }
    }

    /// What stops importing the batch, beyond the file on screen: days two
    /// files cover, and another file's guessed formats or missing balance.
    var batchBlockers: [String] {
        guard let batch else { return [] }
        var reasons: [String] = []
        if batchGaps.contains(where: \.isOverlap) {
            reasons.append("Two files cover the same days of an account: leave one out.")
        }
        for file in batch.files where file.id != batchFile {
            if !file.session.ambiguities.isEmpty {
                reasons.append("Confirm the formats the importer guessed for \(file.name).")
            }
            if batchPreview(of: file)?.issues.contains(where: \.asksForOpeningBalance) == true {
                reasons.append("Give the balance before the first line of \(file.name).")
            }
        }
        return reasons
    }

    /// "Imported 13 months for 2 accounts", for Done: the files' accounts
    /// whose values or account the import changed in `library`, not one
    /// whose file the library already had.
    static func batchSummary(_ result: ImportResult, of fileAccounts: [AccountID],
                             importedInto library: Library) -> String {
        let accounts = Set(fileAccounts).filter { account in
            result.changedAccounts.contains(account)
                || result.library.valuations(for: account) != library.valuations(for: account)
        }.count
        let months = Wording.count(result.changedMonths.count, "month")
        return "Imported \(months) for \(Wording.count(accounts, "account"))"
    }
}
