import TaxKit

extension ItalyTaxSystem {
    /// The wrapper rules, with the rates and ages of `parameters` (the latest
    /// year). Payout taxes are computed in `assess`.
    static func wrapperRules(parameters: ItalyParameters?) -> [WrapperRule] {
        let fund = parameters?.pensionFund
        let pension = parameters?.pension
        let tfr = parameters?.tfr
        /// The vecchiaia age in months when the planner doesn't pass one: the
        /// file's rules plus the default of one more month a year after its steps.
        @Sendable func oldAgeInMonths(_ year: Int) -> Int? {
            pension.map { $0.vecchiaia.age * 12 + $0.ageIncrease(in: year, perYear: 1) }
        }
        return [
            WrapperRule(id: ItalyWrapper.ordinary, name: "Ordinary account", category: .taxable) { _ in
                .accessible(route: nil)
            },
            WrapperRule(id: ItalyWrapper.pensionFund, name: "Pension fund", category: .taxDeferred,
                        growthTaxRate: fund?.growthTaxRate) { context in
                let months = context.oldAgePensionAgeInMonths
                    ?? context.oldAgePensionAge.map { $0 * 12 } ?? oldAgeInMonths(context.year)
                return pensionFundAccess(context, rules: fund, oldAgeInMonths: months)
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
    ///
    /// Ages count in months. The planner steps a year at a time, so an age
    /// requirement opens the fund from the first calendar year it holds for
    /// in full: reached by 1 January, counting from the month of birth as
    /// INPS does (payments start the month after). Without a birth date, the
    /// age reached during the year is compared with the whole years.
    static func pensionFundAccess(_ context: WrapperAccessContext, rules: ItalyParameters.PensionFund?,
                                  oldAgeInMonths oldAge: Int?) -> WrapperAccess {
        guard let rules, let oldAge else { return .locked(reason: "No pension-fund rules are available.") }
        guard context.membershipYears >= rules.minimumMembershipYears else {
            return .locked(reason: "The pension fund can be drawn after \(rules.minimumMembershipYears) years of "
                           + "membership.")
        }
        /// Whether an age of `months` is reached for the whole year.
        func reached(_ months: Int) -> Bool {
            if let age = context.ageInMonthsAtStartOfYear { return age >= months }
            return context.age >= months / 12
        }
        if reached(oldAge) { return .accessible(route: nil) }
        if let stopped = context.yearsSinceWorkStopped {
            if reached(oldAge - rules.ritaYearsBeforeOldAge * 12)
                && context.contributionYears >= rules.ritaContributionYears {
                return .accessible(route: ItalyAccessRoute.rita)
            }
            if reached(oldAge - rules.ritaExtendedYearsBeforeOldAge * 12)
                && stopped >= rules.ritaExtendedYearsWithoutWork {
                return .accessible(route: ItalyAccessRoute.rita)
            }
        }
        return .locked(reason: "The pension fund can be drawn from \(Self.age(oldAge)), or through RITA from "
                       + "\(Self.age(oldAge - rules.ritaYearsBeforeOldAge * 12)) (after stopping work, with "
                       + "\(Int(rules.ritaContributionYears)) years of contributions) or from "
                       + "\(Self.age(oldAge - rules.ritaExtendedYearsBeforeOldAge * 12)) (after "
                       + "\(rules.ritaExtendedYearsWithoutWork) years without work).")
    }

    /// An age in months for messages: "67" or "67 and 9 months".
    static func age(_ months: Int) -> String {
        months % 12 == 0 ? "\(months / 12)" : "\(months / 12) and \(months % 12) months"
    }
}
