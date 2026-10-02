import Foundation
import TaxKit
@testable import TaxSwitzerland
import Testing

/// The module is in place: its ID, its bundled parameter folder and its
/// reference-case folder. The system's own tests come with the system.
struct TaxSwitzerlandModuleTests {
    @Test func theModuleIsInPlace() throws {
        #expect(TaxSwitzerland.systemID == "ch" && TaxSwitzerland.currency == "CHF")
        let store = try TaxSwitzerland.bundledParameters()
        #expect(store.system == "ch")
        let cases = try #require(Bundle.module.resourceURL?.appendingPathComponent("cases"))
        #expect(FileManager.default.fileExists(atPath: cases.appendingPathComponent("README.md").path))
    }
}
