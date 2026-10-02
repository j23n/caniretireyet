import TaxKit

/// Checks a plan against the Swiss rules that don't need its amounts: the
/// shared checks (unknown IDs, regime scope and years, options, overrides),
/// the canton and commune, the tariff, the permit, the home options, the
/// overlays' conditions, and treaty notes on foreign pensions. Checks that
/// need amounts (3a limits, buy-ins) run year by year in `prepare`.
struct SwissValidator {
    let system: SwissTaxSystem
    let plan: TaxPlan
    let parameters: any ParameterStore

    func issues() -> [TaxIssue] {
        // The canton and commune get messages that say what's supported.
        var issues = system.commonIssues(for: plan).filter {
            !($0.code == "\(system.id).options.invalidChoice" && ($0.option == "canton" || $0.option == "commune"))
        }
        let periods = system.residencePeriods(in: plan)
        guard let first = periods.first?.lowerBound else { return issues }
        let p: SwissParameters
        do {
            p = try system.parsed.parameters(for: try parameters.parameters(for: first))
        } catch {
            issues.append(.error("ch.parameters", "The Swiss tax parameters can't be used: \(error)", year: first))
            return issues
        }
        issues += residenceIssues(p, periods: periods)
        issues += lumpSumIssues(p, periods: periods)
        issues += expatriateIssues(p, periods: periods)
        issues += pensionIssues()
        return issues
    }

    private var citizenships: [String] { plan.citizenships.map { $0.uppercased() } }
    private var isSwiss: Bool { citizenships.contains("CH") }

    /// The residence entries in Switzerland, with the last year of each.
    private func entries(_ periods: [ClosedRange<Int>]) -> [(entry: TaxPlan.Residence, last: Int)] {
        plan.residence.filter { $0.system == system.id }.compactMap { entry in
            periods.first { $0.contains(entry.from) }.map { (entry, $0.upperBound) }
        }
    }

    private func residenceIssues(_ p: SwissParameters, periods: [ClosedRange<Int>]) -> [TaxIssue] {
        var issues: [TaxIssue] = []
        for (entry, last) in entries(periods) {
            let options = entry.options.withDefaults(from: system.options)
            if case .failure(let problem) = SwissPlace.resolve(options, parameters: p) {
                if case .missingCanton = problem {} else {
                    issues.append(problem.issue(supported: Array(p.cantons.values), year: entry.from))
                }
            }
            if options.string("tariff") == "married" {
                issues.append(.error(
                    "ch.tariff.married",
                    "The married tariffs aren't available: the federal and Zurich ones aren't in the parameter file, "
                        + "and the planner models one person. Use the single tariff.", year: entry.from, option: "tariff"))
            }
            if !citizenships.isEmpty && !isSwiss && entry.options["permit"] == nil {
                issues.append(.warning(
                    "ch.permit.missing",
                    "Without Swiss citizenship you live in Switzerland on a permit: choose B or C (it only changes the "
                        + "messages).", year: entry.from, option: "permit"))
            }
            if options.string("permit") == "B" && hasSalary(from: entry.from, until: last) {
                issues.append(.warning(
                    "ch.permit.sourceTax",
                    "On a B permit, salary is taxed at source. An ordinary assessment follows from a salary of "
                        + "\(francs(p.ordinaryAssessmentFromSalary)), or with other income or wealth, or on request; "
                        + "the estimate always uses it, which is what's finally due with 3a, buy-ins or investments.",
                    year: entry.from, option: "permit"))
            }
            let homeIncome = (options.double("imputedRentalValue") ?? 0) > 0
                || (options.double("mortgageInterest") ?? 0) > 0
            if homeIncome && last > p.imputedRentLastYear {
                issues.append(.warning(
                    "ch.property.imputedRentEnds",
                    "The imputed rental value and the mortgage-interest deduction end after \(p.imputedRentLastYear); "
                        + "from \(p.imputedRentLastYear + 1) they're left out.", year: p.imputedRentLastYear + 1,
                    option: "imputedRentalValue"))
            }
        }
        return issues
    }

    /// Whether the plan has an employee phase while resident in Switzerland between `from` and `until`.
    private func hasSalary(from: Int, until: Int) -> Bool {
        plan.work.contains { phase in
            phase.kind == .employee
                && phase.fromYear <= until && (phase.untilYear ?? Int.max) >= from
                && !system.residenceYears(in: plan, from: max(phase.fromYear, from),
                                          until: min(phase.untilYear ?? Int.max, until)).isEmpty
        }
    }

