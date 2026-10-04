import Foundation
import Model
import TaxKit

/// Turns a plan file, the library and the registered tax systems into a
/// ``PlanModel``: resolves the residence timeline, overlays and regimes,
/// converts options and amounts to TaxKit's types, builds the starting
/// portfolio, and runs the engine's and every tax system's validation.
enum PlanInterpreter {
    /// The highest end age a plan can have.
    static let maximumEndAge = 120
    /// The most Monte Carlo runs a plan can have.
    static let maximumRuns = 10_000
    /// The yearly inflation a plan can assume.
    static let inflationRange = -0.5...0.5
    /// The most uncertain events (windfalls or expenses) one year can have.
    static let maximumUncertainEventsPerYear = 8

    /// The model, or `nil` when there are errors; and every issue found.
    static func interpret(plan: PlanDocument, library: Library, registry: TaxRegistry,
                          options: PlannerOptions) -> (model: PlanModel?, issues: [PlanIssue]) {
        var issues: [PlanIssue] = []

        // The person and the dates.
        guard let birthDate = library.settings.person?.birthDate else {
            issues.append(.error("planner.noBirthDate", "The plan needs your birth date (library settings).",
                                 section: .person))
            return (nil, issues)
        }
        let startDate: CalendarDate
        switch plan.portfolio.effectiveStart {
        case .date(let date):
            startDate = date
        case .latestCheckIn:
            if let latest = library.latestCheckInDate {
                startDate = latest
            } else {
                startDate = options.today ?? .today()
                issues.append(.warning("planner.noCheckIn", "There is no check-in yet; the plan starts from nothing today.",
                                       section: .portfolio))
            }
        }
        let currentAge = birthDate.wholeYears(to: startDate)
        let endAge = plan.effectiveEndAge
        guard endAge <= Self.maximumEndAge else {
            issues.append(.error("planner.endAge", "The plan's end age (\(endAge)) can be at most \(Self.maximumEndAge).",
                                 section: .retirement, option: "endAge"))
            return (nil, issues)
        }
        guard endAge > currentAge else {
            issues.append(.error("planner.endAge", "The plan's end age (\(endAge)) must be after your age today (\(currentAge)).",
                                 section: .retirement, option: "endAge"))
            return (nil, issues)
        }
        let planAge = plan.retirement.age.age
        if let planAge, planAge >= endAge {
            issues.append(.error("planner.retirementAge", "The retirement age must be before the end age.",
                                 section: .retirement, option: "age"))
        }
        let firstYear = startDate == .lastDay(of: startDate.year) ? startDate.year + 1 : startDate.year
        let lastYear = birthDate.year + endAge
        let currency = plan.effectiveCurrency(base: library.settings.baseCurrency)
        var rates = CurrencyRates(planCurrency: currency, date: startDate, library: library)
        let citizenships = (library.settings.person?.citizenships ?? []).map { $0.rawValue.uppercased() }

        // The residence timeline.
        let inflation = plan.assumptions.effectiveInflation.double
        if !Self.inflationRange.contains(inflation) {
            issues.append(.error("planner.inflation", "Inflation must be between -50% and 50% a year.",
                                 section: .assumptions, option: "inflation"))
        }
        let overrides = OptionValues(plan.tax.overrides)
        var residence = plan.tax.residence.sorted { $0.from < $1.from }
        if residence.isEmpty {
            if let system = Planner.defaultTaxSystem(for: library.settings, registry: registry) {
                residence = [PlanResidence(from: firstYear, system: TaxSystemID(system.id))]
                issues.append(.warning("planner.defaultResidence",
                                       "The plan has no tax residence; it uses \(system.name).",
                                       section: .tax))
            } else {
                issues.append(.error("planner.noTaxSystem", "No tax system is available.", section: .tax))
                return (nil, issues)
            }
        }
        var systems: [SystemContext] = []
        var entrySystem: [Int] = []
        for (index, entry) in residence.enumerated() {
            guard let system = registry.system(entry.system.rawValue) else {
                issues.append(.error("planner.unknownSystem", "There is no tax system \"\(entry.system)\".",
                                     section: .tax, index: index))
                continue
            }
            if let existing = systems.firstIndex(where: { $0.id == system.id }) {
                entrySystem.append(existing)
            } else {
                systems.append(SystemContext(system: system,
                                             parameters: OverriddenParameterStore(base: system.parameters,
                                                                                  overrides: overrides),
                                             currencyRate: rates.rate(for: system, issues: &issues)))
                entrySystem.append(systems.count - 1)
            }
        }
        guard entrySystem.count == residence.count else { return (nil, issues) }
        let timeline = zip(residence, entrySystem).map { entry, s in
            TaxPlan.Residence(from: entry.from, system: systems[s].id, options: OptionValues(entry.options))
        }

        // Year frames.
        var frames: [YearFrame] = []
        var taxParameters: [String: Int] = [:]
        var failedSystems: Set<String> = []
        // Years simulated before each one: prices at its start are (1 + i)^elapsed
        // of today's, so a partial first year counts as its share, as in `inflationStep`.
        var elapsed = 0.0
        for year in firstYear...lastYear {
            let simulatedFrom = max(CalendarDate.firstDay(of: year), startDate.adding(days: 1))
            let daysInYear = CalendarDate.isLeapYear(year) ? 366 : 365
            let fraction = Double(CalendarDate.inclusiveDays(from: simulatedFrom, to: .lastDay(of: year)))
                / Double(daysInYear)
            let yearsBefore = elapsed
            elapsed += fraction
            let entry = residence.lastIndex { $0.from <= year } ?? 0
            let context = systems[entrySystem[entry]]
            let parameters: ParameterSet
            do {
                parameters = try context.parameters.parameters(for: year)
            } catch {
                if failedSystems.insert(context.id).inserted {
                    issues.append(.error("planner.noParameters", "\(error)", section: .tax, year: year))
                }
                continue
            }
            if let parameterYear = context.parameters.parameterYear(for: year) {
                taxParameters[context.id] = max(taxParameters[context.id] ?? parameterYear, parameterYear)
            }
            frames.append(YearFrame(
                index: frames.count, year: year, age: year - birthDate.year, daysInYear: daysInYear,
                simulatedFrom: simulatedFrom, fraction: fraction, system: entrySystem[entry], parameters: parameters,
                systemOptions: OptionValues(residence[entry].options),
                inflationFactor: pow(1 + inflation, yearsBefore),
                inflationStep: pow(1 + inflation, fraction), currencyRate: context.currencyRate))
        }

        // Overlays and work.
        var overlays: [RegimeChoice] = []
        for (index, overlay) in plan.tax.overlays.enumerated() {
            guard let found = registry.regime(overlay.regime.rawValue) else {
                issues.append(.error("planner.unknownRegime", "There is no regime \"\(overlay.regime)\".",
                                     section: .tax, index: index, regime: overlay.regime.rawValue))
                continue
            }
            if found.regime.scope != .overlay {
                issues.append(.error("planner.notOverlay", "\(found.regime.name) is chosen per work phase, not as a special regime.",
                                     section: .tax, index: index, regime: overlay.regime.rawValue))
            }
            overlays.append(RegimeChoice(regime: overlay.regime.rawValue, options: OptionValues(overlay.options)))
        }
        let work = interpretWork(plan.work, firstYear: firstYear, registry: registry, issues: &issues)

        // Spending.
        var spending = SpendingSpec(
            working: plan.spending.working.double, retired: plan.spending.retired.double,
            phases: plan.spending.phases.sorted { $0.fromAge < $1.fromAge }
                .map { SpendingPhaseSpec(fromAge: $0.fromAge, factor: $0.factor.double) })
        if spending.working < 0 || spending.retired < 0 || spending.phases.contains(where: { $0.factor < 0 }) {
            issues.append(.error("planner.negativeSpending", "Spending can't be negative.", section: .spending))
        }
        if let rule = plan.spending.flexibleRule {
            let problems = Self.flexibleSpendingProblems(rule)
            for problem in problems {
                issues.append(.error("planner.flexibleSpending", problem, section: .spending, option: "flexible"))
            }
            if problems.isEmpty { spending.flexible = FlexibleSpendingSpec(rule) }
        }

        var pensions = interpretPensions(plan.pensions, registry: registry, overrides: overrides, issues: &issues)
        // A scheme of a system with its own currency gets that system's rate;
        // the shared `fixed` scheme works in the plan's currency.
        for index in pensions.indices where !pensions[index].isFixed {
            if let owner = pensions[index].ownerID.flatMap({ registry.system($0) }) {
                pensions[index].currencyRate = rates.rate(for: owner, issues: &issues)
            }
        }
        // The paying countries' systems, for pensions taxed at source (G8).
        var nonResident: [NonResidentSystem] = []
        for pension in pensions where pension.taxedIn == .source {
            guard let country = pension.sourceCountry, !nonResident.contains(where: { $0.country == country }),
                  let system = registry.system(forCountry: country) else { continue }
            nonResident.append(NonResidentSystem(
                system: system, country: country,
                parameters: OverriddenParameterStore(base: system.parameters, overrides: overrides),
                currencyRate: rates.rate(for: system, issues: &issues)))
        }

        // The starting portfolio. Accounts that hold a pension scheme's record
        // (its seed wrapper) start the scheme instead of being a bucket.
        var seedWrappers: [String: String] = [:]
        for pension in pensions where !pension.isFixed {
            if let wrapper = pension.scheme.seedWrapper, seedWrappers[wrapper] == nil {
                seedWrappers[wrapper] = pension.schemeID
            }
        }
        let portfolio = PortfolioBuilder(library: library, date: startDate, plan: plan, registry: registry,
                                         residence: systems.first?.system, currency: currency,
                                         seedWrappers: seedWrappers, issues: &issues)
        seed(&pensions, from: portfolio.seeds, registry: registry, issues: &issues)
        checkTargetMixSteps(plan.portfolio.targetMixByAge, endAge: endAge, issues: &issues)

        let contributions = interpretContributions(plan.contributions, portfolio: portfolio, pensions: pensions,
                                                   library: library, registry: registry, years: firstYear...lastYear,
                                                   issues: &issues)

        // Events.
        var events: [EventSpec] = []
        var probabilities: [Double] = []
        for (index, event) in plan.events.enumerated() {
            let year = switch event.timing {
            case .age(let age): birthDate.year + age
            case .year(let year): year
            }
            guard (firstYear...lastYear).contains(year) else {
                issues.append(.warning("planner.eventOutside", "\(event.name) falls outside the plan's years; it's ignored.",
                                       section: .events, index: index, year: year))
                continue
            }
            let probability = min(1, max(0, event.effectiveProbability.double))
            var bit: Int?
            if probability < 1 {
                if probabilities.count < 64 {
                    bit = probabilities.count
                    probabilities.append(probability)
                } else {
                    issues.append(.warning("planner.tooManyUncertainEvents",
                                           "Only 64 events can be uncertain; \(event.name) is treated as certain if likely.",
                                           section: .events, index: index))
                }
            }
            if bit == nil, probability < 0.5 { continue }
            events.append(EventSpec(index: index, name: event.name, year: year, amount: event.amount.double,
                                    probability: probability, kind: event.effectiveKind.rawValue, bit: bit))
        }
        // Each combination of a year's uncertain windfalls is prepared on its
        // own (2^n of them), so a year can only have a few.
        let uncertainByYear = Dictionary(grouping: events.filter { $0.bit != nil }, by: \.year)
        for (year, uncertain) in uncertainByYear.sorted(by: { $0.key < $1.key })
        where uncertain.count > Self.maximumUncertainEventsPerYear {
            issues.append(.error("planner.uncertainEventsInYear",
                                 "\(year) has \(uncertain.count) uncertain events; at most "
                                     + "\(Self.maximumUncertainEventsPerYear) in one year can be uncertain.",
                                 section: .events, index: uncertain[Self.maximumUncertainEventsPerYear].index,
                                 year: year))
        }

        // Returns and the simulation settings.
        let returns = ReturnModel(assumptions: plan.assumptions, heldClasses: portfolio.classes, issues: &issues)
        let incomeYields = portfolio.classes.map { assetClass -> Double in
            guard let yield = plan.assumptions.returnAssumption(for: assetClass)?.incomeYield?.double else { return 0 }
            if !(0...1).contains(yield) {
                issues.append(.error("planner.incomeYield", "The income yield of \(assetClass) must be between 0 and 100%.",
                                     section: .assumptions, option: "incomeYield"))
            }
            return min(1, max(0, yield))
        }
        if returns.expected.contains(where: { $0 <= -1 })
            || plan.assumptions.returns.values.contains(where: { $0.isGivenByMedian && ($0.medianReal ?? 0) <= -1 }) {
            issues.append(.error("planner.returnTooLow", "A real return must be above -100%.", section: .assumptions))
        }
        let confidence = plan.simulation.effectiveConfidence.double
        if !(confidence > 0 && confidence <= 1) {
            issues.append(.error("planner.confidence", "The confidence level must be between 0 and 100%.",
                                 section: .simulation, option: "confidence"))
        }
        if plan.simulation.effectiveRuns < 1 {
            issues.append(.error("planner.runs", "The plan needs at least one run.", section: .simulation,
                                 option: "runs"))
        } else if plan.simulation.effectiveRuns > Self.maximumRuns {
            issues.append(.error("planner.runs", "A plan can have at most 10,000 runs.", section: .simulation,
                                 option: "runs"))
        }

        // The tax systems' own validation.
        let lastWorkingYear = planAge.map { max(startDate, birthDate.adding(years: $0)).adding(days: -1).year }
        for (index, context) in systems.enumerated() {
            let years = frames.filter { $0.system == index }.map(\.year)
            guard let first = years.min(), let last = years.max() else { continue }
            let taxPlan = TaxPlan(
                residence: timeline,
                overlays: overlays.filter { context.system.regime($0.regime) != nil },
                indexThresholds: plan.tax.effectiveIndexThresholds,
                overrides: overrides,
                work: work.compactMap { phase in
                    // Retiring ends every phase, whatever its `until`.
                    let untilYear = [phase.until?.year, lastWorkingYear].compactMap { $0 }.min()
                    // A phase that ends before it starts (an `until` before `from`, which
                    // is an error above, or a retirement before the phase begins) never
                    // happens, so the tax systems don't see it.
                    let fromYear = max(phase.from.year, first)
                    guard phase.from.year <= last, (untilYear ?? last) >= fromYear else { return nil }
                    if let regime = phase.regime, context.system.regime(regime) == nil {
                        issues.append(.warning("planner.regimeNotInSystem",
                                               "\(regime) doesn't exist in \(context.system.name); that system's default applies.",
                                               section: .work, index: phase.index, regime: regime))
                    }
                    return TaxPlan.WorkPhase(id: phase.id, kind: phase.kind, regime: phase.regime(in: context.system),
                                             options: phase.options, fromYear: fromYear,
                                             untilYear: untilYear.map { min($0, last) })
                },
                pensions: pensions.filter { $0.isFixed || context.system.pensionScheme($0.schemeID) != nil }
                    .map { TaxPlan.Pension(id: $0.id, scheme: $0.schemeID, options: $0.options, kind: $0.kind,
                                           sourceCountry: $0.sourceCountry) },
                birthYear: birthDate.year, citizenships: citizenships)
            systems[index].taxPlan = taxPlan
            // Checks that need each year's amounts come later, from the prepared
            // years of a retirement age (`PlanModel.yearIssues(for:)`).
            for issue in context.system.validate(taxPlan, parameters: context.parameters) {
                issues.append(PlanIssue(issue, section: section(of: issue, registry: registry)))
            }
        }

        // The old-age pension age behind wrapper access rules, in whole years
        // and in months: the plan's schemes first (with their options), then
        // the residence system's.
        let oldAgePensionAges = frames.map { frame -> (years: Int, months: Int?)? in
            for pension in pensions {
                if let age = pension.scheme.oldAgePensionAge(in: frame.year, options: pension.options,
                                                             parameters: pension.schemeParameters) {
                    return (age, pension.scheme.oldAgePensionAgeInMonths(in: frame.year, options: pension.options,
                                                                          parameters: pension.schemeParameters))
                }
            }
            let residence = systems[frame.system]
            for scheme in residence.system.pensionSchemes {
                if let age = scheme.oldAgePensionAge(in: frame.year, options: [:], parameters: residence.parameters) {
                    return (age, scheme.oldAgePensionAgeInMonths(in: frame.year, options: [:],
                                                                 parameters: residence.parameters))
                }
            }
            return nil
        }

        guard !issues.contains(where: \.isError) else { return (nil, issues) }
        let model = PlanModel(
            plan: plan, registry: registry, currency: currency, birthDate: birthDate, citizenships: citizenships,
            residence: timeline, startDate: startDate, currentAge: currentAge,
            endAge: endAge, planAge: planAge, frames: frames, systems: systems, nonResidentSystems: nonResident,
            oldAgePensionAges: oldAgePensionAges.map { $0?.years },
            oldAgePensionAgesInMonths: oldAgePensionAges.map { $0?.months }, overlays: overlays,
            indexThresholds: plan.tax.effectiveIndexThresholds, inflation: inflation, work: work, spending: spending,
            pensions: pensions, contributions: contributions, events: events, incomeYields: incomeYields,
            uncertainEventProbabilities: probabilities, portfolio: portfolio, returns: returns,
            cashBuffer: max(0, plan.withdrawals.effectiveCashBuffer.double),
            runs: options.runs(planRuns: plan.simulation.effectiveRuns), seed: plan.simulation.effectiveSeed,
            confidence: confidence, issues: issues, taxParameters: taxParameters)
        return (model, issues)
    }

