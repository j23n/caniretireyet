import Foundation
import Model
import Tracker

/// Edits the Plan screens make to a `PlanDocument`, as plain functions:
/// new plans, new list items with sensible defaults, and the conversions
/// the editors need. Everything is saved through `LibraryStore.save(_:)`.
///
/// Default amounts follow the library (UI.md, "The editors"): a new plan spends
/// what your other plans say, else 30.000 euros' worth in the base
/// currency; a new item's amount is in proportion to the plan's spending.
enum PlanEditing {
    // MARK: Plans

    /// A new plan starting from sensible defaults: retire as early as
    /// possible, spend what the library suggests (``defaultSpending(in:asOf:)``),
    /// and the tax rates of your other plans (``defaultTax(in:)``).
    static func newPlan(id: PlanID, name: String, library: Library, asOf: CalendarDate) -> PlanDocument {
        PlanDocument(id: id, name: name, retirement: PlanRetirement(age: .earliest),
                     tax: defaultTax(in: library), spending: defaultSpending(in: library, asOf: asOf))
    }

    /// The plan onboarding creates (UI.md, "Empty states and first
    /// launch"): a ``newPlan(id:name:library:asOf:)`` that spends
    /// `spendingPerMonth` while working and in retirement, when it's given
    /// (0 included), and, when `payPerMonth` is given and above 0, has one
    /// work phase from `asOf` until retirement paying it after tax. A
    /// negative amount is left out. Amounts are in the base currency; a
    /// plan stores them a year.
    static func starterPlan(id: PlanID, name: String, library: Library, asOf: CalendarDate,
                            payPerMonth: Decimal?, spendingPerMonth: Decimal?) -> PlanDocument {
        var plan = newPlan(id: id, name: name, library: library, asOf: asOf)
        if let spendingPerMonth, spendingPerMonth >= 0 {
            plan.spending.working = spendingPerMonth * 12
            plan.spending.retired = spendingPerMonth * 12
        }
        if let payPerMonth, payPerMonth > 0 {
            plan.work = [WorkPhase(from: asOf, until: .retirement, netIncome: payPerMonth * 12)]
        }
        return plan
    }

    /// The plan the library's defaults come from: the main plan, else the
    /// first plan by ID.
    static func sourcePlan(in library: Library) -> PlanDocument? {
        library.settings.mainPlan.flatMap { library.plans[$0] } ?? library.plans.values.min { $0.id < $1.id }
    }

    /// A new plan's tax rates: those of the main plan (else the first plan
    /// by ID), since you've set them already; else none, which runs as 0%
    /// on investments with a warning until it's set.
    static func defaultTax(in library: Library) -> PlanTax {
        sourcePlan(in: library)?.tax ?? PlanTax()
    }

