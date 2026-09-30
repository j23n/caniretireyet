import TaxKit

/// An impatriati overlay's effect in one year: the exempt share and the most
/// income it applies to.
struct ImpatriatiYear: Hashable, Sendable {
    var regime: String
    var exemptShare: Double
    /// The largest yearly income the exemption applies to, if limited.
    var incomeCap: Double?
}

extension ItalyParameters {
    /// What `overlay` does in `year`, or `nil` when it doesn't cover the year
    /// (or isn't an impatriati regime).
    func impatriati(_ overlay: RegimeChoice, in year: Int) -> ImpatriatiYear? {
        guard let movedIn = overlay.options.int("movedIn") else { return nil }
        switch overlay.regime {
        case ItalyRegime.impatriati2024:
            let rules = impatriati2024
            guard movedIn >= rules.firstMoveYear, year >= movedIn, year < movedIn + rules.years else { return nil }
            let share = overlay.options.bool("minorChild", default: false) ? rules.minorChildExemptShare : rules.exemptShare
            return ImpatriatiYear(regime: overlay.regime, exemptShare: share, incomeCap: rules.incomeCap)
        case ItalyRegime.impatriati2015:
            let rules = impatriati2015
            guard movedIn <= rules.lastMoveYear, year >= movedIn else { return nil }
            if year < movedIn + rules.years {
                let share: Double
                if movedIn >= rules.reformFromMoveYear {
                    share = overlay.options.bool("south", default: false) ? rules.southExemptShare : rules.exemptShare
                } else {
                    share = rules.preReformExemptShare
                }
                return ImpatriatiYear(regime: overlay.regime, exemptShare: share, incomeCap: nil)
            }
            let extensionChoice = overlay.options.string("extension", default: "none")
            guard extensionChoice != "none", movedIn >= rules.extensionFromMoveYear,
                  year < movedIn + rules.years + rules.extensionYears else { return nil }
            let share = overlay.options.bool("threeMinorChildren", default: false)
                ? rules.extensionThreeMinorChildrenExemptShare : rules.extensionExemptShare
            return ImpatriatiYear(regime: overlay.regime, exemptShare: share, incomeCap: nil)
        default:
            return nil
        }
    }

    /// Whether choosing forfettario in the year of the move rules `regime` out.
    func forfettarioOnArrivalRulesOut(_ regime: String) -> Bool {
        switch regime {
        case ItalyRegime.impatriati2024: impatriati2024.forfettarioOnArrivalRulesOut
        case ItalyRegime.impatriati2015: impatriati2015.forfettarioOnArrivalRulesOut
        default: false
        }
    }
}

extension ItalyYearCalculator {
    /// Stage 2: impatriati exempts part of employment and professional income
    /// (never forfettario income). With both regimes chosen, the first one
    /// that covers the year applies; validation reports the conflict.
    mutating func applyOverlays() {
        let onArrival = state[ItalyStateKey.forfettarioOnArrival].map { Int($0) }
        for overlay in year.overlays {
            guard let movedIn = overlay.options.int("movedIn") else { continue }
            if movedIn == year.year, work.contains(where: { $0.regime == ItalyRegime.forfettario }) {
                arrivedWithForfettario = movedIn
            }
        }
        let parameters = p
        let thisYear = year.year
        let active = year.overlays.lazy.compactMap { parameters.impatriati($0, in: thisYear) }.first
        guard let active else { return }
        if let onArrival, p.forfettarioOnArrivalRulesOut(active.regime) {
            issues.append(.warning(
                "it.impatriati.forfettarioOnArrival",
                "Forfettario was chosen in \(onArrival), the year of the move, which rules out impatriati: "
                    + "\(year.year) gets no exemption.",
                year: year.year, regime: active.regime))
            return
        }
        var capLeft = active.incomeCap ?? .infinity
        for index in work.indices {
            let income: Double
            switch work[index].regime {
            case ItalyRegime.employee: income = work[index].employmentIncome
            case ItalyRegime.professional: income = work[index].professionalIncome
            default:
                if work[index].regime == ItalyRegime.forfettario {
                    issues.append(.warning(
                        "it.impatriati.forfettario",
                        "Impatriati doesn't apply to forfettario income: you lose the \(year.year) exemption.",
                        year: year.year, regime: active.regime))
                }
                continue
            }
            let covered = min(max(0, income), capLeft)
            capLeft -= covered
            work[index].exempt = active.exemptShare * covered
        }
    }
}
