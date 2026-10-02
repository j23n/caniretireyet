import Foundation
import TaxKit

/// The German tax system (`de`), designed in docs/tax/DE.md: the income tax tariff with Soli and church tax, social contributions, the DRV pension, Riester, Rürup and bAV, and the flat tax on investments with the Teilfreistellung and the Vorabpauschale, computed in EUR.
///
/// Not built yet. This namespace holds the module's place, with its bundled
/// parameter folder (`Resources/de`) and its test target with reference
/// cases (`Tests/TaxGermanyTests/cases`), so the system can be added without
/// changing Package.swift. It isn't registered in the app's or the CLI's
/// `TaxRegistry` (the CLI already depends on the module).
public enum TaxGermany {
    /// The system's ID, as plans' residence timelines name it.
    public static let systemID = "de"
    /// The currency the system computes in and its parameter files are
    /// written in: its `TaxSystem.currency`.
    public static let currency = "EUR"

    /// The bundled yearly parameter files, `Resources/de/<year>.json` (none yet).
    static func bundledParameters() throws -> JSONParameterStore {
        guard let root = Bundle.module.resourceURL else { throw ParameterError.noParameters(system: systemID) }
        // `.process` flattens Resources/de into the bundle's root; `.copy` would keep the folder.
        let folder = root.appendingPathComponent(systemID)
        let directory = FileManager.default.fileExists(atPath: folder.path) ? folder : root
        return try JSONParameterStore(system: systemID, directory: directory)
    }
}
