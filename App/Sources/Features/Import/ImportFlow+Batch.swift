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
        let order = previews.map(\.file)
        return batch.files.sorted { lhs, rhs in
            (order.firstIndex(of: lhs.id) ?? order.count, lhs.id) < (order.firstIndex(of: rhs.id) ?? order.count, rhs.id)
        }
    }

    /// The file's preview in the batch; `nil` while it has no account.
    func batchPreview(of file: StatementBatch.File) -> ImportPreview? {
        previews.first { $0.file == file.id }?.preview
    }

    /// "fineco-2025.csv · Conto Fineco", for the file picker.
    func batchFileTitle(_ file: StatementBatch.File) -> String {
        file.name + " · " + (file.account.map(accountName) ?? "No account yet")
    }

    /// How many lines of the files are transfers paired with a line of
    /// another file, counted once per pair.
    var batchPairedTransfers: Int {
        let lines = previews.flatMap(\.preview.statementLines)
        return lines.filter { if case .paired = $0.source { $0.amount < 0 } else { false } }.count
    }

    /// Days one account's files leave out or cover twice.
    var batchGaps: [StatementGap] {
        guard let batch else { return [] }
        return StatementBatch.gaps(in: previews, batch: batch)
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
}

// MARK: - Before the first check-in

/// The statements' days before the library's first check-in (UI.md,
/// "Add past statements"): where their values go, at every month end,
/// every quarter end or none (Importer's `StatementCheckIns`).
struct ImportFirstCheckIn: Hashable, Sendable {
    /// The first day a file covers.
    var from: CalendarDate
    /// The library's first check-in; `nil` when it has none.
    var firstCheckIn: CalendarDate?
    /// The month ends that get a value.
    var ends: StatementCheckIns.Ends
    /// The dates of the values the files add before the first check-in.
    var values: [CalendarDate]

    /// "8 check-ins added, one at each quarter end. …"
    var note: String {
        let count = Wording.count(values.count, "check-in")
        switch ends {
        case .months:
            return "\(count) added, one at each month end, with balances from the files. Most detail, most to "
                + "check."
        case .quarters:
            return "\(count) added, one at each quarter end. A difference shows within 3 months, with a third of "
                + "the checking."
        case .never:
            return "No check-ins are added: the lines count as one long stretch. A difference is only known for the "
                + "whole stretch."
        }
    }
}

extension ImportFlow {
    /// The files' days before the library's first check-in, and where
    /// their values go; `nil` when no file has any.
    var firstCheckIn: ImportFirstCheckIn? {
        guard let batch else { return nil }
        let first = library.checkInDates.first
        let starts = previews.compactMap(\.preview.statementPeriod?.from)
        guard let from = starts.min(), first.map({ from < $0 }) ?? true else { return nil }
        var values: Set<CalendarDate> = []
        for entry in previews {
            for record in entry.preview.records {
                if case .valuation(let key) = record.imported.key, first.map({ key.date < $0 }) ?? true {
                    values.insert(key.date)
                }
            }
        }
        return ImportFirstCheckIn(from: from, firstCheckIn: first, ends: batch.checkIns?.ends ?? .months,
                                  values: values.sorted())
    }
}