    /// What a new plan spends a year, while working and in retirement:
    ///
    /// 1. what the main plan spends (else the first plan by ID), since
    ///    you've said it already;
    /// 2. else 30.000 euros' worth in the base currency, at the library's
    ///    latest rate on `asOf`, to two significant figures (35.000 for
    ///    dollars, 4.800.000 for yen);
    /// 3. else, without a rate to the euro, 30.000 in the base currency.
    static func defaultSpending(in library: Library, asOf: CalendarDate) -> PlanSpending {
        let base = library.settings.baseCurrency
        if let source = sourcePlan(in: library) {
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
        let value = amount.doubleValue
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
    /// start of next year) until retirement, earning after tax a third more
    /// than the plan spends while working.
    static func newWorkPhase(in plan: PlanDocument, asOf: CalendarDate) -> WorkPhase {
        let lastEnd = plan.work.compactMap { $0.until.date }.max()
        let from = lastEnd?.adding(days: 1) ?? asOf.adding(days: 1)
        return WorkPhase(from: from, until: .retirement, netIncome: share(of: plan, Decimal(4) / 3, fallback: 40_000))
    }

    /// A pension from 67 whose amount after tax is still to fill in.
    static func newPension() -> PlanPension {
        PlanPension(name: "Pension", fromAge: 67, perYear: nil)
    }

    /// A yearly contribution into the first plan account available from a
    /// later age (a pension fund), else the first plan account: a thirtieth
    /// of what `plan` spends while working (1.000 of 30.000).
    static func newContribution(in library: Library, plan: PlanDocument) -> PlanContribution? {
        let accounts = contributionAccounts(in: library)
        let perYear = share(of: plan, Decimal(1) / 30, fallback: 1_000)
        guard let account = accounts.first(where: { $0.availableFromAge != nil }) ?? accounts.first else { return nil }
        return PlanContribution(account: account.id, perYear: perYear)
    }

    /// `share` of what `plan` spends while working, as a default amount;
    /// `fallback` when it spends nothing.
    static func share(of plan: PlanDocument, _ share: Decimal, fallback: Decimal) -> Decimal {
        plan.spending.working > 0 ? roundedForDefault(plan.spending.working * share) : fallback
    }

    /// An expense in five years of a third of what `plan` spends while
    /// working (10.000 of 30.000).
    static func newEvent(in plan: PlanDocument, asOf: CalendarDate) -> PlanEvent {
        PlanEvent(name: "New event", timing: .year(asOf.year + 5), amount: -share(of: plan, Decimal(1) / 3, fallback: 10_000))
    }

    /// Under the rate on investments (UI.md, "The editors").
    static let investmentRateExplanation = "Paid on the gain part of what you sell and, every year, on the income "
        + "your investments pay out (Assumptions, income yield). 26% in Italy, for example; 0% if they aren't taxed. "
        + "Income from work and pensions is entered after tax."

    /// Under the wealth tax.
    static let wealthTaxExplanation = "A yearly tax on the money you can draw, above the allowance. Accounts "
        + "available only from a later age, such as a pension fund, aren't counted until then."

    /// Under the flexible-spending switch (UI.md, "The editors").
    static let flexibleExplanation = "Cuts spending in retirement after bad years and restores it after good ones, "
        + "as real retirees do, instead of spending the same whatever the markets do. A future only fails if you'd "
        + "have to spend less than the floor."

    /// Under the guardrails.
    static let guardrailsExplanation = "Each year the plan compares the share of your money you draw with the first "
        + "year of retirement's: this much above it, spending is cut; this much below it, a cut is restored."

    static func newSpendingPhase(in plan: PlanDocument) -> SpendingPhase {
        let last = plan.spending.phases.map(\.fromAge).max()
        return SpendingPhase(fromAge: last.map { $0 + 10 } ?? 75, factor: Decimal(string: "0.9")!)
    }

    // MARK: Assumptions

    /// The asset classes the editor offers an income yield for: those whose
    /// funds pay income. Cash earns its interest anyway.
    static let incomeYieldClasses: [AssetClass] = [.equity, .bonds]

    /// The line under the income yields.
    static let incomeYieldExplanation = "The part of the return paid out as income each year (dividends, interest), "
        + "taxed every year at the rate on investments. Leave it empty to count it as growth, taxed when sold."

    /// The line under the returns.
    static let returnsExplanation = "Placeholders to review, not forecasts: real returns after fund costs. The mean "
        + "is the average year, the median the typical one, which a portfolio rebalanced every year grows at. Enter "
        + "either: the other follows from the volatility."

    /// The note on a class whose return repeats an earlier version's default
    /// exactly (`PlanAssumptions.previousDefaultReturn(for:)`), which the plan
    /// most likely didn't choose: "This is the previous default (4.5%
    /// average). The current default is a 5.0% typical year." `nil` for any
    /// other class.
    static func previousDefaultNote(for assetClass: AssetClass, in assumptions: PlanAssumptions,
                                    locale: Locale = .current) -> String? {
        guard let previous = assumptions.previousDefaultReturn(for: assetClass),
              let current = PlanAssumptions.defaultReturns[assetClass] else { return nil }
        return "This is the previous default (\(returnInWords(previous, locale: locale))). "
            + "The current default is a \(returnInWords(current, locale: locale))."
    }

    /// "4.5% average" for a return given by its mean, "5.0% typical year"
    /// for one given by its median, to one decimal.
    private static func returnInWords(_ assumption: ReturnAssumption, locale: Locale) -> String {
        let value = assumption.isGivenByMedian ? assumption.impliedMedianReal : assumption.real
        let text = AmountFormat.typographicMinus(value.doubleValue
            .formatted(.percent.precision(.fractionLength(1)).locale(locale)))
        return assumption.isGivenByMedian ? "\(text) typical year" : "\(text) average"
    }

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

    // MARK: Accounts

    /// Accounts a contribution can go to, and the plan can leave out: open
    /// ones the plan counts.
    static func contributionAccounts(in library: Library) -> [Account] {
        library.accounts.values.filter { $0.includedInPlan && !$0.isClosed }.sorted { $0.name < $1.name }
    }
}