    // MARK: - Sections

    /// What's wrong with a flexible-spending rule's settings, as messages:
    /// the cut must be more than 0% and at most 100% of the plan's
    /// spending, the floor between 0% and 100%, the upper guardrail at
    /// least 0% and the lower one between 0% and 100%.
    static func flexibleSpendingProblems(_ rule: FlexibleSpending) -> [String] {
        var problems: [String] = []
        let cut = rule.effectiveCut
        if cut <= 0 || cut > 1 {
            problems.append("Flexible spending's cut must be more than 0% and at most 100% of the plan's spending.")
        }
        let floor = rule.effectiveFloor
        if floor < 0 || floor > 1 {
            problems.append("Flexible spending's floor must be between 0% and 100% of the plan's spending.")
        }
        if rule.effectiveUpperGuardrail < 0 {
            problems.append("Flexible spending's upper guardrail can't be negative.")
        }
        let lower = rule.effectiveLowerGuardrail
        if lower < 0 || lower > 1 {
            problems.append("Flexible spending's lower guardrail must be between 0% and 100%.")
        }
        return problems
    }

    /// The ages of the target mix steps (`portfolio.targetMixByAge`; their
    /// mixes are checked with the portfolio): ages must go up in the list,
    /// a step after the plan's end never applies, and of two `retirement`
    /// steps only the later can. A step at or before today's age applies
    /// from the start, which needs no message.
    static func checkTargetMixSteps(_ steps: [TargetMixStep], endAge: Int, issues: inout [PlanIssue]) {
        var previous: Int?
        var lastRetirement: Int?
        for (index, step) in steps.enumerated() {
            switch step.fromAge {
            case .age(let age):
                if let previous, age <= previous {
                    issues.append(.error("planner.targetMixAges",
                                         "The target mix's ages must go up: \(age) comes after \(previous).",
                                         section: .portfolio, index: index, option: "targetMixByAge"))
                }
                if age > endAge {
                    issues.append(.warning("planner.targetMixLate",
                                           "The target mix from \(age) starts after the plan's end at \(endAge); "
                                               + "it never applies.",
                                           section: .portfolio, index: index, option: "targetMixByAge"))
                }
                previous = max(previous ?? age, age)
            case .retirement:
                if let earlier = lastRetirement {
                    issues.append(.warning("planner.targetMixRepeated",
                                           "Two target mixes start at retirement; only the later one applies.",
                                           section: .portfolio, index: earlier, option: "targetMixByAge"))
                }
                lastRetirement = index
            }
        }
    }

