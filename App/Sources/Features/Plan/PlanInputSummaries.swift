import Foundation
import Model
import Planner

/// The sections of a plan's inputs, in order (UI.md, "The editors"): the
/// plan file's sections, plus the birth date from the library. *All
/// assumptions…* shows some as cards, and issues are grouped by them.
enum PlanInputSection: String, CaseIterable, Hashable, Sendable, Identifiable {
    case you
    case work
    case spending
    case pensions
    case income
    case contributions
    case events
    case taxes
    case assumptions
    case targetMix
    case simulation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .you: "You"
        case .work: "Work"
        case .spending: "Spending"
        case .pensions: "Pensions"
        case .income: "Other income"
        case .contributions: "Contributions"
        case .events: "Events"
        case .taxes: "Taxes"
        case .assumptions: "Assumptions"
        case .targetMix: "Target mix"
        case .simulation: "Simulation"
        }
    }

    var systemImage: String {
        switch self {
        case .you: "person"
        case .work: "briefcase"
        case .spending: "cart"
        case .pensions: "building.columns"
        case .income: "banknote"
        case .contributions: "arrow.down.to.line"
        case .events: "calendar"
        case .taxes: "percent"
        case .assumptions: "chart.line.uptrend.xyaxis"
        case .targetMix: "chart.pie"
        case .simulation: "dice"
        }
    }

    /// The card an issue shows on: the target mix's own card for the
    /// target mix and its changes with age, else its section's.
    init(_ issue: PlanIssue) {
        if issue.section == .portfolio, issue.option == "targetMix" || issue.option == "targetMixByAge" {
            self = .targetMix
        } else {
            self.init(issue.section)
        }
    }

    /// The card an issue about `section` shows on. The portfolio's other
    /// settings (start, excluded accounts, gains estimate) live on
    /// Assumptions.
    init(_ section: PlanSection) {
        switch section {
        case .person, .retirement: self = .you
        case .work: self = .work
        case .spending: self = .spending
        case .pensions: self = .pensions
        case .income: self = .income
        case .contributions: self = .contributions
        case .events: self = .events
        case .tax: self = .taxes
        case .portfolio, .assumptions: self = .assumptions
        case .simulation: self = .simulation
        default: self = .assumptions
        }
    }
}

/// Issues grouped by the card they belong on.
struct PlanInputIssues: Hashable, Sendable {
    private(set) var bySection: [PlanInputSection: [PlanIssue]] = [:]

    /// Issues without repeats, placed by their section.
    init(_ issues: [PlanIssue]) {
        var seen: Set<PlanIssue> = []
        for issue in issues where seen.insert(issue).inserted {
            bySection[PlanInputSection(issue), default: []].append(issue)
        }
    }

    func issues(for section: PlanInputSection) -> [PlanIssue] {
        bySection[section] ?? []
    }

    /// The issues about one item of a list section (a work phase, a
    /// pension, a contribution, an event), by position.
    func issues(for section: PlanInputSection, index: Int) -> [PlanIssue] {
        issues(for: section).filter { $0.index == index }
    }
}

/// The one-line summaries on *Assumptions…*'s collapsed cards, e.g. "26% on
/// investments · no wealth tax". Amounts read `•••••` while hidden.
struct PlanInputSummaries {
    var plan: PlanDocument
    var library: Library
    var currency: CurrencyCode
    var hidesAmounts = false
    var locale: Locale = .current

    func summary(for section: PlanInputSection) -> String {
        switch section {
        case .you: library.settings.person?.birthDate.map { "Born \($0.year)" } ?? "No birth date"
        case .taxes: taxes
        case .assumptions: assumptions
        case .targetMix: PlanTargetMixModel.summary(plan.portfolio, locale: locale)
        case .simulation: simulation
        // The chapters show these: no card sums them up.
        case .work, .spending, .pensions, .income, .contributions, .events: ""
        }
    }

    // MARK: Formatting

    func amount(_ value: Decimal) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(value, currency: currency, locale: locale)
    }

    func percent(_ value: Decimal, digits: Int = 1) -> String {
        AmountFormat.percent(value, digits: digits, locale: locale)
    }

    // MARK: Sections

    /// "26% on investments · wealth tax 0.2% above 50.000 €", or what's missing.
    var taxes: String {
        guard let rate = plan.tax.investmentRate else { return "Tax on investments not set" }
        var parts = ["\(percent(rate)) on investments"]
        let wealth = plan.tax.effectiveWealthRate
        if wealth > 0 {
            let allowance = plan.tax.effectiveWealthAllowance
            parts.append("wealth tax \(percent(wealth, digits: 2))"
                + (allowance > 0 ? " above \(amount(allowance))" : ""))
        } else {
            parts.append("no wealth tax")
        }
        return parts.joined(separator: " · ")
    }

    var assumptions: String {
        let equity = plan.assumptions.returnAssumption(for: .equity)
        // What the return is given by: the typical year (median) or the average (mean).
        var equityText = equity.map { $0.isGivenByMedian ? "Equity \(percent($0.impliedMedianReal)) typical year"
            : "Equity \(percent($0.real)) average" } ?? "Equity \(percent(0))"
        if let income = equity?.incomeYield { equityText += " (\(percent(income)) income)" }
        var parts = [equityText, "Inflation \(percent(plan.assumptions.effectiveInflation))"]
        let otherYields = plan.assumptions.returns.filter { $0.key != .equity && $0.value.incomeYield != nil }.count
        if otherYields > 0 { parts.append(otherYields == 1 ? "1 other income yield" : "\(otherYields) income yields") }
        // Returns an earlier version wrote as its default (the editor offers the current one).
        let previous = plan.assumptions.returns.keys
            .filter { plan.assumptions.previousDefaultReturn(for: $0) != nil }.count
        if previous > 0 {
            parts.append(previous == 1 ? "1 previous default return" : "\(previous) previous default returns")
        }
        if !plan.portfolio.exclude.isEmpty {
            parts.append("\(plan.portfolio.exclude.count) excluded")
        }
        return parts.joined(separator: " · ")
    }

    var simulation: String {
        let runs = AmountFormat.number(Decimal(plan.simulation.effectiveRuns), locale: locale)
        return "\(runs) runs · \(percent(plan.simulation.effectiveConfidence, digits: 0)) confidence"
    }
}

/// How work phases read in rows.
enum PlanWorkText {
    /// "2026–28", "2029–retirement", "2026".
    static func years(of phase: WorkPhase) -> String {
        let from = phase.from.year
        guard let until = phase.until.date?.year else { return "\(from)–retirement" }
        if until == from { return "\(from)" }
        if until / 100 == from / 100 { return "\(from)–\(String(format: "%02d", until % 100))" }
        return "\(from)–\(until)"
    }
}

/// How other income reads in rows.
enum PlanIncomeText {
    /// "From 57 until 65", "From when you stop working until 60", "From 45".
    static func span(of income: PlanIncome) -> String {
        let from: String = switch income.from {
        case .age(let age): "From \(age)"
        case .retirement: "From when you stop working"
        case nil: "No start yet"
        }
        return from + (income.untilAge.map { " until \($0)" } ?? "")
    }
}
