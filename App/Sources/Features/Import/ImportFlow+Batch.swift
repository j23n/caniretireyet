import Foundation
import Importer
import Model

/// Several bank statements opened at once (IMPORT.md, "Several statements
/// at once"; UI.md, "Import"): what the File step lists for each file, the
/// file picker of Income and Preview, and what stops the import.
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

    /// What's in the file: "204 lines · Jan – Dec 2025 · balance column".
    func batchFileDetail(_ file: StatementBatch.File) -> String {
        var parts: [String] = []
        if let preview = batchPreview(of: file) {
            parts.append(Wording.count(preview.statementLines.count, "line"))
            if let period = preview.statementPeriod {
                parts.append("\(AmountFormat.mediumDate(period.from)) – \(AmountFormat.mediumDate(period.through))")
            }
        } else {
            parts.append(Wording.count(file.session.table.rows.count, "row"))
        }
        let hasBalance = file.session.profile.columns.contains { $0.field == .balance }
        parts.append(hasBalance ? "balance column" : "no balance column")
        return parts.joined(separator: " · ")
    }

    /// How the file's account was found, e.g. "Follows on from its value
    /// of 31 Dec 2025"; `nil` while it has none.
    func batchAccountSourceText(_ file: StatementBatch.File) -> String? {
        switch file.accountSource {
        case .profile?: "Remembered from its saved profile"
        case .balance(let date)?: "Its balance follows on from the value of \(AmountFormat.mediumDate(date))"
        case .named?: "Named in the file"
        case .chosen?: "Chosen"
        case nil: nil
        }
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

    /// The File step's sentences under the files: the transfers paired,
    /// and the gaps and overlaps between an account's files.
    var batchNotes: [StatementNote] {
        var notes: [StatementNote] = []
        let paired = batchPairedTransfers
        if paired > 0 {
            notes.append(StatementNote(text: "\(Wording.count(paired, "transfer")) between these accounts found "
                + "in both files and paired: neither spent nor came in.", isProblem: false))
        }
        let gaps = batchGaps
        for gap in gaps {
            let before = batch?.files.first { $0.id == gap.before }?.name ?? ""
            let after = batch?.files.first { $0.id == gap.after }?.name ?? ""
            let days = "\(AmountFormat.mediumDate(gap.from)) – \(AmountFormat.mediumDate(gap.through))"
            let text = gap.isOverlap
                ? "\(before) and \(after) both cover \(days) of \(accountName(gap.account)): leave one out, or "
                    + "its lines count twice."
                : "No file covers \(days) of \(accountName(gap.account)), between \(before) and \(after): the "
                    + "next value's money in and out leave those days out."
            notes.append(StatementNote(text: text, isProblem: true))
        }
        if gaps.isEmpty, batchPreviews.count > 1, batchFileWithoutAccount == nil {
            notes.append(StatementNote(text: "No gaps or overlaps between an account's files.", isProblem: false))
        }
        return notes
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

    /// "Imported 13 months for 2 accounts", for Done.
    static func batchSummary(_ result: ImportResult, accounts: Int) -> String {
        "Imported \(Wording.count(result.changedMonths.count, "month")) for \(Wording.count(accounts, "account"))"
    }
}
