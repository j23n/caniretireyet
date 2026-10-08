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

    /// The issues a card lists itself: those not shown on one of its rows.
    func cardIssues(for section: PlanInputSection, in plan: PlanDocument) -> [PlanIssue] {
        let all = issues(for: section)
        switch section {
        case .work, .pensions, .income, .contributions, .events:
            return all.filter { $0.index == nil }
        default:
            return all
        }
    }

    var errorCount: Int { bySection.values.reduce(0) { $0 + $1.filter(\.isError).count } }
    var warningCount: Int { bySection.values.reduce(0) { $0 + $1.filter { !$0.isError }.count } }
    var all: [PlanIssue] { PlanInputSection.allCases.flatMap { issues(for: $0) } }
}

/// The one-line summaries on the collapsed cards, e.g. "Born 1988 · retire
/// at 55 · plan to 95". Amounts read `•••••` while hidden.
struct PlanInputSummaries {
    var plan: PlanDocument
    var library: Library
    var currency: CurrencyCode
    var hidesAmounts = false
    var locale: Locale = .current

    func summary(for section: PlanInputSection) -> String {
        switch section {
        case .you: you
        case .work: work
        case .spending: spending
        case .pensions: pensions
        case .income: income
        case .contributions: contributions
        case .events: events
        case .taxes: taxes
        case .assumptions: assumptions
        case .targetMix: PlanTargetMixModel.summary(plan.portfolio, locale: locale)
        case .simulation: simulation
        }
    }

    // MARK: Formatting

