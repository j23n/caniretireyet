import Foundation
import Model
import TaxKit

/// A way to claim a pension, as its scheme lists it (`ClaimOption.route`),
/// e.g. the annuity alone, or part of a pension fund as a lump sum.
struct PlanClaimRoute: Hashable, Sendable, Identifiable {
    /// The route's ID, as the plan's `claimRoute` names it.
    var id: String
    /// The scheme's label for it, e.g. "Anticipata contributiva".
    var label: String
    /// The ages it's offered at with the pension's details as they are, ascending.
    var ages: [Int]
    /// Whether one of its options pays a lump sum.
    var paysLumpSum: Bool

    /// "Anticipata contributiva · from 64", "Capital · at 65, lump sum".
    var title: String {
        var parts = [label]
        if let first = ages.first {
            parts.append(ages.count == 1 ? "at \(first)" : "from \(first)")
        }
        return parts.joined(separator: " · ") + (paysLumpSum ? ", lump sum" : "")
    }
}

/// What the pension editor offers, read from the tax registry: the kinds a
/// statement pension can be, and the ways a scheme can be claimed. A scheme
/// added to the registry brings its routes with no UI code.
enum PlanPensionChoices {
    /// The kinds a pension can say (`kind`), for systems that tax kinds differently.
    static let kinds: [PlanPensionKind] = PlanPensionKind.knownValues

    /// "State pension", "Occupational pension", …
    static func name(of kind: PlanPensionKind) -> String {
        switch kind {
        case .statutory: "State pension"
        case .occupational: "Occupational pension"
        case .basicPension: "Basic pension (private, taxed like a state one)"
        case .privateAnnuity: "Private annuity"
        default: kind.rawValue
        }
    }

    /// The pension's options as the planner passes them to its scheme: a
    /// `fixed` pension's `fromAge` and `perYear` are its own keys.
    static func options(of pension: PlanPension) -> OptionValues {
        var options = PlanOptionForm.optionValues(pension.options)
        if pension.scheme == .fixed {
            if let age = pension.fromAge { options["fromAge"] = .number(Double(age)) }
            if let amount = pension.perYear { options["perYear"] = .number(amount.doubleValue) }
        }
        return options
    }

    /// The routes the pension's scheme offers with its details as they are,
    /// in the order the scheme lists them: its claim options for a record
    /// started from the pension's options, asked once as if still working
    /// and once as if work had just stopped (some schemes offer other
    /// routes then), from `today`'s year on. Routes that need more
    /// contributions than the details say yet don't show; empty when the
    /// scheme lists none (or isn't registered).
    static func claimRoutes(for pension: PlanPension, birthDate: CalendarDate?, today: CalendarDate,
                            registry: TaxRegistry = AppTaxRegistry.standard) -> [PlanClaimRoute] {
        guard let owner = registry.systems.first(where: { $0.pensionScheme(pension.scheme.rawValue) != nil }),
              let scheme = owner.pensionScheme(pension.scheme.rawValue) else { return [] }
        let options = options(of: pension)
        let birth = birthDate ?? YouSettings.suggestedBirthDate(today: today)
        let record = scheme.startingRecord(options: options, year: today.year, parameters: owner.parameters)
        var routes: [PlanClaimRoute] = []
        for stopped in [nil, 0] as [Int?] {
            let context = ClaimContext(year: today.year, birthDate: BirthDate(year: birth.year, month: birth.month,
                                                                              day: birth.day),
                                       options: options, yearsSinceWorkStopped: stopped)
            for option in scheme.claimOptions(for: record, context: context, parameters: owner.parameters) {
                let lumpSum = (option.lumpSum ?? 0) > 0
                if let index = routes.firstIndex(where: { $0.id == option.route }) {
                    if !routes[index].ages.contains(option.age) { routes[index].ages.append(option.age) }
                    routes[index].ages.sort()
                    routes[index].paysLumpSum = routes[index].paysLumpSum || lumpSum
                } else {
                    routes.append(PlanClaimRoute(id: option.route, label: option.label, ages: [option.age],
                                                 paysLumpSum: lumpSum))
                }
            }
        }
        return routes
    }

    /// Whether the editor offers a choice of route: the scheme lists more
    /// than one, or the plan names one already.
    static func offersRouteChoice(_ routes: [PlanClaimRoute], pension: PlanPension) -> Bool {
        routes.count > 1 || pension.claimRoute != nil
    }

    /// The route's label for a plan's `claimRoute`, else the ID as written.
    static func routeName(_ route: String, among routes: [PlanClaimRoute]) -> String {
        routes.first { $0.id == route }?.label ?? route
    }
}
