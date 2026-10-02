import Foundation
import TaxKit
@testable import TaxGermany
import Testing

/// The module is in place: its ID, its bundled parameter folder and its
/// reference-case folder. The system's own tests come with the system.
struct TaxGermanyModuleTests {
    @Test func theModuleIsInPlace() throws {
        #expect(TaxGermany.systemID == "de" && TaxGermany.currency == "EUR")
        let store = try TaxGermany.bundledParameters()
        #expect(store.system == "de")
        let cases = try #require(Bundle.module.resourceURL?.appendingPathComponent("cases"))
        #expect(FileManager.default.fileExists(atPath: cases.appendingPathComponent("README.md").path))
    }
}
