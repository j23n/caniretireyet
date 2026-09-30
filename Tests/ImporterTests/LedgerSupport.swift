import Foundation
@testable import Importer
import Model

/// The made-up journals in `Samples/ledger/`:
///
/// | File | What it covers |
/// | --- | --- |
/// | `ledger-cli.ledger` | comments of every kind, `comment` blocks, `D`, `Y`, `M/D` dates, secondary dates, codes, `alias`, `apply account`, `$` before amounts, `@`, `{lot}`, `[date]`, `(note)`, virtual postings, skipped `=`, `~`, `define` and `bucket`, a transaction that doesn't balance, `P` with a time |
/// | `hledger.journal` | `decimal-mark ,`, `commodity 1.000,00 EUR`, account types, tags, a balance assignment, `=` and `==` assertions that pass and one that fails, a quoted commodity, an inferred price |
/// | `split/` | `include` of a file and of `2024/*.journal`, an alias for the included files, a transaction dated out of file order |
/// | `cycle/` | two files including each other |
/// | `missing/` | includes of a file and a folder that aren't there |
/// | `years/` | two files given at once, both including `common.journal` |
/// | `personal/` | a year of made-up personal finances for the conversion tests |
enum LedgerSamples {
    static func url(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: "Samples/ledger/\(name)", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    static func read(_ names: String...) throws -> LedgerJournal {
        LedgerReader.read(try names.map(url), files: LocalLedgerFiles())
    }
}

extension LedgerJournal {
    /// The balance of an account (without subaccounts) in one commodity, at the end.
    func balance(_ account: String, _ commodity: String) -> Decimal {
        transactions.flatMap(\.postings).filter { $0.account == account && $0.amount.commodity == commodity }
            .reduce(0) { $0 + $1.amount.quantity }
    }

    /// The diagnostics' messages with their line, e.g. `12: …`.
    var messages: [String] {
        diagnostics.map { diagnostic in
            diagnostic.location.map { "\($0.line): \(diagnostic.message)" } ?? diagnostic.message
        }
    }
}
