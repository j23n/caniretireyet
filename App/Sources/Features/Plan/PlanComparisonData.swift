import Foundation
import Model

/// Comparing two plans (UI.md, "Comparing two plans"): both headlines, both
/// success curves on one chart, and a table of key numbers. This is the
/// screen for regime decisions, e.g. forfettario against ordinario with
/// impatriati.
struct PlanComparisonData: Sendable {
    struct Side: Sendable {
        var plan: PlanDocument
        var results: PlanResults?
        /// Why `results` no longer fit the plan and the library; empty when they do.
        var staleReasons: [PlanStaleReason] = []
        /// The answer recorded at the plan's last check-in, for before its
        /// first calculation.
        var recorded: PlanHeadline?
        /// The plan's currency (``PlanMoney/currency(of:settings:)``), for
        /// two plans in different currencies.
        var currency: CurrencyCode?

        /// Whether *Calculate* has anything to do for this plan.
        var needsCalculation: Bool { results == nil || !staleReasons.isEmpty }

        /// An amount of this plan, in its results' currency (else its own).
        func figure(_ amount: Decimal, unit: String?) -> PlanFigure {
            guard let currency = results?.currency ?? currency else { return .amount(amount, unit: unit) }
            return .amountIn(amount, currency: currency, unit: unit)
        }
    }

    var first: Side
    var second: Side

    /// The plans one *Calculate* runs, in order: those without results or
    /// with results out of date.
    var plansToCalculate: [PlanID] {
        [first, second].filter(\.needsCalculation).map(\.plan.id)
    }

    /// "Calculate" before either plan has results, else "Recalculate".
    var calculateTitle: String {
        first.results == nil && second.results == nil ? "Calculate" : "Recalculate"
    }

    /// Both curves, direct-labelled by plan name.
    var series: [SuccessSeries] {
        [first, second].enumerated().compactMap { index, side in
            side.results.map {
                SuccessSeries(id: side.plan.id.rawValue, name: side.plan.name, color: .series(index),
                              points: $0.successByAge)
            }
        }
    }

    /// The years both plans have a net income for.
    var years: [Int] {
        let a = Set(first.results?.details?.focus.netIncome.map(\.year) ?? [])
        let b = Set(second.results?.details?.focus.netIncome.map(\.year) ?? [])
        return a.intersection(b).sorted()
    }

    /// The year to show net income for by default: the first year the two
    /// plans' net incomes differ by more than 1%, else the first full year.
    var defaultYear: Int? {
        let a = first.results?.details?.focus.netIncome ?? []
        let b = second.results?.details?.focus.netIncome ?? []
        for year in years {
            guard let x = a.first(where: { $0.year == year })?.value,
                  let y = b.first(where: { $0.year == year })?.value else { continue }
            if abs(x - y) > max(1, 0.01 * max(abs(x), abs(y))) { return year }
        }
        return years.dropFirst().first ?? years.first
    }

    /// The public pension schemes either plan has, e.g. `it.inps`, in order.
    var publicSchemes: [(scheme: String, name: String)] {
        var result: [(String, String)] = []
        for side in [first, second] {
            for pension in side.results?.details?.focus.pensions ?? [] where pension.scheme != "fixed" {
                if !result.contains(where: { $0.0 == pension.scheme }) {
                    result.append((pension.scheme, PlanResultsMapping.shortName(pension.name)))
                }
            }
        }
        return result
    }

    /// The table: net income in `year`, each public pension, lifetime
    /// taxes, earliest retirement, and more.
    func rows(year: Int?) -> [(label: String, values: [PlanFigure])] {
        var rows: [(String, [PlanFigure])] = []
        let sides = [first, second]
        if let year {
            rows.append(("Net income \(year)", sides.map { side in
                guard let value = side.results?.details?.focus.netIncome.first(where: { $0.year == year })?.value
                else { return .missing }
                return side.figure(PlanResultsText.whole(value), unit: nil)
            }))
        }
        for scheme in publicSchemes {
            rows.append(("\(scheme.name) pension", sides.map { side in
                guard let pension = side.results?.details?.focus.pensions.first(where: { $0.scheme == scheme.scheme }),
                      let amount = pension.perYear
                else { return .missing }
                return side.figure(PlanResultsText.whole(amount), unit: pension.age.map { "/yr at \($0)" } ?? "/yr")
            }))
        }
        rows.append(("Taxes, lifetime", sides.map { side in
            side.results?.details.map { side.figure(PlanResultsText.whole($0.focus.lifetimeTaxes), unit: nil) }
                ?? .missing
        }))
        rows.append(("Earliest retirement", sides.map { side in
            guard let results = side.results else { return .missing }
            return .text(results.headline.earliestAge.map(String.init) ?? "None yet")
        }))
        rows.append(("Chance of success at target", sides.map { side in
            guard let headline = side.results?.headline, let success = headline.successAtTarget else { return .missing }
            return .percent(success)
        }))
        rows.append(("Sustainable spending", sides.map { side in
            side.results?.headline.sustainableSpending.map { side.figure($0, unit: "/yr") } ?? .missing
        }))
        return rows
    }
}