    private static func interpretWork(_ phases: [WorkPhase], firstYear: Int, registry: TaxRegistry,
                                      issues: inout [PlanIssue]) -> [WorkSpec] {
        var result: [WorkSpec] = []
        for (index, phase) in phases.enumerated() {
            let kind = EarnedIncomeKind(rawValue: phase.kind.rawValue)
            var gross = 0.0
            var net: Double?
            var label: String
            switch phase.kind {
            case .employee:
                label = "Employee"
                guard let salary = phase.grossSalary else {
                    issues.append(.error("planner.missingAmount", "An employee phase needs grossSalary.",
                                         section: .work, index: index, option: "grossSalary"))
                    continue
                }
                gross = salary.double
            case .selfEmployed:
                label = "Self-employed"
                guard let revenue = phase.revenue else {
                    issues.append(.error("planner.missingAmount", "A self-employed phase needs revenue.",
                                         section: .work, index: index, option: "revenue"))
                    continue
                }
                gross = revenue.double
            case .net:
                label = "Net income"
                guard let income = phase.netIncome else {
                    issues.append(.error("planner.missingAmount", "A net phase needs netIncome.",
                                         section: .work, index: index, option: "netIncome"))
                    continue
                }
                net = income.double
            default:
                issues.append(.error("planner.unknownWorkKind", "There is no kind of work \"\(phase.kind)\".",
                                     section: .work, index: index))
                continue
            }
            if let regime = phase.regime?.rawValue {
                if let found = registry.regime(regime) {
                    label = found.regime.name
                    if !found.regime.scope.applies(to: kind) {
                        issues.append(.error("planner.regimeKind",
                                             "\(found.regime.name) doesn't apply to \(phase.kind) work.",
                                             section: .work, index: index, regime: regime))
                    }
                } else {
                    issues.append(.error("planner.unknownRegime", "There is no regime \"\(regime)\".",
                                         section: .work, index: index, regime: regime))
                }
            }
            if let until = phase.until.date, until < phase.from {
                issues.append(.error("planner.phaseDates", "A work phase can't end before it starts.",
                                     section: .work, index: index, option: "until"))
            }
            result.append(WorkSpec(
                index: index, id: "work-\(index)", kind: kind, regime: phase.regime?.rawValue,
                options: OptionValues(phase.options), from: phase.from, until: phase.until.date, gross: gross,
                costs: phase.costs?.double ?? 0, net: net, realGrowth: phase.realGrowth?.double ?? 0,
                baseYear: max(phase.from.year, firstYear), label: label))
        }
        return result
    }

