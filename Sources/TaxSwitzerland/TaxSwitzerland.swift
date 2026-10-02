import Foundation
import TaxKit

/// The Swiss tax system's IDs and bundled parameters. The system itself is
/// ``SwissTaxSystem``; docs/tax/CH.md describes it.
public enum TaxSwitzerland {
    /// The system's ID, as plans' residence timelines name it.
    public static let systemID = "ch"
    /// The currency the system computes in and its parameter files are
    /// written in: its `TaxSystem.currency`.
    public static let currency = "CHF"
    /// The country whose law it is: its `TaxSystem.country`, which the
    /// planner matches against a pension's `sourceCountry`.
    public static let country = "CH"

    /// The bundled yearly parameter files, `Resources/ch/<year>.json`.
    static func bundledParameters() throws -> JSONParameterStore {
        guard let root = Bundle.module.resourceURL else { throw ParameterError.noParameters(system: systemID) }
        // `.process` flattens Resources/ch into the bundle's root; `.copy` would keep the folder.
        let folder = root.appendingPathComponent(systemID)
        let directory = FileManager.default.fileExists(atPath: folder.path) ? folder : root
        return try JSONParameterStore(system: systemID, directory: directory)
    }
}

/// The IDs of the Swiss regimes and overlays.
public enum SwissRegime {
    /// Employees (the default for employee work).
    public static let employee = "ch.employee"
    /// The self-employed (the default for self-employed work).
    public static let selfEmployed = "ch.selfEmployed"
    /// Deductions for expatriates on a temporary assignment (ExpaV).
    public static let expatriate = "ch.expatriate"
    /// Taxation on expenditure (lump-sum taxation), where the canton allows it.
    public static let lumpSum = "ch.lumpSum"
}

/// The IDs of the Swiss wrappers.
public enum SwissWrapper {
    /// Current and savings accounts, brokerage, crypto, gold, 3b savings.
    public static let ordinary = "ch.ordinary"
    /// Pillar 3a accounts.
    public static let pillar3a = "ch.pillar3a"
    /// Vested-benefits accounts (Freizügigkeitskonto).
    public static let vestedBenefits = "ch.vestedBenefits"
    /// A pension-fund balance tracked as an account: the `ch.bvg` scheme's
    /// seed wrapper, and a wrapper of its own when the plan has no `ch.bvg`
    /// pension.
    public static let bvg = "ch.bvg"
}

/// The IDs of the Swiss tax and contribution lines.
public enum SwissLine {
    public static let federal = "ch.federal"
    public static let cantonal = "ch.cantonal"
    public static let communal = "ch.communal"
    public static let church = "ch.church"
    public static let personalTax = "ch.personalTax"
    public static let capitalBenefitsFederal = "ch.capitalBenefits.federal"
    public static let capitalBenefitsCantonal = "ch.capitalBenefits.cantonal"
    public static let capitalBenefitsCommunal = "ch.capitalBenefits.communal"
    public static let capitalBenefitsChurch = "ch.capitalBenefits.church"
    public static let wealthCantonal = "ch.wealth.cantonal"
    public static let wealthCommunal = "ch.wealth.communal"
    public static let wealthChurch = "ch.wealth.church"
    /// Ticino's wealth-tax brake (art. 49a LT), negative.
    public static let wealthBrake = "ch.wealth.brake"
    /// A credit for the tax another country charged on a pension Switzerland
    /// taxes under the treaty although the plan says that country does; negative.
    public static let foreignTaxCredit = "ch.foreignTaxCredit"
    /// The source tax on Swiss pensions paid to someone living abroad:
    /// federal, and cantonal and communal together.
    public static let nonResidentFederal = "ch.nonResident.federal"
    public static let nonResidentCantonal = "ch.nonResident.cantonal"

    // Contributions.
    public static let ahvEmployee = "ch.ahv.employee"
    public static let alv = "ch.alv"
    public static let bvgEmployee = "ch.bvg.employee"
    public static let insuranceEmployee = "ch.insurance.employee"
    public static let ahvSelfEmployed = "ch.ahv.selfEmployed"
    public static let bvgSelfEmployed = "ch.bvg.selfEmployed"
    public static let ahvNonEmployed = "ch.ahv.nonEmployed"
}
