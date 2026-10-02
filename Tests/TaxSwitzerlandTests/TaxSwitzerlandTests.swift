import Foundation
import TaxKit
@testable import TaxSwitzerland
import Testing

/// The module's place: its ID and currency, its bundled parameter folder
/// and its reference-case folder.
struct TaxSwitzerlandModuleTests {
    @Test func theModuleIsInPlace() throws {
        #expect(TaxSwitzerland.systemID == "ch" && TaxSwitzerland.currency == "CHF")
        let store = try TaxSwitzerland.bundledParameters()
        #expect(store.system == "ch" && store.years == [2026])
        let cases = try #require(Bundle.module.resourceURL?.appendingPathComponent("cases"))
        #expect(FileManager.default.fileExists(atPath: cases.appendingPathComponent("README.md").path))
    }
}
