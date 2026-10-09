import Foundation
import Model

extension CheckInDraft {
    /// Brings the draft up to date with `library`: when an unfinished
    /// check-in is resumed, when the library changes while it's open (the
    /// other device saved a check-in, an account was added), and right
    /// before saving.
    ///
    /// - Each row's previous valuation, and the one saved on the date, are
    ///   read again. Rows are added for accounts not closed before the date
    ///   (open on it, or opening later) that have none, and dropped for
    ///   accounts deleted or closed before it; rows keep the draft's order
    ///   (by group, then name). A row whose account's opening date moved to
    ///   the other side of the date is filled in again, keeping what was
    ///   entered.
    /// - Rows with nothing entered (not reviewed yet, only pre-filled from
    ///   a valuation saved on the date, or a trades account's as its trades
    ///   say) are filled in again, and skipped rows stay skipped. Rows marked
    ///   unchanged restore the new previous values. What was entered is
    ///   kept, and default flows follow the new previous values.
    /// - A row with something entered whose account now has a different
    ///   valuation saved on the date than the row started from keeps its
    ///   values and records the saved one as its ``CheckInRow/conflict``. It
    ///   writes nothing until that's settled with
    ///   ``resolveConflict(of:keepingSaved:in:)``, so the saved valuation is
    ///   never overwritten without asking.
    ///
    /// Prices and FX rates are kept. Returns the accounts whose rows came
    /// into conflict with a valuation saved on the date, or whose conflict
    /// is now with a newer one, in row order.
    @discardableResult
    public mutating func rebase(onto library: Library) -> [AccountID] {
        var newConflicts: [AccountID] = []
        var valuator = LazyValuator(library: libraryWithRates(library))
        let accounts = Self.accounts(for: date, in: library)
        var rebased: [CheckInRow] = []
        for account in accounts {
            let valuations = library.valuations(for: account.id)
            let previous = valuations.last { $0.date < date }
            let saved = valuations.last { $0.date == date }
            guard let old = self[account.id] else {
                rebased.append(CheckInRow(account: account, date: date, previous: previous, existing: saved,
                                          valuator: &valuator))
                continue
            }
            // A trades account's starting point also moves when its trades change.
            let derived = account.recordsTrades
                ? valuator.valuator.derivedSnapshot(of: account, on: date, previous: previous) : nil
            let holdsCash = account.recordsTrades ? valuator.valuator.holdsCash(account.id) : true
            if old.previous == previous, (old.conflict ?? old.existing) == saved,
               old.opensLater == (account.opened > date), old.isTrades == account.recordsTrades, old.derived == derived,
               old.holdsCash == holdsCash {
                rebased.append(old)
                continue
            }
            let row = refreshed(old, account: account, previous: previous, saved: saved, valuator: &valuator)
            if let conflict = row.conflict, conflict != old.conflict { newConflicts.append(account.id) }
            rebased.append(row)
        }
        rows = rebased
        return newConflicts
    }

    /// Settles the conflict of `account`'s row (see ``CheckInRow/conflict``).
    /// `keepingSaved` fills the row in from the valuation saved on the date,
    /// as if the check-in had started from it, so saving leaves that
    /// valuation as it is. Otherwise the row keeps its values, and saving
    /// replaces the saved valuation with them.
    public mutating func resolveConflict(of account: AccountID, keepingSaved: Bool, in library: Library) {
        guard let index = rows.firstIndex(where: { $0.account == account }), let saved = rows[index].conflict
        else { return }
        guard keepingSaved else {
            rows[index].existing = saved
            rows[index].conflict = nil
            return
        }
        guard let details = library.accounts[account] else {
            // Without the account the row can't be filled in: writing nothing keeps the saved valuation.
            rows[index].skip()
            return
        }
        var valuator = LazyValuator(library: libraryWithRates(library))
        var row = CheckInRow(account: details, date: date, previous: rows[index].previous, existing: saved,
                             valuator: &valuator)
        if rows[index].hasTypedNote, row.note == nil { row.note = rows[index].note }
        rows[index] = row
    }

    // MARK: - Internals

    /// `old` filled in again from the account's `previous` valuation and the
    /// one `saved` on the date now.
    private func refreshed(_ old: CheckInRow, account: Account, previous: Valuation?, saved: Valuation?,
                           valuator: inout LazyValuator) -> CheckInRow {
        guard old.hasUserInput, old.state != .skipped else {
            // Nothing entered (or skipped, which writes nothing): start again from the library.
            var row = CheckInRow(account: account, date: date, previous: previous, existing: saved,
                                 valuator: &valuator)
            row.adoptEdits(from: old)
            return row
        }
        // What was entered goes on top of what the row started from, unless
        // the saved valuation is gone.
        let baseline = saved == nil || saved == old.existing ? saved : old.existing
        var row = CheckInRow(account: account, date: date, previous: previous, existing: baseline,
                             valuator: &valuator)
        row.adoptEdits(from: old)
        // A different valuation saved on the date is a conflict, unless it
        // records just what the row would write (e.g. this check-in's own
        // write, before a failed save was reloaded). The row keeps what it
        // started from either way.
        if let saved, saved != baseline {
            let written = proposal(for: row, using: valuator.valuator, ignoringConflict: true).written
            if !Self.recordsTheSame(written, saved) { row.conflict = saved }
        }
        return row
    }

    /// Whether `written` records what `saved` does, apart from where the
    /// values came from and the order of the positions.
    static func recordsTheSame(_ written: Valuation?, _ saved: Valuation) -> Bool {
        guard var written else { return false }
        var saved = saved
        written.source = nil
        saved.source = nil
        written.positions.sort { $0.instrument < $1.instrument }
        saved.positions.sort { $0.instrument < $1.instrument }
        return written == saved
    }
}
