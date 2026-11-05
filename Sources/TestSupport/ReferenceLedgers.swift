import Foundation
import Model

/// The reference ledgers (docs/PROGRESS.md, "Reference ledgers"): small
/// made-up libraries in `Resources/ReferenceLedgers/`, one folder each,
/// each with an `expected.md` next to its files that tells its events in
/// plain words and works out every number a person would check by hand.
/// The tests assert exactly those numbers. Each folder is a library the app
/// can open and the CLI can read (`retire --library <folder> …`).
public enum ReferenceLedger: String, CaseIterable, Sendable {
    /// C1: one month of five accounts: pay, a refund, debit spending, a
    /// card's purchases and bill, a deposit to the broker, a mortgage
    /// payment and an employer's pension contribution.
    case fiveAccounts = "c1-five-accounts"

    /// The folder that holds every reference ledger.
    public static var foldersURL: URL {
        guard let url = Bundle.module.url(forResource: "ReferenceLedgers", withExtension: nil) else {
            preconditionFailure("TestSupport's ReferenceLedgers resource is missing")
        }
        return url
    }

    /// The ledger's library folder.
    public var url: URL {
        Self.foldersURL.appendingPathComponent(rawValue)
    }

    /// The paths of every JSON file in the ledger, relative to its folder
    /// and sorted.
    public var allJSONFiles: [String] {
        Fixtures.jsonFiles(in: url)
    }

    /// The contents of a file in the ledger, e.g. `data(for: "library.json")`.
    public func data(for relativePath: String) throws -> Data {
        try Data(contentsOf: url.appendingPathComponent(relativePath))
    }

    /// The ledger as a `Library`, read naively with `JSONDecoder`, as
    /// ``Fixtures/exampleLibrary()`` reads the example library.
    public func library() throws -> Library {
        try Fixtures.library(at: url)
    }
}
