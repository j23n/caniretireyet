import TaxGeneric
import TaxItaly
import TaxKit

/// The tax systems the CLI knows, registered in one place (TAXES.md).
enum TaxSystems {
    /// Italy (`it`) and the generic flat-rate system (`generic`).
    static func registry() -> TaxRegistry {
        TaxRegistry([ItalyTaxSystem(), GenericTaxSystem()])
    }
}