    private static func interpretPensions(_ pensions: [PlanPension], registry: TaxRegistry, overrides: OptionValues,
                                          issues: inout [PlanIssue]) -> [PensionSpec] {
        var result: [PensionSpec] = []
        var schemes: Set<String> = []
        for (index, pension) in pensions.enumerated() {
            let id = "pension-\(index)"
            let taxedIn: FixedYear.TaxedIn = pension.effectiveTaxedIn == .source ? .source : .residence
            let planKind = pension.kind.map { PensionKind(rawValue: $0.rawValue) }
            let schemeOwner = registry.systems.first { $0.pensionScheme(pension.scheme.rawValue) != nil }
            // The paying country: the plan's, else the country of the system whose scheme it is.
            let sourceCountry = pension.sourceCountry?.rawValue.uppercased()
                ?? (pension.scheme.rawValue == FixedPensionScheme.schemeID ? nil : schemeOwner?.country?.uppercased())
            // A pension taxed by a country the plan has a system for is taxed by
            // it (TaxSystem.prepareNonResident); otherwise it's left untaxed.
            if taxedIn == .source, sourceCountry.flatMap({ registry.system(forCountry: $0) }) == nil {
                issues.append(.warning("planner.taxedAtSource",
                                       "\(pension.name ?? pension.scheme.rawValue) is taxed by the paying country, which "
                                           + "the plan doesn't compute; enter it after that tax.",
                                       section: .pensions, index: index, option: "taxedIn"))
            }
            if pension.scheme.rawValue == FixedPensionScheme.schemeID {
                guard let fromAge = pension.fromAge, let perYear = pension.perYear else {
                    issues.append(.error("planner.fixedPension", "A fixed pension needs fromAge and perYear.",
                                         section: .pensions, index: index))
                    continue
                }
                // TaxKit's shared scheme reads the entry's top-level keys as options.
                var options = OptionValues(pension.options)
                options["fromAge"] = .number(Double(fromAge))
                options["perYear"] = .number(perYear.double)
                let owner = registry.systems.first { $0.pensionScheme(FixedPensionScheme.schemeID) != nil }
                    ?? registry.systems.first
                let parameters: any ParameterStore = owner.map {
                    OverriddenParameterStore(base: $0.parameters, overrides: overrides)
                } ?? NoParameters(system: FixedPensionScheme.schemeID)
                let scheme = owner?.pensionScheme(FixedPensionScheme.schemeID) ?? FixedPensionScheme()
                result.append(PensionSpec(
                    index: index, id: id, name: pension.name ?? "Pension", schemeID: FixedPensionScheme.schemeID,
                    scheme: scheme, schemeParameters: parameters, claim: pension.claim ?? .age(fromAge),
                    taxedIn: taxedIn, options: options, claimRoute: pension.claimRoute,
                    kind: planKind ?? scheme.pensionKind(options: options), sourceCountry: sourceCountry,
                    ownerID: owner?.id))
                continue
            }
            guard let owner = schemeOwner, let scheme = owner.pensionScheme(pension.scheme.rawValue) else {
                issues.append(.error("planner.unknownScheme", "There is no pension scheme \"\(pension.scheme)\".",
                                     section: .pensions, index: index))
                continue
            }
            if !schemes.insert(scheme.id).inserted {
                issues.append(.warning("planner.duplicateScheme",
                                       "\(scheme.name) appears twice; work credits count toward both.",
                                       section: .pensions, index: index))
            }
            let options = OptionValues(pension.options)
            result.append(PensionSpec(
                index: index, id: id, name: pension.name ?? scheme.name, schemeID: scheme.id, scheme: scheme,
                schemeParameters: OverriddenParameterStore(base: owner.parameters, overrides: overrides),
                claim: pension.effectiveClaim, taxedIn: taxedIn, options: options, claimRoute: pension.claimRoute,
                kind: planKind ?? scheme.pensionKind(options: options), sourceCountry: sourceCountry,
                ownerID: owner.id))
        }
        return result
    }

