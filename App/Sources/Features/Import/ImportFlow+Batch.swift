import Foundation
import Importer
import Model
import Tracker

/// Several bank statements opened at once (IMPORT.md, "Several statements
/// at once"; UI.md, "Import"): the files in the order they're imported,
/// the file picker of Review, and what stops the import. The
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
    /// Whether the files' lines add up at each of ``values``.
    var before: [ImportCheckInCheck] = []
    /// The library's check-ins the files' days reach, from the first on:
    /// they stay, and the files' lines fill them in.
    var after: [ImportCheckInCheck] = []
    /// The check-ins the files add from the first check-in on, on days
    /// without one: month ends, and a file's own last day.
    var added: [ImportCheckInCheck] = []

    /// "8 past check-ins: one at each quarter end, and at the end of each
    /// file. …"; each file's last month end gets one, so the next file
    /// follows on from it.
    var note: String {
        let count = Wording.count(values.count, "past check-in")
        switch ends {
        case .months:
            return "\(count), with balances from the files. Your history shows every month, and a missing line is "
                + "easy to find."
        case .quarters:
            return "\(count): one at each quarter end, and at the end of each file. A third of the checking, and a "
                + "missing line shows up within 3 months."
        case .never:
            return "\(count): one at the end of each file. The least checking, but a missing line can only be traced "
                + "to the whole file."
        }
    }

    /// "Feb 2026 – Sep 2026: your 8 check-ins stay as they are. The lines
    /// fill in what came in and went out between them."
    /// With one, "Jan 2026: your check-in stays as it is. …".
    func afterNote(locale: Locale = .current) -> String {
        let span = Self.span(after, locale: locale)
        guard after.count != 1 else {
            return span + "your check-in stays as it is. The lines fill in what came in and went out up to it."
        }
        return span + "your \(Wording.count(after.count, "check-in")) stay as they are. "
            + "The lines fill in what came in and went out between them."
    }

    /// "Mar 2026 – Jun 2026: 2 new check-ins, with balances from the files."
    func addedNote(locale: Locale = .current) -> String {
        "\(Self.span(added, locale: locale))\(Wording.count(added.count, "new check-in")), "
            + "with balances from the files."
    }

    /// "Feb 2026 – Sep 2026: ", or "Feb 2026: " when they're all in one
    /// month.
    private static func span(_ checks: [ImportCheckInCheck], locale: Locale) -> String {
        guard let first = checks.first?.title(locale: locale), let last = checks.last?.title(locale: locale) else {
            return ""
        }
        return first == last ? "\(first): " : "\(first) – \(last): "
    }
}

/// Whether the files' lines lead to their accounts' balances at one
/// check-in (Tracker's `AccountMonth`), as importing would leave them.
struct ImportCheckInCheck: Hashable, Sendable, Identifiable {
    var date: CalendarDate
    /// How many of the files' accounts' lines lead to it.
    var lines = 0
    /// The first of its accounts whose lines don't lead to its balance:
    /// the balance less what they lead to, in that account's currency.
    var off: Decimal?
    var currency: CurrencyCode?
    /// Whether none of its accounts has a balance before and on the date
    /// to check its lines against, such as an account's first value.
    var unchecked = false

    var id: CalendarDate { date }

    /// "Mar 2025".
    func title(locale: Locale = .current) -> String {
        date.dateValue.formatted(.dateTime.month(.abbreviated).year().locale(locale))
    }

    /// "412 lines · adds up", "58 lines · off by 12,40 €", "3 lines · no
    /// balance before to check", or "No lines".
    func status(locale: Locale = .current) -> AmountSentence {
        let count = Wording.count(lines, "line")
        guard let off else {
            if lines == 0 { return "No lines" }
            return unchecked ? "\(count) · no balance before to check" : "\(count) · adds up"
        }
        let amount = AmountFormat.amount(abs(off), currency: currency ?? .eur, precision: .cents, locale: locale)
        return "\(count) · off by \(amount: amount)"
    }

    /// "7 add up; Mar 2025 is off by 12,40 €.", "All 8 add up.", or `nil`
    /// for none; those without a balance before to check are left out.
    static func summary(_ all: [ImportCheckInCheck], locale: Locale = .current) -> AmountSentence? {
        let checks = all.filter { !$0.unchecked }
        guard !checks.isEmpty else { return nil }
        let offs = checks.filter { $0.off != nil }
        guard let first = offs.first, let off = first.off else {
            if checks.count == 1 { return "It adds up." }
            return "All \(checks.count) add up."
        }
        let amount = AmountFormat.amount(abs(off), currency: first.currency ?? .eur, precision: .cents,
                                         locale: locale)
        var sentence: AmountSentence = "\(checks.count - offs.count) of \(checks.count) add up; "
        sentence += "\(first.title(locale: locale)) is off by \(amount: amount)"
        if offs.count > 1 { sentence += " and \(offs.count - 1) more don't" }
        return sentence + "."
    }
}

extension ImportFlow {
    /// Whether the files' lines add up at each of `dates`, in the library
    /// as importing would leave it: of the accounts with a value on the
    /// date, whose lines lead to it.
    func checkInChecks(on dates: [CalendarDate]) -> [ImportCheckInCheck] {
        guard let batch, let after = planned?.library else { return [] }
        let accounts = Set(batch.files.compactMap(\.account)).sorted()
        return dates.map { date in
            var check = ImportCheckInCheck(date: date)
            var checked = false
            for account in accounts {
                guard let month = after.accountMonth(of: account, through: date), month.value != nil else { continue }
                check.lines += month.lines.count
                switch month.status {
                case .off(let difference):
                    checked = true
                    if check.off == nil {
                        check.off = difference
                        check.currency = after.accounts[account]?.currency
                    }
                case .toCheck, .checked: checked = true
                default: break
                }
            }
            check.unchecked = !checked
            return check
        }
    }

    /// The files' days before the library's first check-in, and where
    /// their values go; `nil` when no file has any.
    var firstCheckIn: ImportFirstCheckIn? {
        guard let batch else { return nil }
        let first = library.checkInDates.first
        let starts = previews.compactMap(\.preview.statementPeriod?.from)
        guard let from = starts.min(), first.map({ from < $0 }) ?? true else { return nil }
        let existing = Set(library.checkInDates)
        var values: Set<CalendarDate> = []
        var added: Set<CalendarDate> = []
        for entry in previews {
            for record in entry.preview.records {
                guard case .valuation(let key) = record.imported.key else { continue }
                if first.map({ key.date < $0 }) ?? true {
                    values.insert(key.date)
                } else if !existing.contains(key.date) {
                    added.insert(key.date)
                }
            }
        }
        var result = ImportFirstCheckIn(from: from, firstCheckIn: first, ends: batch.checkIns?.ends ?? .months,
                                        values: values.sorted())
        result.before = checkInChecks(on: result.values)
        if let first, let through = statementsPeriod?.through {
            result.after = checkInChecks(on: library.checkInDates.filter { $0 >= first && $0 <= through })
        }
        result.added = checkInChecks(on: added.sorted())
        return result
    }
}
