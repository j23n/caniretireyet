import Foundation
import Model
import Planner
import TaxKit

/// The cards of the Inputs form, in order (UI.md, "Inputs"): the plan
/// file's sections, plus the birth date from the library.
enum PlanInputSection: String, CaseIterable, Hashable, Sendable, Identifiable {
    case you
    case work
    case spending
    case pensions
    case contributions
    case events
    case taxes
    case assumptions
    case simulation
    case withdrawals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .you: "You"
        case .work: "Work"
        case .spending: "Spending"
        case .pensions: "Pensions"
        case .contributions: "Contributions"
        case .events: "Events"
        case .taxes: "Taxes"
        case .assumptions: "Assumptions"
        case .simulation: "Simulation"
        case .withdrawals: "Withdrawals"
        }
    }

    var systemImage: String {
        switch self {
        case .you: "person"
        case .work: "briefcase"
        case .spending: "cart"
        case .pensions: "building.columns"
        case .contributions: "arrow.down.to.line"
        case .events: "calendar"
        case .taxes: "percent"
        case .assumptions: "chart.line.uptrend.xyaxis"
        case .simulation: "dice"
        case .withdrawals: "arrow.up.forward"
        }
    }

    /// The card an issue about `section` shows on. The portfolio's settings
    /// (start, excluded accounts, target mix, gains estimate) live on
    /// Assumptions.
    init(_ section: PlanSection) {
        switch section {
        case .person, .retirement: self = .you
        case .work: self = .work
        case .spending: self = .spending
        case .pensions: self = .pensions
        case .contributions: self = .contributions
        case .events: self = .events
        case .tax: self = .taxes
        case .portfolio, .assumptions: self = .assumptions
        case .withdrawals: self = .withdrawals
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
            bySection[PlanInputSection(issue.section), default: []].append(issue)
        }
    }

    func issues(for section: PlanInputSection) -> [PlanIssue] {
        bySection[section] ?? []
    }

    /// The issues about one item of a list section (a work phase, a
    /// pension, an event), by position, or by the regime it chose.
    func issues(for section: PlanInputSection, index: Int, regime: String? = nil) -> [PlanIssue] {
        issues(for: section).filter { $0.index == index || (regime != nil && $0.index == nil && $0.regime == regime) }
    }

    /// The issues a card lists itself: those not shown on one of its rows
    /// (work phases by position or regime, pensions and events by position,
    /// tax overlays by regime, residence entries by position).
    func cardIssues(for section: PlanInputSection, in plan: PlanDocument) -> [PlanIssue] {
        let all = issues(for: section)
        switch section {
        case .work:
            let regimes = Set(plan.work.compactMap { $0.regime?.rawValue })
            return all.filter { $0.index == nil && !($0.regime.map { regimes.contains($0) } ?? false) }
        case .pensions, .contributions, .events:
            return all.filter { $0.index == nil }
        case .taxes:
            let overlays = Set(plan.tax.overlays.map(\.regime.rawValue))
            return all.filter { issue in
                if let regime = issue.regime { return !overlays.contains(regime) }
                return issue.index == nil
            }
        default:
            return all
        }
    }

    /// The issues about one tax residence entry.
    func residenceIssues(index: Int) -> [PlanIssue] {
        issues(for: .taxes).filter { $0.index == index && $0.regime == nil }
    }

    /// The issues about one overlay (special regime).
    func overlayIssues(regime: String) -> [PlanIssue] {
        issues(for: .taxes).filter { $0.regime == regime }
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
    var registry: TaxRegistry
    var currency: CurrencyCode
    var hidesAmounts = false
    var locale: Locale = .current

    func summary(for section: PlanInputSection) -> String {
        switch section {
        case .you: you
        case .work: work
        case .spending: spending
        case .pensions: pensions
        case .contributions: contributions
        case .events: events
        case .taxes: taxes
        case .assumptions: assumptions
        case .simulation: simulation
        case .withdrawals: withdrawals
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
        if let currency = plan.currency { parts.append("in \(currency.rawValue)") }
        return parts.joined(separator: " · ")
    }

    var work: String {
        guard !plan.work.isEmpty else { return "No work phases" }
        return plan.work.map { phase in
            "\(PlanWorkText.title(of: phase, registry: registry)) \(PlanWorkText.years(of: phase))"
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
        return parts.joined(separator: " · ")
    }

    var pensions: String {
        guard !plan.pensions.isEmpty else { return "No pensions" }
        return plan.pensions.map { pension in
            let name = PlanResultsMapping.shortName(PlanResultsMapping.pensionName(pension, registry: registry))
            if pension.scheme == .fixed {
                return pension.fromAge.map { "\(name) \($0)" } ?? name
            }
            switch pension.effectiveClaim {
            case .earliest: return "\(name) (earliest)"
            case .age(let age): return "\(name) \(age)"
            }
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

    /// What a contribution pays into: the account's name, or the pension
    /// scheme's ("BVG").
    func title(of contribution: PlanContribution) -> String {
        if let scheme = contribution.pension {
            return PlanResultsMapping.shortName(registry.pensionScheme(scheme.rawValue)?.name ?? scheme.rawValue)
        }
        return library.accounts[contribution.account]?.name ?? contribution.account.rawValue
    }

    /// A contribution's second line: "Every year until retirement ·
    /// 5.000 €/yr", "Pension scheme · once in 2030 · 20.000 €".
    func detail(of contribution: PlanContribution) -> String {
        var parts: [String] = []
        if contribution.pension != nil { parts.append("Pension scheme (buy-in)") }
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

    var taxes: String {
        var parts: [String] = []
        let residence = plan.tax.residence.sorted { $0.from < $1.from }
        if residence.isEmpty {
            let system = PlanTaxChoices.defaultSystem(for: library.settings, registry: registry)
            parts.append("\(system?.name ?? "No tax system") (default)")
        }
        for (index, entry) in residence.enumerated() {
            let name = registry.system(entry.system.rawValue)?.name ?? entry.system.rawValue
            parts.append(index == 0 ? name : "\(name) from \(entry.from)")
        }
        for overlay in plan.tax.overlays {
            let name = registry.regime(overlay.regime.rawValue)?.regime.name ?? overlay.regime.rawValue
            if let years = PlanTaxChoices.overlayYears(overlay, plan: plan, registry: registry) {
                parts.append(years.end.map { "\(name) \(Self.years(from: years.start, until: $0))" }
                    ?? "\(name) from \(years.start)")
            } else {
                parts.append(name)
            }
        }
        if !plan.tax.overrides.isEmpty {
            parts.append(plan.tax.overrides.count == 1 ? "1 override" : "\(plan.tax.overrides.count) overrides")
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

    /// A work phase's second line: "65.000 € gross · +1%/yr · TFR goes to: A
    /// pension fund", "Forfettario · 70.000 € revenue · Profitability
    /// coefficient 67%": the amounts, then the options its regime (the one
    /// chosen, else the default) describes and the plan sets.
    func detail(of phase: WorkPhase) -> String {
        var parts: [String] = []
        if let regime = phase.regime, let found = registry.regime(regime.rawValue), phase.kind != .employee {
            parts.append(PlanWorkText.shortRegimeName(found.regime.name))
        }
        switch phase.kind {
        case .employee:
            if let salary = phase.grossSalary { parts.append("\(amount(salary)) gross") }
        case .selfEmployed:
            if let revenue = phase.revenue { parts.append("\(amount(revenue)) revenue") }
            if let costs = phase.costs, costs > 0 { parts.append("\(amount(costs)) costs") }
        case .net:
            if let net = phase.netIncome { parts.append("\(amount(net)) net") }
        default:
            break
        }
        if let growth = phase.realGrowth, growth != 0 {
            parts.append("\(growth > 0 ? "+" : "")\(percent(growth))/yr")
        }
        let regime = PlanTaxChoices.effectiveRegimeID(for: phase, in: plan, settings: library.settings,
                                                      registry: registry)
        parts += PlanOptionForm.summary(phase.options, fields: PlanTaxChoices.regimeFields(regime, registry: registry),
                                        currency: currency, hidesAmounts: hidesAmounts, locale: locale)
        return parts.joined(separator: " · ")
    }

    /// A pension's second line: "Claimed as early as possible · Capital",
    /// "From 67 · 4.800 €/yr · State pension · from Germany".
    func detail(of pension: PlanPension) -> String {
        var parts: [String] = []
        if pension.scheme == .fixed {
            if let age = pension.fromAge { parts.append("From \(age)") }
            if let amount = pension.perYear { parts.append("\(self.amount(amount))/yr") }
        } else {
            switch pension.effectiveClaim {
            case .earliest: parts.append("Claimed as early as possible")
            case .age(let age): parts.append("Claimed at \(age)")
            }
        }
        if let route = pension.claimRoute {
            let routes = PlanPensionChoices.claimRoutes(for: pension, birthDate: library.settings.person?.birthDate,
                                                        today: .today(), registry: registry)
            parts.append(PlanPensionChoices.routeName(route, among: routes))
        }
        if let kind = pension.kind { parts.append(PlanPensionChoices.name(of: kind)) }
        if let country = pension.sourceCountry {
            parts.append("from \(CountryChoices.name(of: country, locale: locale))")
        }
        if pension.effectiveTaxedIn == .source { parts.append("taxed where it's paid") }
        return parts.joined(separator: " · ")
    }

    /// An event's second line: "+150.000 € · 80% likely", "−25.000 €".
    func detail(of event: PlanEvent) -> String {
        let sign = event.amount > 0 ? "+" : ""
        var text = hidesAmounts ? AmountFormat.hidden : sign + AmountFormat.amount(event.amount, currency: currency, locale: locale)
        if event.effectiveProbability < 1 { text += " · \(percent(event.effectiveProbability, digits: 0)) likely" }
        if event.kind == .inheritance { text += " · inheritance" }
        return text
    }

    /// A residence entry's line: "From 2026 · Italy".
    func title(of residence: PlanResidence) -> String {
        let name = registry.system(residence.system.rawValue)?.name ?? residence.system.rawValue
        return "From \(residence.from) · \(name)"
    }

    var withdrawals: String {
        let strategy = plan.withdrawals.effectiveStrategy == .fixedReal
            ? "Fixed real spending" : plan.withdrawals.effectiveStrategy.rawValue
        let buffer = plan.withdrawals.effectiveCashBuffer
        return buffer > 0 ? "\(strategy) · \(amount(buffer)) cash buffer" : strategy
    }
}

/// How work phases read in rows and summaries.
enum PlanWorkText {
    /// "Employee", "Self-employed", "Net income".
    static func kindName(_ kind: WorkKind) -> String {
        switch kind {
        case .employee: "Employee"
        case .selfEmployed: "Self-employed"
        case .net: "Net income"
        default: kind.rawValue
        }
    }

    /// A regime's name without "Regime": "Regime forfettario" → "Forfettario".
    static func shortRegimeName(_ name: String) -> String {
        let prefix = "Regime "
        guard name.hasPrefix(prefix), name.count > prefix.count else { return name }
        let rest = name.dropFirst(prefix.count)
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }

    /// The phase's regime by name if it chose one, else its kind: "Forfettario", "Employee".
    static func title(of phase: WorkPhase, registry: TaxRegistry) -> String {
        if let regime = phase.regime, let found = registry.regime(regime.rawValue) {
            return shortRegimeName(found.regime.name)
        }
        return kindName(phase.kind)
    }

    /// "2026–28", "2029–retirement".
    static func years(of phase: WorkPhase) -> String {
        PlanInputSummaries.years(from: phase.from.year, until: phase.until.date?.year)
    }
}
