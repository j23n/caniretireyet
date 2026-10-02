import Model
import TaxKit

extension Planner {
    /// The tax system a plan without a residence timeline uses (PLANNER.md,
    /// "Plan file"): the registered system whose country
    /// (`TaxSystem.country`) is the library's tax residence, else `generic`,
    /// else the first registered. The app and the CLI start a new plan's
    /// timeline in it, and say which system applies, by this same rule.
    public static func defaultTaxSystem(for settings: LibrarySettings, registry: TaxRegistry) -> (any TaxSystem)? {
        settings.taxResidence.flatMap { registry.system(forCountry: $0.rawValue) }
            ?? registry.system(TaxSystemID.generic.rawValue) ?? registry.systems.first
    }
}
