import Model
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

    /// The system for `settings`' tax residence: the registered system
    /// whose country (`TaxSystem.country`) it is, else `generic`, else the
    /// first registered.
    static func residenceSystem(for settings: LibrarySettings, registry: TaxRegistry) -> (any TaxSystem)? {
        settings.taxResidence.flatMap { registry.system(forCountry: $0.rawValue) }
            ?? registry.system(TaxSystemID.generic.rawValue) ?? registry.systems.first
    }

    /// The system a plan without a residence timeline uses, as the planner
    /// chooses it: the system whose ID is the tax residence's country code
    /// in lower case, else `generic`, else the first registered.
    static func defaultSystem(for settings: LibrarySettings, registry: TaxRegistry) -> (any TaxSystem)? {
        let candidates = [settings.taxResidence?.rawValue.lowercased(), TaxSystemID.generic.rawValue] + registry.ids
        return candidates.compactMap { $0 }.lazy.compactMap { registry.system($0) }.first
    }
}
