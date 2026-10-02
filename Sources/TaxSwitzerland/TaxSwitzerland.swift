import Foundation
import TaxKit

/// The Swiss tax system (`ch`), designed in docs/tax/CH.md: federal, cantonal and communal income and wealth tax, AHV, the BVG pension fund, pillar 3a, vested benefits and the capital withdrawal tax, computed in CHF.
///
/// Not built yet. This namespace holds the module's place, with its bundled
/// parameter folder (`Resources/ch`) and its test target with reference
/// cases (`Tests/TaxSwitzerlandTests/cases`), so the system can be added without
/// changing Package.swift. It isn't registered in the app's or the CLI's
/// `TaxRegistry` (the CLI already depends on the module).
public enum TaxSwitzerland {
    /// The system's ID, as plans' residence timelines name it.
    public static let systemID = "ch"
    /// The currency the system computes in and its parameter files are
    /// written in: its `TaxSystem.currency`.
    public static let currency = "CHF"

    /// The bundled yearly parameter files, `Resources/ch/<year>.json` (none yet).
    static func bundledParameters() throws -> JSONParameterStore {
        guard let root = Bundle.module.resourceURL else { throw ParameterError.noParameters(system: systemID) }
        // `.process` flattens Resources/ch into the bundle's root; `.copy` would keep the folder.
        let folder = root.appendingPathComponent(systemID)
        let directory = FileManager.default.fileExists(atPath: folder.path) ? folder : root
        return try JSONParameterStore(system: systemID, directory: directory)
    }
}
