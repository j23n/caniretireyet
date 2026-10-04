import Foundation
import Model
import TaxKit
import Tracker

/// Edits the Plan screens make to a `PlanDocument`, as plain functions:
/// new plans, new list items with sensible defaults, and the conversions
/// the editors need. Everything is saved through `LibraryStore.save(_:)`.
///
/// Default amounts follow the library (UI.md, "Inputs"): a new plan spends
/// what your other plans say, else 30.000 euros' worth in the base
/// currency; a new item's amount is in proportion to the plan's spending.
enum PlanEditing {
    // MARK: Plans

    /// A new plan starting from sensible defaults: retire as early as
    /// possible, spend what the library suggests (``defaultSpending(in:asOf:)``),
    /// taxes where you live from this year. It's in the library's base currency.
    static func newPlan(id: PlanID, name: String, library: Library, asOf: CalendarDate,
                        registry: TaxRegistry) -> PlanDocument {
        var plan = PlanDocument(id: id, name: name, retirement: PlanRetirement(age: .earliest),
                                spending: defaultSpending(in: library, asOf: asOf))
        if let system = PlanTaxChoices.residenceSystem(for: library.settings, registry: registry) {
            plan.tax.residence = [PlanResidence(from: asOf.year, system: TaxSystemID(system.id))]
        }
        return plan
    }

    /// What a new plan spends a year, while working and in retirement:
    ///
    /// 1. what the main plan spends (else the first plan by ID), when it's
    ///    in the base currency, since you've said it already;
    /// 2. else 30.000 euros' worth in the base currency, at the library's
    ///    latest rate on `asOf`, to two significant figures (35.000 for
    ///    dollars, 4.800.000 for yen);
    /// 3. else, without a rate to the euro, 30.000 in the base currency.
    static func defaultSpending(in library: Library, asOf: CalendarDate) -> PlanSpending {
        let base = library.settings.baseCurrency
        let plans = library.plans.values.filter { $0.effectiveCurrency(base: base) == base }
        let main = library.settings.mainPlan.flatMap { id in plans.first { $0.id == id } }
        if let source = main ?? plans.min(by: { $0.id < $1.id }) {
            return PlanSpending(working: source.spending.working, retired: source.spending.retired)
        }
        let amount = FXTable(library: library).convert(referenceSpending, from: .eur, to: base, on: asOf)
            .map(roundedForDefault) ?? referenceSpending
        return PlanSpending(working: amount, retired: amount)
    }

    /// The yearly spending a new plan starts from without other plans: in
    /// euros, converted into the base currency.
    static let referenceSpending: Decimal = 30_000

    /// `amount` to two significant figures: 35.123 → 35.000, 4.812.345 →
    /// 4.800.000. A default to edit, not a figure to trust.
    static func roundedForDefault(_ amount: Decimal) -> Decimal {
        let value = NSDecimalNumber(decimal: amount).doubleValue
        guard value >= 10, value < 1e17 else { return amount }
        let step = Int(pow(10, log10(value).rounded(.down) - 1).rounded())
        return Decimal(Int((value / Double(step)).rounded()) * step)
    }

    /// A name no other plan has: "New plan", "New plan 2", …
    static func uniqueName(_ name: String, among plans: some Sequence<PlanDocument>) -> String {
        let names = Set(plans.map(\.name))
        guard names.contains(name) else { return name }
        var number = 2
        while names.contains("\(name) \(number)") { number += 1 }
        return "\(name) \(number)"
    }

    // MARK: New items

    /// A work phase after the plan's last one: from the next day (or the
    /// start of next year) until retirement, earning in proportion to what
    /// the plan spends while working (a gross salary of 4/3 of it).
    static func newWorkPhase(in plan: PlanDocument, asOf: CalendarDate, kind: WorkKind = .employee) -> WorkPhase {
        let lastEnd = plan.work.compactMap { $0.until.date }.max()
        let from = lastEnd?.adding(days: 1) ?? asOf.adding(days: 1)
        var phase = WorkPhase(kind: kind, from: from, until: .retirement)
        applyDefaultAmounts(to: &phase, spending: plan.spending.working)
        return phase
    }

