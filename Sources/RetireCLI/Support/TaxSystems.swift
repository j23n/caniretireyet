import Model
import Planner
import TaxGeneric
import TaxItaly
import TaxKit

/// The tax systems the CLI knows, registered in one place (TAXES.md). The
/// CLI already depends on `TaxSwitzerland` and `TaxGermany`, so registering
/// them is an import and an entry in ``registry()``; everything else reads
/// the registry.
enum TaxSystems {
    /// Italy (`it`) and the generic flat-rate system (`generic`).
    static func registry() -> TaxRegistry {
        TaxRegistry([ItalyTaxSystem(), GenericTaxSystem()])
    }

    /// The system for `settings`' tax residence, which a plan without a
    /// residence timeline uses and a new one starts in: the planner's own
    /// rule (`Planner.defaultTaxSystem`), the registered system whose
    /// country (`TaxSystem.country`) it is, else `generic`, else the first
    /// registered.
    static func residenceSystem(for settings: LibrarySettings, registry: TaxRegistry) -> (any TaxSystem)? {
        Planner.defaultTaxSystem(for: settings, registry: registry)
    }
}
