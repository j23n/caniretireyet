import TaxKit

/// Checks a plan against the Italian rules that don't need its amounts:
/// the shared checks (unknown IDs, regime scope and years, options,
/// overrides), impatriati's years and exclusions, and forfettario's
/// start-up period. Checks that need amounts, such as forfettario's revenue
/// limits, run year by year in `prepare`; `TaxSystem.validate(_:years:parameters:)`
/// collects them over a plan's years.
struct ItalyValidator {
    let system: ItalyTaxSystem
    let plan: TaxPlan
    let parameters: any ParameterStore

    func issues() -> [TaxIssue] {
        var issues = system.commonIssues(for: plan)
        let periods = system.residencePeriods(in: plan)
        guard let first = periods.first?.lowerBound else { return issues }
        let p: ItalyParameters
        do {
            p = try ItalyParameters(try parameters.parameters(for: first))
        } catch {
            issues.append(.error("it.parameters", "The Italian tax parameters can't be used: \(error)", year: first))
            return issues
        }
        issues += overlayIssues(p)
        issues += forfettarioIssues(p)
        return issues
    }

    private func isResident(in year: Int) -> Bool {
        plan.residence(in: year)?.system == system.id
    }

    /// The phases taxed under forfettario, with the years they're resident in Italy.
    private var forfettarioPhases: [(phase: TaxPlan.WorkPhase, years: [ClosedRange<Int>])] {
        plan.work.compactMap { phase in
            guard system.effectiveRegime(for: phase.regime, kind: phase.kind) == ItalyRegime.forfettario else {
                return nil
            }
            let years = system.residenceYears(in: plan, from: phase.fromYear, until: phase.untilYear)
            return years.isEmpty ? nil : (phase, years)
        }
    }

    private func overlayIssues(_ p: ItalyParameters) -> [TaxIssue] {
        var issues: [TaxIssue] = []
        let impatriati = plan.overlays.filter {
            $0.regime == ItalyRegime.impatriati2024 || $0.regime == ItalyRegime.impatriati2015
        }
        if impatriati.count > 1 {
            issues.append(.error("it.impatriati.both", "Choose one impatriati regime: they can't be combined.",
                                 regime: impatriati[1].regime))
        }
        for overlay in impatriati {
            guard let movedIn = overlay.options.int("movedIn") else { continue }
            let name = system.regime(overlay.regime)?.name ?? overlay.regime
            let lastYear: Int
            var stay: Int
            if overlay.regime == ItalyRegime.impatriati2024 {
                guard movedIn >= p.impatriati2024.firstMoveYear else {
                    issues.append(.error("it.impatriati.movedIn", "\(name) is for moves from "
                                         + "\(p.impatriati2024.firstMoveYear); for earlier moves choose "
                                         + "\(ItalyRegime.impatriati2015).", regime: overlay.regime, option: "movedIn"))
                    continue
                }
                lastYear = movedIn + p.impatriati2024.years - 1
                stay = p.impatriati2024.minimumStayYears
            } else {
                let rules = p.impatriati2015
                guard movedIn <= rules.lastMoveYear else {
                    issues.append(.error("it.impatriati.movedIn", "\(name) is for moves up to \(rules.lastMoveYear); "
                                         + "for later moves choose \(ItalyRegime.impatriati2024).",
                                         regime: overlay.regime, option: "movedIn"))
                    continue
                }
                let extended = overlay.options.string("extension", default: "none") != "none"
                if extended && movedIn < rules.extensionFromMoveYear {
                    issues.append(.warning("it.impatriati.extension", "The extension for moves before "
                                           + "\(rules.extensionFromMoveYear) needed a one-off payment and isn't modelled.",
                                           regime: overlay.regime, option: "extension"))
                }
                lastYear = movedIn + rules.years - 1
                    + (extended && movedIn >= rules.extensionFromMoveYear ? rules.extensionYears : 0)
                stay = rules.minimumStayYears
            }
            let covered = (movedIn...lastYear).filter(isResident)
            if covered.isEmpty {
                issues.append(.warning("it.impatriati.noYears", "\(name) covers \(movedIn)–\(lastYear), which the plan "
                                       + "doesn't spend resident in Italy.", regime: overlay.regime))
            }
            stay = max(stay, 1)
            if let leaving = plan.residence.filter({ $0.system != system.id && $0.from > movedIn })
                .map(\.from).min(), leaving < movedIn + stay {
                issues.append(.warning("it.impatriati.minimumStay", "Leaving Italy in \(leaving), within \(stay) years "
                                       + "of moving, means paying the \(name) exemption back with interest.",
                                       year: leaving, regime: overlay.regime))
            }
            for (phase, years) in forfettarioPhases {
                let lost = years.flatMap { range -> [Int] in
                    let lower = max(range.lowerBound, movedIn)
                    let upper = min(range.upperBound, lastYear)
                    return lower <= upper ? Array(lower...upper) : []
                }
                if let firstLost = lost.first, let lastLost = lost.last {
                    let span = firstLost == lastLost ? "the \(firstLost) exemption" : "the \(firstLost)–\(lastLost) exemptions"
                    issues.append(.warning("it.impatriati.forfettario",
                                           "Impatriati doesn't apply to forfettario income: you lose \(span).",
                                           year: firstLost, regime: overlay.regime))
                }
                if phase.fromYear <= movedIn && (phase.untilYear ?? Int.max) >= movedIn {
                    let message = p.forfettarioOnArrivalRulesOut(overlay.regime)
                        ? "Choosing forfettario in \(movedIn), the year you moved, rules out \(name) in later years."
                        : "Choosing forfettario in \(movedIn), the year you moved, may rule out \(name) in later years: "
                            + "the Agenzia delle Entrate said so for the 2015 regime, and there's no ruling on the 2024 "
                            + "regime yet."
                    issues.append(.warning("it.impatriati.forfettarioOnArrival", message, year: movedIn,
                                           regime: overlay.regime))
                }
            }
        }
        return issues
    }

    private func forfettarioIssues(_ p: ItalyParameters) -> [TaxIssue] {
        var issues: [TaxIssue] = []
        for (phase, years) in forfettarioPhases {
            guard let startedIn = phase.options.int("startedIn"), let last = years.last?.upperBound else { continue }
            if startedIn > phase.fromYear {
                issues.append(.warning("it.forfettario.startedIn", "The activity is said to start in \(startedIn), "
                                       + "after the phase starts in \(phase.fromYear).", year: phase.fromYear,
                                       regime: ItalyRegime.forfettario, option: "startedIn"))
            }
            let end = startedIn + p.forfettario.startupYears
            if end > phase.fromYear && end <= last {
                issues.append(.warning("it.forfettario.startupEnds", "The \(percent(p.forfettario.startupRate)) "
                                       + "start-up rate ends after \(end - 1); from \(end) the rate is "
                                       + "\(percent(p.forfettario.rate)).", year: end, regime: ItalyRegime.forfettario))
            }
        }
        return issues
    }
}