    private func lumpSumIssues(_ p: SwissParameters, periods: [ClosedRange<Int>]) -> [TaxIssue] {
        var issues: [TaxIssue] = []
        let regime = SwissRegime.lumpSum
        for overlay in plan.overlays where overlay.regime == regime {
            guard let firstYear = overlay.options.int("firstYear") else { continue }
            let covered = entries(periods).filter { $0.last >= firstYear }
            if covered.isEmpty {
                issues.append(.warning("ch.lumpSum.noYears", "Lump-sum taxation from \(firstYear) covers no year the plan "
                                       + "spends resident in Switzerland.", regime: regime))
                continue
            }
            for (entry, _) in covered {
                guard let code = entry.options.string("canton"), let canton = p.cantons[code], !canton.lumpSumAvailable
                else { continue }
                let offered = p.cantons.values.filter(\.lumpSumAvailable).map(\.name).sorted()
                issues.append(.error(
                    "ch.lumpSum.canton",
                    "\(canton.name) has abolished lump-sum taxation; of the cantons offered, only "
                        + "\(offered.joined(separator: " and ")) has it.", year: max(entry.from, firstYear),
                    regime: regime))
            }
            if isSwiss {
                issues.append(.error("ch.lumpSum.citizenship",
                                     "Lump-sum taxation is only for people without Swiss citizenship.", regime: regime))
            } else if citizenships.isEmpty {
                issues.append(.error("ch.lumpSum.citizenship",
                                     "Lump-sum taxation is only for people without Swiss citizenship: set the person's "
                                         + "citizenships.", regime: regime))
            }
            for phase in plan.work where phase.kind == .employee || phase.kind == .selfEmployed {
                let years = system.residenceYears(in: plan, from: max(phase.fromYear, firstYear), until: phase.untilYear)
                if let year = years.first?.lowerBound {
                    issues.append(.error("ch.lumpSum.earnedIncome",
                                         "Lump-sum taxation excludes work in Switzerland, and the plan works there in "
                                             + "\(year).", year: year, regime: regime))
                }
            }
            if plan.residence(in: firstYear - 1)?.system == system.id {
                issues.append(.error("ch.lumpSum.firstYear",
                                     "Lump-sum taxation starts with Swiss residence (the first year, or after 10 years "
                                         + "away), and the plan already lives in Switzerland in \(firstYear - 1).",
                                     year: firstYear, regime: regime, option: "firstYear"))
            }
        }
        return issues
    }

    private func expatriateIssues(_ p: SwissParameters, periods: [ClosedRange<Int>]) -> [TaxIssue] {
        var issues: [TaxIssue] = []
        let regime = SwissRegime.expatriate
        for overlay in plan.overlays where overlay.regime == regime {
            guard let start = overlay.options.int("assignmentStart") else { continue }
            let last = start + p.expatriateYears - 1
            let employed = plan.work.contains { phase in
                phase.kind == .employee
                    && !system.residenceYears(in: plan, from: max(phase.fromYear, start),
                                              until: min(phase.untilYear ?? Int.max, last)).isEmpty
            }
            if !employed {
                issues.append(.warning(
                    "ch.expatriate.noEmployment",
                    "Expatriate deductions apply to employees on an assignment in Switzerland in \(start)–\(last), and "
                        + "the plan has no such work: they don't apply.", year: start, regime: regime))
            }
        }
        return issues
    }

    /// An Italian public-service pension stays taxable in Italy for an
    /// Italian citizen (treaty Art. 19); the plan says so with `taxedIn`.
    private func pensionIssues() -> [TaxIssue] {
        guard citizenships.contains("IT") else { return [] }
        return plan.pensions.filter { $0.scheme == "it.inps" || $0.sourceCountry?.uppercased() == "IT" }.map { pension in
            .warning("ch.foreignPension.italianPublicService",
                     "If \(pension.id) is a pension from Italian public service, Italy taxes it for an Italian citizen "
                         + "(treaty Art. 19): enter it with taxedIn: source. A private-sector pension is taxed in "
                         + "Switzerland.", regime: pension.scheme)
        }
    }
}
