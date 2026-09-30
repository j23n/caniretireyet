import TaxKit

extension ItalyTaxSystem {
    /// The wrapper rules, with the rates and ages of `parameters` (the latest
    /// year). Payout taxes are computed in `assess`.
    static func wrapperRules(parameters: ItalyParameters?) -> [WrapperRule] {
        let fund = parameters?.pensionFund
        let pension = parameters?.pension
        let tfr = parameters?.tfr
        /// The vecchiaia age when the planner doesn't pass one: the file's
        /// rules plus the default of one more month a year after its steps.
        @Sendable func oldAge(_ year: Int) -> Int? {
            pension.map { ($0.vecchiaia.age * 12 + $0.ageIncrease(in: year, perYear: 1)) / 12 }
        }
        return [
            WrapperRule(id: ItalyWrapper.ordinary, name: "Ordinary account", category: .taxable) { _ in
                .accessible(route: nil)
            },
            WrapperRule(id: ItalyWrapper.pensionFund, name: "Pension fund", category: .taxDeferred,
                        growthTaxRate: fund?.growthTaxRate) { context in
                pensionFundAccess(context, rules: fund, oldAge: context.oldAgePensionAge ?? oldAge(context.year))
            },
            WrapperRule(id: ItalyWrapper.tfr, name: "TFR", category: .taxDeferred,
                        growthTaxRate: tfr?.revaluationTaxRate, revaluation: tfr?.revaluation) { context in
                context.yearsSinceWorkStopped != nil
                    ? .accessible(route: nil) : .locked(reason: "The TFR is paid when the job ends.")
            },
        ]
    }

    /// From the INPS pension age after the minimum membership, or earlier
    /// through RITA: within 5 years of it after stopping work with 20 years
    /// of contributions, or within 10 years after 2 years without work.
    static func pensionFundAccess(_ context: WrapperAccessContext, rules: ItalyParameters.PensionFund?,
                                  oldAge: Int?) -> WrapperAccess {
        guard let rules, let oldAge else { return .locked(reason: "No pension-fund rules are available.") }
        guard context.membershipYears >= rules.minimumMembershipYears else {
            return .locked(reason: "The pension fund can be drawn after \(rules.minimumMembershipYears) years of "
                           + "membership.")
        }
        if context.age >= oldAge { return .accessible(route: nil) }
        if let stopped = context.yearsSinceWorkStopped {
            if context.age >= oldAge - rules.ritaYearsBeforeOldAge
                && context.contributionYears >= rules.ritaContributionYears {
                return .accessible(route: ItalyAccessRoute.rita)
            }
            if context.age >= oldAge - rules.ritaExtendedYearsBeforeOldAge
                && stopped >= rules.ritaExtendedYearsWithoutWork {
                return .accessible(route: ItalyAccessRoute.rita)
            }
        }
        let early = oldAge - rules.ritaExtendedYearsBeforeOldAge
        return .locked(reason: "The pension fund can be drawn from \(oldAge), or through RITA from "
                       + "\(oldAge - rules.ritaYearsBeforeOldAge) (after stopping work, with "
                       + "\(Int(rules.ritaContributionYears)) years of contributions) or from \(early) (after "
                       + "\(rules.ritaExtendedYearsWithoutWork) years without work).")
    }
}
