import Foundation
import Model
import Testing
import TestSupport
import Tracker

/// What holds for every reference ledger (docs/PROGRESS.md, "Reference
/// ledgers"), so the numbers its expected.md works out stand on records a
/// statement's import would write: nothing to point out, every account's
/// lines lead to its balances and give its money in and out, and the trades
/// apply cleanly.
@Suite struct ReferenceLedgerTests {
    @Test(arguments: ReferenceLedger.allCases)
    func hasNothingToPointOut(_ ledger: ReferenceLedger) throws {
        let library = try ledger.library()
        #expect(library.problems().isEmpty, "\(library.problems())")
    }

    /// Each value's money in and out are its lines' sums, as an import
    /// counts them, and the lines lead to its balance.
    @Test(arguments: ReferenceLedger.allCases)
    func linesGiveEveryValue(_ ledger: ReferenceLedger) throws {
        let library = try ledger.library()
        for account in library.accounts.keys.sorted() {
            for stretch in library.lineStretches(of: account) where stretch.through != nil {
                #expect(stretch.addsUp, "\(account) through \(String(describing: stretch.through))")
            }
            var recounted = library
            recounted.countLines(of: account)
            #expect(recounted.months == library.months, "\(account)'s money in and out aren't its lines'")
        }
    }

    @Test(arguments: ReferenceLedger.allCases)
    func tradesApplyCleanly(_ ledger: ReferenceLedger) throws {
        let valuator = Valuator(library: try ledger.library())
        #expect(valuator.tradeIssues().isEmpty, "\(valuator.tradeIssues())")
        for account in valuator.accounts.keys.sorted() {
            #expect(valuator.reconciliation(of: account).isEmpty)
        }
    }
}
