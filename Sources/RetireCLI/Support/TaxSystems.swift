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

    /// The system plans use for `settings`' tax residence when they don't
    /// set one, as the planner chooses it: the registered system whose ID
    /// is the country code in lower case (`it`, `ch`, `de`), else `generic`,
    /// else the first registered.
    static func defaultSystem(for settings: LibrarySettings, registry: TaxRegistry) -> (any TaxSystem)? {
        let candidates = [settings.taxResidence?.rawValue.lowercased(), TaxSystemID.generic.rawValue] + registry.ids
        return candidates.compactMap { $0 }.lazy.compactMap { registry.system($0) }.first
    }
}