    /// Fills in the amount a kind of work needs, if it's missing, in
    /// proportion to a yearly spending: a gross salary of 4/3 of it, revenue
    /// of 5/3, net income equal to it. The spending is the one the phase's
    /// amount for another kind of work stands for (a gross salary of 40.000
    /// stands for 30.000), else `spending`; without either, 40.000, 50.000
    /// and 30.000.
    static func applyDefaultAmounts(to phase: inout WorkPhase, spending: Decimal? = nil) {
        let shares: [WorkKind: Decimal] = [.employee: Decimal(4) / 3, .selfEmployed: Decimal(5) / 3, .net: 1]
        let typed: Decimal? = if let gross = phase.grossSalary {
            gross / shares[.employee]!
        } else if let revenue = phase.revenue {
            revenue / shares[.selfEmployed]!
        } else {
            phase.netIncome
        }
        func amount(for kind: WorkKind, fallback: Decimal) -> Decimal {
            guard let reference = typed ?? spending, reference > 0, let share = shares[kind] else { return fallback }
            return roundedForDefault(reference * share)
        }
        switch phase.kind {
        case .employee: if phase.grossSalary == nil { phase.grossSalary = amount(for: .employee, fallback: 40_000) }
        case .selfEmployed: if phase.revenue == nil { phase.revenue = amount(for: .selfEmployed, fallback: 50_000) }
        case .net: if phase.netIncome == nil { phase.netIncome = amount(for: .net, fallback: 30_000) }
        default: break
        }
    }

    /// A phase changed to another kind of work: its regime is cleared
    /// unless it still fits (the system's default applies), and the amount
    /// the new kind needs is filled in.
    static func changing(_ phase: WorkPhase, to kind: WorkKind, registry: TaxRegistry) -> WorkPhase {
        var phase = phase
        phase.kind = kind
        if let regime = phase.regime?.rawValue, let found = registry.regime(regime)?.regime,
           !found.scope.applies(to: EarnedIncomeKind(rawValue: kind.rawValue)) {
            phase.regime = nil
            phase.options = [:]
        }
        applyDefaultAmounts(to: &phase)
        return phase
    }

    /// A phase with another regime (`nil`: the system's default). Options
    /// the new regime doesn't know are dropped.
    static func choosing(_ regime: String?, for phase: WorkPhase, registry: TaxRegistry) -> WorkPhase {
        var phase = phase
        phase.regime = regime.map { RegimeID($0) }
        phase.options = PlanOptionForm.carryOver(phase.options, to: PlanTaxChoices.regimeFields(regime, registry: registry))
        return phase
    }

    /// A pension of `scheme`: `fixed` pensions start at 67 with an amount to fill in.
    static func newPension(scheme: String) -> PlanPension {
        if scheme == FixedPensionScheme.schemeID {
            return PlanPension(scheme: .fixed, name: "Pension", fromAge: 67, perYear: 0)
        }
        return PlanPension(scheme: PensionSchemeID(scheme), claim: .earliest)
    }

    /// A pension moved to another scheme, keeping its name and claim, what
    /// kind it is and where it's from. A claim route belongs to its scheme,
    /// so it goes.
    static func changing(_ pension: PlanPension, toScheme scheme: String, registry: TaxRegistry) -> PlanPension {
        var changed = newPension(scheme: scheme)
        changed.name = pension.name ?? changed.name
        if scheme != FixedPensionScheme.schemeID { changed.claim = pension.claim }
        changed.taxedIn = pension.taxedIn
        changed.sourceCountry = pension.sourceCountry
        changed.kind = pension.kind
        changed.options = PlanOptionForm.carryOver(
            pension.options, to: PlanTaxChoices.pensionOptionFields(scheme: scheme, registry: registry))
        return changed
    }