    /// Gives each pension scheme the value of the accounts that seed it, as
    /// its option `startingBalance` (unless the plan sets it): the first
    /// pension with the scheme gets it.
    private static func seed(_ pensions: inout [PensionSpec], from seeds: [PortfolioBuilder.Seed],
                             registry: TaxRegistry, issues: inout [PlanIssue]) {
        for seed in seeds {
            guard let index = pensions.firstIndex(where: { $0.schemeID == seed.scheme }) else { continue }
            if pensions[index].options["startingBalance"] != nil {
                issues.append(.warning("planner.seedReplaced",
                                       "\(pensions[index].name) sets startingBalance, so the value of "
                                           + "\(seed.accounts.map(\.rawValue).joined(separator: ", ")) isn't used.",
                                       section: .pensions, index: pensions[index].index, option: "startingBalance"))
            } else {
                pensions[index].options["startingBalance"] = .number(seed.value)
            }
        }
    }

    /// The plan's contributions: into an account's bucket, or into a
    /// pension scheme; yearly while working, or once.
    private static func interpretContributions(
        _ entries: [PlanContribution], portfolio: PortfolioBuilder, pensions: [PensionSpec], library: Library,
        registry: TaxRegistry, years: ClosedRange<Int>, issues: inout [PlanIssue]
    ) -> [ContributionSpec] {
        var result: [ContributionSpec] = []
        for (index, contribution) in entries.enumerated() {
            if contribution.pension != nil, !contribution.account.rawValue.isEmpty {
                issues.append(.error("planner.contributionTarget",
                                     "A contribution goes into an account or a pension scheme, not both.",
                                     section: .contributions, index: index))
                continue
            }
            var oneOff: (year: Int, amount: Double)?
            switch (contribution.amount, contribution.year) {
            case (let amount?, let year?):
                if contribution.perYear != 0 {
                    issues.append(.error("planner.contributionAmount",
                                         "A contribution is paid every year (perYear) or once (amount), not both.",
                                         section: .contributions, index: index, option: "amount"))
                    continue
                }
                guard years.contains(year) else {
                    issues.append(.warning("planner.contributionOutside",
                                           "A contribution in \(year) falls outside the plan's years; it's ignored.",
                                           section: .contributions, index: index, year: year))
                    continue
                }
                oneOff = (year, amount.double)
            case (nil, nil):
                break
            default:
                issues.append(.error("planner.contributionYear", "A one-off contribution needs an amount and a year.",
                                     section: .contributions, index: index, option: "year"))
                continue
            }
            let until = contribution.effectiveUntil.date
            if let scheme = contribution.pension?.rawValue {
                guard registry.pensionScheme(scheme) != nil else {
                    issues.append(.warning("planner.contributionScheme",
                                           "There is no pension scheme \"\(scheme)\"; its contributions stay in your savings.",
                                           section: .contributions, index: index, option: "pension"))
                    continue
                }
                if !pensions.contains(where: { $0.schemeID == scheme }) {
                    issues.append(.warning("planner.contributionWithoutPension",
                                           "Contributions go into \(scheme), but the plan has no \(scheme) pension to "
                                               + "claim them.",
                                           section: .contributions, index: index, option: "pension"))
                }
                result.append(ContributionSpec(index: index, wrapper: scheme, isScheme: true,
                                               perYear: contribution.perYear.double, until: until, oneOff: oneOff))
                continue
            }
            guard let bucket = portfolio.buckets.first(where: { $0.accounts.contains(contribution.account) }) else {
                let reason = portfolio.seeds.contains(where: { $0.accounts.contains(contribution.account) })
                    ? "holds a pension scheme's record"
                    : library.accounts[contribution.account] == nil ? "doesn't exist" : "isn't in the plan"
                issues.append(.warning("planner.contributionAccount",
                                       "The account \(contribution.account) \(reason); its contributions stay in your savings.",
                                       section: .contributions, index: index, account: contribution.account))
                continue
            }
            result.append(ContributionSpec(index: index, wrapper: bucket.wrapper, isScheme: false,
                                           perYear: contribution.perYear.double, until: until, oneOff: oneOff))
        }
        return result
    }

    /// The plan section a tax system's issue belongs on.
    static func section(of issue: TaxIssue, registry: TaxRegistry) -> PlanSection {
        guard let regime = issue.regime.flatMap({ registry.regime($0)?.regime }) else { return .tax }
        return regime.scope == .overlay ? .tax : .work
    }
}

/// Stands in for a scheme's parameters when no tax system is registered.
private struct NoParameters: ParameterStore {
    let system: String
    var years: [Int] { [] }

    func parameters(for year: Int) throws -> ParameterSet {
        throw ParameterError.noParameters(system: system)
    }
}
