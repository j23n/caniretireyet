import Model
import Planner
import TaxGeneric
import TaxGermany
import TaxItaly
import TaxKit
import TaxSwitzerland

/// The tax systems the CLI knows, registered in one place (TAXES.md). A new
/// system is an import and an entry in ``registry()``; everything else reads
/// the registry.
enum TaxSystems {
    /// Italy (`it`), Switzerland (`ch`), Germany (`de`) and the generic
    /// flat-rate system (`generic`).
    static func registry() -> TaxRegistry {
        TaxRegistry([ItalyTaxSystem(), SwissTaxSystem(), GermanTaxSystem(), GenericTaxSystem()])
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
