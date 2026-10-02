import Foundation
import TaxKit

/// The German tax system's namespace: its ID, its currency and its bundled
/// parameter files. The system itself is ``GermanTaxSystem``.
public enum TaxGermany {
    /// The system's ID, as plans' residence timelines name it.
    public static let systemID = "de"
    /// The currency the system computes in and its parameter files are
    /// written in: its `TaxSystem.currency`.
    public static let currency = "EUR"

    /// The bundled yearly parameter files, `Resources/de/<year>.json`.
    static func bundledParameters() throws -> JSONParameterStore {
        guard let root = Bundle.module.resourceURL else { throw ParameterError.noParameters(system: systemID) }
        // `.process` flattens Resources/de into the bundle's root; `.copy` would keep the folder.
        let folder = root.appendingPathComponent(systemID)
        let directory = FileManager.default.fileExists(atPath: folder.path) ? folder : root
        return try JSONParameterStore(system: systemID, directory: directory)
    }

    /// The bundled files, read once.
    static let bundled: Result<JSONParameterStore, any Error> = Result { try bundledParameters() }
}

/// The IDs of the German earned-income regimes.
public enum GermanRegime {
    /// Employees (the default for employee work).
    public static let employee = "de.employee"
    /// Freiberufler: the professions of §18 EStG (the default for self-employed work). No trade tax.
    public static let freelancer = "de.freelancer"
    /// Gewerbetreibende: as a freelancer, plus trade tax, mostly credited against income tax.
    public static let trader = "de.trader"
}

/// The IDs of the German wrappers (an account's `tax.wrapper`).
public enum GermanWrapper {
    /// Current and savings accounts, brokerage, crypto, gold: taxed on income and gains.
    public static let ordinary = "de.ordinary"
    /// A Riester contract.
    public static let riester = "de.riester"
    /// A Basisrente (Rürup) contract.
    public static let ruerup = "de.ruerup"
    /// An occupational pension through a Direktversicherung, Pensionskasse or Pensionsfonds.
    public static let bav = "de.bav"
    /// The Altersvorsorgedepot, the state-subsidised pension depot from 2027.
    public static let altersvorsorgedepot = "de.altersvorsorgedepot"
}

/// The IDs of the German tax and contribution lines.
public enum GermanLine {
    /// Income tax on the §32a tariff, after the trade-tax credit.
    public static let incomeTax = "de.incomeTax"
    /// The solidarity surcharge on income tax.
    public static let soli = "de.soli"
    /// Church tax on income tax.
    public static let churchTax = "de.churchTax"
    /// Trade tax of a `de.trader` phase.
    public static let tradeTax = "de.tradeTax"
    /// The flat tax on investment income (Abgeltungsteuer).
    public static let capitalIncomeTax = "de.capitalIncomeTax"
    /// The solidarity surcharge on the flat tax.
    public static let capitalIncomeSoli = "de.capitalIncomeTax.soli"
    /// Church tax on the flat tax.
    public static let capitalIncomeChurchTax = "de.capitalIncomeTax.churchTax"
    /// Inheritance and gift tax.
    public static let inheritanceTax = "de.inheritanceTax"
    /// Pension insurance (Rentenversicherung): an employee's share, or a self-employed person's contribution.
    public static let pension = "de.rv"
    /// Unemployment insurance (Arbeitslosenversicherung).
    public static let unemployment = "de.av"
    /// Statutory health insurance (Krankenversicherung).
    public static let health = "de.kv"
    /// Long-term care insurance (Pflegeversicherung).
    public static let care = "de.pv"
    /// A private health insurance premium (PKV), less any employer's or the DRV's subsidy.
    public static let privateHealth = "de.pkv"
}
