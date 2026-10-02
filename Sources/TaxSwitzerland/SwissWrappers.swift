import TaxKit

extension SwissTaxSystem {
    /// The wrapper rules, with the ages of `p` (the latest year). Payout
    /// taxes are computed in `assess`. Ages are the age during the calendar
    /// year: a pillar 3a account opens in the year of the 60th birthday.
    static func wrapperRules(parameters p: SwissParameters?, staggerPayouts: Bool) -> [WrapperRule] {
        let referenceAge = p?.ahv.referenceAge ?? 65
        let pillar3aFrom = referenceAge - (p?.pillar3a.earliestYearsBeforeReferenceAge ?? 5)
        let pillar3aLatest = referenceAge + (p?.pillar3a.latestYearsAfterReferenceAgeIfWorking ?? 5)
        let vestedFrom = referenceAge - (p?.vestedBenefits.earliestYearsBeforeReferenceAge ?? 5)
        let vestedLatest = referenceAge + (p?.vestedBenefits.latestYearsAfterReferenceAgeIfWorking ?? 5)
        let bvgEarliest = p?.bvg.earliestAge ?? 58
        /// Due at the reference age, or later while still working, at the latest at `latest`.
        @Sendable func due(_ context: WrapperAccessContext, latest: Int) -> Bool {
            (context.age >= referenceAge && context.yearsSinceWorkStopped != nil) || context.age >= latest
        }
        return [
            WrapperRule(id: SwissWrapper.ordinary, name: "Ordinary account", category: .taxable) { _ in
                .accessible(route: nil)
            },
            WrapperRule(id: SwissWrapper.pillar3a, name: "Pillar 3a", category: .taxDeferred,
                        preferredPayoutYears: staggerPayouts ? referenceAge - pillar3aFrom : nil,
                        mustPayOut: { due($0, latest: pillar3aLatest) }) { context in
                context.age >= pillar3aFrom
                    ? .accessible(route: nil)
                    : .locked(reason: "A pillar 3a account can be drawn from \(pillar3aFrom), "
                        + "\(referenceAge - pillar3aFrom) years before the AHV reference age (earlier only on "
                        + "leaving Switzerland for good, for self-employment or a home, which the plan doesn't "
                        + "model).")
            },
            WrapperRule(id: SwissWrapper.vestedBenefits, name: "Vested benefits", category: .taxDeferred,
                        preferredPayoutYears: staggerPayouts ? p?.vestedBenefits.maxAccounts : nil,
                        mustPayOut: { due($0, latest: vestedLatest) }) { context in
                context.age >= vestedFrom
                    ? .accessible(route: nil)
                    : .locked(reason: "A vested-benefits account can be drawn from \(vestedFrom), "
                        + "\(referenceAge - vestedFrom) years before the AHV reference age (earlier only on leaving "
                        + "Switzerland or for self-employment or a home, which the plan doesn't model).")
            },
            WrapperRule(id: SwissWrapper.bvg, name: "Pension fund (BVG)", category: .taxDeferred,
                        mustPayOut: { due($0, latest: vestedLatest) }) { context in
                (context.age >= bvgEarliest && context.yearsSinceWorkStopped != nil) || context.age >= referenceAge
                    ? .accessible(route: nil)
                    : .locked(reason: "Pension-fund assets are paid from \(bvgEarliest) once work stops, or from "
                        + "\(referenceAge). Add a ch.bvg pension to the plan to choose an annuity or a lump sum.")
            },
        ]
    }
}
