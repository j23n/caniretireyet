import Foundation
import Importer
import Model

/// The bank statements a check-in holds (UI.md, "Statements first"): an
/// import that writes nothing on its own. The check-in reads its rows from
/// what importing would do (``checkInLibrary``), and saving the check-in
/// writes the statements with its own values.
extension ImportFlow {
    /// The library as it would be with the statements imported
    /// (``planned``); `nil` while no statement is open.
    var checkInLibrary: Library? {
        isBatch ? planned?.library : nil
    }

    /// The previews the check-in writes when it's saved, in order: one per
    /// file with an account.
    var checkInPreviews: [ImportPreview] {
        isBatch ? batchPreviews.map(\.preview) : []
    }

    /// The lines of the batch's file `id` that need an answer and have
    /// none, as Income counts them for the file on screen
    /// (``statementQuestions``).
    func unansweredLines(ofFile id: Int) -> Int {
        guard let file = batch?.files.first(where: { $0.id == id }), let preview = batchPreview(of: file) else {
            return 0
        }
        return preview.statementLines.count { $0.needsAnswer && file.session.statementAssets[$0.row] == nil }
    }

    /// How many of the file `id`'s lines are paired with a line of another
    /// file, by that file's account, most first.
    func pairedTransfers(ofFile id: Int) -> [(account: AccountID, count: Int)] {
        guard let file = batch?.files.first(where: { $0.id == id }) else { return [] }
        var counts: [AccountID: Int] = [:]
        for account in file.session.statementPairs.values { counts[account, default: 0] += 1 }
        return counts.map { (account: $0.key, count: $0.value) }
            .sorted { ($1.count, $0.account) < ($0.count, $1.account) }
    }

    /// What the statements move to or from the library's other accounts,
    /// from their side (``Importer/StatementBatch/accountMoves(in:)``).
    var checkInMoves: [StatementAccountMove] {
        batch?.accountMoves(in: batchPreviews) ?? []
    }

    /// The statements read again for a check-in on `date`, keeping each
    /// file's account, answers and how it's read, and the decisions made.
    /// Without statements, an empty import for that date.
    func movingCheckIn(to date: CalendarDate) -> ImportFlow {
        guard checkIn != date else { return self }
        var moved = ImportFlow(library: library, guided: prefersGuided, checkIn: date)
        guard let batch else { return moved }
        moved.open(statements: givenFiles)
        for file in batch.files where moved.batch?.files.contains(where: { $0.id == file.id }) == true {
            moved.showBatchFile(file.id)
            moved.editSession { session in
                session = file.session
                session.statementCheckIn = date
            }
        }
        let decisions = self.decisions
        moved.editDecisions { $0 = decisions }
        if let shown = batchFile { moved.showBatchFile(shown) }
        return moved
    }
}
