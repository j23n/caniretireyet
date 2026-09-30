import Foundation
import Model
import TaxKit

/// What the plan editor offers, read from the tax registry (TAXES.md,
/// "Choosing them in a plan"): the systems for the residence timeline, the
/// regimes that fit a work phase, the overlays and the pension schemes. A
/// system or regime added to the registry shows up here with no UI code.
enum PlanTaxChoices {
    /// The system a plan without a residence uses, as the Planner chooses
    /// it: the library's tax residence if a system has that ID, else
    /// `generic`, else the first registered.
    static func defaultSystem(for settings: LibrarySettings, registry: TaxRegistry) -> (any TaxSystem)? {
        let candidates = [settings.taxResidence?.rawValue.lowercased(), TaxSystemID.generic.rawValue] + registry.ids
        return candidates.compactMap { $0 }.lazy.compactMap { registry.system($0) }.first
    }

    /// The systems in force between `from` and `through` (`nil`: to the end
    /// of the plan), in timeline order, without repeats.
    static func systems(for plan: PlanDocument, from: Int, through: Int?, settings: LibrarySettings,
                        registry: TaxRegistry) -> [any TaxSystem] {
        let residence = plan.tax.residence.sorted { $0.from < $1.from }
        guard !residence.isEmpty else { return defaultSystem(for: settings, registry: registry).map { [$0] } ?? [] }
        var ids: [String] = []
        for (index, entry) in residence.enumerated() {
            let next = index + 1 < residence.count ? residence[index + 1].from : Int.max
            // The entry covers [entry.from, next); the first entry also covers earlier years.
            let start = index == 0 ? Int.min : entry.from
            let overlaps = start <= (through ?? Int.max) && next > from
            if overlaps, !ids.contains(entry.system.rawValue) { ids.append(entry.system.rawValue) }
        }
        return ids.compactMap { registry.system($0) }
    }

    /// Every system, for the residence picker.
    static func allSystems(_ registry: TaxRegistry) -> [any TaxSystem] {
        registry.systems
    }

    /// The years a work phase covers: from its start to its end, or open.
    static func years(of phase: WorkPhase) -> (from: Int, through: Int?) {
        (phase.from.year, phase.until.date?.year)
    }

    /// The earned-income regimes a work phase can choose: those of the
    /// systems in force over its years, for its kind of work, available in
    /// its first year.
    static func regimes(for phase: WorkPhase, in plan: PlanDocument, settings: LibrarySettings,
                        registry: TaxRegistry) -> [RegimeDescriptor] {
        let years = years(of: phase)
        let kind = EarnedIncomeKind(rawValue: phase.kind.rawValue)
        var result: [RegimeDescriptor] = []
        for system in systems(for: plan, from: years.from, through: years.through, settings: settings,
                              registry: registry) {
            for regime in system.regimes where regime.scope.applies(to: kind) && regime.isAvailable(in: years.from) {
                if !result.contains(where: { $0.id == regime.id }) { result.append(regime) }
            }
        }
        // Keep the phase's own choice listed, even if it no longer fits, so the picker can show it.
        if let chosen = phase.regime?.rawValue, !result.contains(where: { $0.id == chosen }),
           let found = registry.regime(chosen)?.regime {
            result.append(found)
        }
        return result
    }

    /// The regime a phase gets when it doesn't choose one, by name: "Employee (default)".
    static func defaultRegimeName(for phase: WorkPhase, in plan: PlanDocument, settings: LibrarySettings,
                                  registry: TaxRegistry) -> String? {
        let years = years(of: phase)
        let kind = EarnedIncomeKind(rawValue: phase.kind.rawValue)
        guard let system = systems(for: plan, from: years.from, through: years.from, settings: settings,
                                   registry: registry).first,
              let id = system.defaultRegime(for: kind)
        else { return nil }
        return system.regime(id)?.name ?? id
    }

    /// The overlays (special regimes) of the plan's residence systems.
    static func overlays(for plan: PlanDocument, settings: LibrarySettings, registry: TaxRegistry)
        -> [RegimeDescriptor] {
        var result: [RegimeDescriptor] = []
        for system in systems(for: plan, from: Int.min, through: nil, settings: settings, registry: registry) {
            for regime in system.regimes where regime.scope == .overlay && !result.contains(where: { $0.id == regime.id }) {
                result.append(regime)
            }
        }
        return result
    }

    /// The pension schemes of the plan's residence systems, `fixed` included, without repeats.
    static func pensionSchemes(for plan: PlanDocument, settings: LibrarySettings, registry: TaxRegistry)
        -> [any PensionScheme] {
        var result: [any PensionScheme] = []
        let systems = systems(for: plan, from: Int.min, through: nil, settings: settings, registry: registry)
        for system in systems.isEmpty ? registry.systems : systems {
            for scheme in system.pensionSchemes where !result.contains(where: { $0.id == scheme.id }) {
                result.append(scheme)
            }
        }
        if !result.contains(where: { $0.id == FixedPensionScheme.schemeID }) {
            result.append(FixedPensionScheme())
        }
        return result
    }

    /// The fields of a pension's `options`. A `fixed` pension's amount and
    /// age are its own keys (`fromAge`, `perYear`), so they're left out here.
    static func pensionOptionFields(scheme: String, registry: TaxRegistry) -> [OptionField] {
        let fields = registry.pensionScheme(scheme)?.options ?? []
        return scheme == FixedPensionScheme.schemeID ? fields.filter { !["perYear", "fromAge"].contains($0.key) } : fields
    }

    /// The fields of a regime's options.
    static func regimeFields(_ id: String?, registry: TaxRegistry) -> [OptionField] {
        guard let id else { return [] }
        return registry.regime(id)?.regime.options ?? []
    }

    /// The fields of a residence entry's options.
    static func systemFields(_ id: TaxSystemID, registry: TaxRegistry) -> [OptionField] {
        registry.system(id.rawValue)?.options ?? []
    }

    /// When an overlay starts, as far as the editor can tell: its first
    /// year-kind option (e.g. `movedIn`), or the regime's first year. And
    /// when it ends, if the regime says (`lastYear`). TaxKit doesn't describe
    /// how long a regime lasts from the move (impatriati: 5 years), so an
    /// open end is shown as open rather than guessed.
    static func overlayYears(_ overlay: PlanOverlay, plan: PlanDocument, registry: TaxRegistry)
        -> (start: Int, end: Int?)? {
        guard let regime = registry.regime(overlay.regime.rawValue)?.regime else { return nil }
        let yearField = regime.options.first { $0.kind == .year }
        guard let start = yearField.flatMap({ overlay.options[$0.key]?.intValue }) ?? regime.firstYear else {
            return nil
        }
        return (start, regime.lastYear.map { max(start, $0) })
    }
}