    func amount(_ value: Decimal) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(value, currency: currency, locale: locale)
    }

    func percent(_ value: Decimal, digits: Int = 1) -> String {
        AmountFormat.percent(value, digits: digits, locale: locale)
    }

    /// "2026–28", "2029–retirement", "2026".
    static func years(from: Int, until: Int?) -> String {
        guard let until else { return "\(from)–retirement" }
        if until == from { return "\(from)" }
        if until / 100 == from / 100 { return "\(from)–\(String(format: "%02d", until % 100))" }
        return "\(from)–\(until)"
    }

    // MARK: Sections

    var you: String {
        var parts: [String] = []
        if let birth = library.settings.person?.birthDate {
            parts.append("Born \(birth.year)")
        } else {
            parts.append("No birth date")
        }
        switch plan.retirement.age {
        case .earliest: parts.append("retire as early as possible")
        case .age(let age): parts.append("retire at \(age)")
        }
        parts.append("plan to \(plan.effectiveEndAge)")
        return parts.joined(separator: " · ")
    }

    var work: String {
        guard !plan.work.isEmpty else { return "No work phases" }
        return plan.work.enumerated().map { index, phase in
            "\(PlanWorkText.title(of: phase, index: index, of: plan.work.count)) \(PlanWorkText.years(of: phase))"
        }.joined(separator: " · ")
    }

    var spending: String {
        var parts: [String] = []
        if plan.spending.working == plan.spending.retired {
            parts.append("\(amount(plan.spending.retired))/yr")
        } else {
            parts.append("\(amount(plan.spending.working)) working")
            parts.append("\(amount(plan.spending.retired)) retired")
        }
        for phase in plan.spending.phases.sorted(by: { $0.fromAge < $1.fromAge }) {
            parts.append("\(percent(phase.factor, digits: 0)) from \(phase.fromAge)")
        }
        if let rule = plan.spending.flexibleRule {
            parts.append("flexible, down to \(percent(rule.effectiveFloor, digits: 0))")
        }
        return parts.joined(separator: " · ")
    }

    var pensions: String {
        guard !plan.pensions.isEmpty else { return "No pensions" }
        return plan.pensions.enumerated().map { index, pension in
            let name = PlanResultsMapping.shortName(
                PlanResultsMapping.pensionName(pension, index: index, of: plan.pensions.count))
            return pension.fromAge.map { "\(name) \($0)" } ?? name
        }.joined(separator: " · ")
    }

    var income: String {
        guard !plan.income.isEmpty else { return "None" }
        return plan.income.enumerated().map { index, income in
            PlanResultsMapping.shortName(PlanResultsMapping.incomeName(income, index: index, of: plan.income.count))
        }.joined(separator: " · ")
    }

    var contributions: String {
        guard !plan.contributions.isEmpty else { return "None" }
        return plan.contributions.map { contribution in
            let name = title(of: contribution)
            if let oneOff = contribution.amount {
                return "\(name) \(amount(oneOff))" + (contribution.year.map { " in \($0)" } ?? "")
            }
            return "\(name) \(amount(contribution.perYear))/yr"
        }.joined(separator: " · ")
    }

    /// What a contribution pays into: the account's name.
    func title(of contribution: PlanContribution) -> String {
        library.accounts[contribution.account]?.name ?? contribution.account.rawValue
    }

    /// A contribution's second line: "Every year until retirement ·
    /// 5.000 €/yr", "Once in 2030 · 20.000 €".
    func detail(of contribution: PlanContribution) -> String {
        var parts: [String] = []
        if let oneOff = contribution.amount {
            parts.append(contribution.year.map { "Once in \($0)" } ?? "Once")
            parts.append(amount(oneOff))
        } else {
            switch contribution.effectiveUntil {
            case .retirement: parts.append("Every year until retirement")
            case .date(let date): parts.append("Every year until \(date.year)")
            }
            parts.append("\(amount(contribution.perYear))/yr")
        }
        return parts.joined(separator: " · ")
    }

    var events: String {
        guard !plan.events.isEmpty else { return "None" }
        return plan.events.map { event in
            var text = event.name
            switch event.timing {
            case .age(let age): text += " at \(age)"
            case .year(let year): text += " \(year)"
            }
            if event.effectiveProbability < 1 {
                text += " (\(percent(event.effectiveProbability, digits: 0)))"
            }
            return text
        }.joined(separator: " · ")
    }

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

    // MARK: List rows

    /// A work phase's second line: "40.000 €/yr after tax · +1%/yr".
    func detail(of phase: WorkPhase) -> String {
        var parts: [String] = []
        if let net = phase.netIncome {
            parts.append("\(amount(net))/yr after tax")
        } else {
            parts.append("Income after tax not set")
        }
        if let growth = phase.realGrowth, growth != 0 {
            parts.append("\(growth > 0 ? "+" : "")\(percent(growth))/yr")
        }
        return parts.joined(separator: " · ")
    }

    /// A pension's second line: "From 67 · 14.000 €/yr after tax".
    func detail(of pension: PlanPension) -> String {
        var parts: [String] = []
        if let age = pension.fromAge { parts.append("From \(age)") }
        if let amount = pension.perYear {
            parts.append("\(self.amount(amount))/yr after tax")
        } else {
            parts.append("Amount not set")
        }
        return parts.joined(separator: " · ")
    }

    /// An event's second line: "+150.000 € · 80% likely", "−25.000 €".
    func detail(of event: PlanEvent) -> String {
        let sign = event.amount > 0 ? "+" : ""
        var text = hidesAmounts ? AmountFormat.hidden : sign + AmountFormat.amount(event.amount, currency: currency, locale: locale)
        if event.effectiveProbability < 1 { text += " · \(percent(event.effectiveProbability, digits: 0)) likely" }
        return text
    }
}

/// How work phases read in rows and summaries.
enum PlanWorkText {
    /// The phase's name, else "Work", or "Work 2" when there are several
    /// (as the planner names it).
    static func title(of phase: WorkPhase, index: Int, of count: Int) -> String {
        phase.name ?? (count == 1 ? "Work" : "Work \(index + 1)")
    }

    /// "2026–28", "2029–retirement".
    static func years(of phase: WorkPhase) -> String {
        PlanInputSummaries.years(from: phase.from.year, until: phase.until.date?.year)
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