    /// A yearly contribution into the first plan account with a
    /// tax-advantaged kind (pension fund), else the first plan account,
    /// else into the first pension scheme of `schemes`: a thirtieth of what
    /// `plan` spends while working (1.000 of 30.000).
    static func newContribution(in library: Library, plan: PlanDocument, schemes: [PlanChoice] = [])
        -> PlanContribution? {
        let accounts = contributionAccounts(in: library)
        let perYear = share(of: plan, Decimal(1) / 30, fallback: 1_000)
        if let account = accounts.first(where: { $0.kind == .pensionFund }) ?? accounts.first {
            return PlanContribution(account: account.id, perYear: perYear)
        }
        return schemes.first.map { PlanContribution(pension: PensionSchemeID($0.id), perYear: perYear) }
    }

    /// `share` of what `plan` spends while working, as a default amount;
    /// `fallback` when it spends nothing.
    static func share(of plan: PlanDocument, _ share: Decimal, fallback: Decimal) -> Decimal {
        plan.spending.working > 0 ? roundedForDefault(plan.spending.working * share) : fallback
    }

    /// The pension schemes a contribution can pay into (a buy-in): those of
    /// the plan's residence systems, without `fixed`, which doesn't build up.
    static func contributionSchemes(for plan: PlanDocument, settings: LibrarySettings, registry: TaxRegistry)
        -> [PlanChoice] {
        PlanTaxChoices.schemeChoices(for: plan, settings: settings, registry: registry)
            .filter { $0.id != FixedPensionScheme.schemeID }
    }

    /// An expense in five years of a third of what `plan` spends while
    /// working (10.000 of 30.000).
    static func newEvent(in plan: PlanDocument, asOf: CalendarDate) -> PlanEvent {
        PlanEvent(name: "New event", timing: .year(asOf.year + 5), amount: -share(of: plan, Decimal(1) / 3, fallback: 10_000))
    }

    static func newSpendingPhase(in plan: PlanDocument) -> SpendingPhase {
        let last = plan.spending.phases.map(\.fromAge).max()
        return SpendingPhase(fromAge: last.map { $0 + 10 } ?? 75, factor: Decimal(string: "0.9")!)
    }

    /// A residence entry after the plan's last one: the generic system,
    /// ten years on.
    static func newResidence(in plan: PlanDocument, asOf: CalendarDate) -> PlanResidence {
        let last = plan.tax.residence.map(\.from).max()
        return PlanResidence(from: last.map { $0 + 10 } ?? asOf.year, system: .generic)
    }

    // MARK: Assumptions

    /// The asset classes the editor offers an income yield for: those whose
    /// funds pay income. Cash earns its interest anyway.
    static let incomeYieldClasses: [AssetClass] = [.equity, .bonds]

    /// The line under the income yields.
    static let incomeYieldExplanation = "The part of the return paid as income each year; some countries tax it "
        + "yearly. Leave it empty for none."

    /// The line under the returns.
    static let returnsExplanation = "Placeholders to review, not forecasts: real returns after fund costs. The mean "
        + "is the average year, the median the typical one, which a portfolio rebalanced every year grows at. Enter "
        + "either: the other follows from the volatility."

    // MARK: Lists

    /// `list` without the item at `index` (if it's there).
    static func removing<T>(at index: Int, from list: [T]) -> [T] {
        var list = list
        if list.indices.contains(index) { list.remove(at: index) }
        return list
    }

    /// `list` with `item` at `index`, or appended when `index` is past the end.
    static func replacing<T>(at index: Int, with item: T, in list: [T]) -> [T] {
        var list = list
        if list.indices.contains(index) { list[index] = item } else { list.append(item) }
        return list
    }

    // MARK: Values

    /// A decimal as a whole number, for sliders and steppers.
    static func whole(_ value: Double) -> Decimal {
        Decimal(Int(value.rounded()))
    }

    /// Accounts a contribution can go to: open ones the plan counts.
    static func contributionAccounts(in library: Library) -> [Account] {
        library.accounts.values.filter { $0.includedInPlan && !$0.isClosed }.sorted { $0.name < $1.name }
    }

    /// Accounts the plan could leave out: open ones the plan counts.
    static func excludableAccounts(in library: Library) -> [Account] {
        contributionAccounts(in: library)
    }
}
