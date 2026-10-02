import TaxKit

extension GermanTaxSystem {
    /// The federal states, by their ISO 3166-2 code without the `DE-` prefix.
    static let federalStates: [(value: String, label: String)] = [
        ("BW", "Baden-Württemberg"), ("BY", "Bavaria"), ("BE", "Berlin"), ("BB", "Brandenburg"), ("HB", "Bremen"),
        ("HH", "Hamburg"), ("HE", "Hesse"), ("MV", "Mecklenburg-Western Pomerania"), ("NI", "Lower Saxony"),
        ("NW", "North Rhine-Westphalia"), ("RP", "Rhineland-Palatinate"), ("SL", "Saarland"), ("SN", "Saxony"),
        ("ST", "Saxony-Anhalt"), ("SH", "Schleswig-Holstein"), ("TH", "Thuringia"),
    ]

    /// The residence options. `childBirthYears` (a list of years) is read
    /// too, though no `OptionField` kind describes a list: the validator
    /// checks it.
    static func systemOptions(parameters p: GermanParameters?) -> [OptionField] {
        [
            .choice("bundesland", "Federal state", federalStates,
                    help: "Sets the church-tax rate (8% in Bavaria and Baden-Württemberg, 9% elsewhere) and "
                        + "Saxony's split of care insurance. None: 9% and the usual split."),
            .bool("churchMember", "Member of a church that levies church tax"),
            .int("children", "Children", default: 0, range: 0...30,
                 help: "Any child ends the childless care surcharge, and each adds 3 years toward the pensioners' "
                     + "health insurance (KVdR). The residence option childBirthYears, a list of years, adds the "
                     + "care discounts and Riester grants for children under 25."),
            .choice("healthInsurance", "Health insurance before a pension",
                    [("gkv", "Statutory (GKV)"), ("pkv", "Private (PKV)")], default: "gkv",
                    help: "PKV needs self-employment or, for an employee, a salary above the compulsory-insurance "
                        + "limit (€77,400 in 2026)."),
            .percent("zusatzbeitrag", "Health fund's additional rate", default: p?.health.averageAdditionalRate,
                     range: 0...0.1, help: "The Zusatzbeitrag of your health fund (2.9% on average in 2026)."),
            .money("pkvPremium", "PKV premium per month",
                   help: "Health and care together, in today's money in the plan's currency. Required with PKV."),
            .percent("pkvBasicShare", "Deductible share of the PKV premium", default: 0.8,
                     help: "The basic-cover share, from your insurer's yearly statement."),
            .percent("pkvRealPremiumGrowth", "Real growth of the PKV premium per year", default: 0.01,
                     range: -0.05...0.1, help: "How much faster than prices the premium rises. A plan assumption."),
            .choice("retirementHealthInsurance", "Health insurance from the first pension",
                    [("auto", "Decide by the 9/10 rule"), ("kvdr", "Pensioners' insurance (KVdR)"),
                     ("voluntary", "Voluntary GKV"), ("pkv", "Private (PKV)")], default: "auto",
                    help: "KVdR charges pensions only; voluntary GKV charges all income, capital included."),
            .percent("insuredShareBeforePlan", "Share of working life in statutory health insurance before the plan",
                     default: 1, help: "In Germany, another EU/EEA country or Switzerland. For the 9/10 rule."),
            .year("workStartYear", "Year of the first job",
                  help: "Starts the 9/10 rule's reference period. Default: the year you turned 20."),
            .money("otherDeductions", "Other deductions per year", default: 0,
                   help: "Work costs above the €1,230 lump sum, donations, extraordinary burdens."),
            .percent("basiszins", "Base rate for the Vorabpauschale after 2026", default: p?.basiszins,
                     range: -0.1...0.2, help: "A plan assumption; 3.20% in 2026."),
            .percent("realWageGrowth", "Real growth of average wages per year", default: 0.01, range: -0.05...0.1,
                     help: "Moves the contribution ceilings and the other amounts the law sets from wages."),
            .bool("indexFixedAllowances", "Index fixed allowances",
                  help: "Whether the €1,000 savers' allowance, the lump sums and the inheritance allowances keep their "
                      + "value in today's money. The law keeps them fixed."),
        ]
    }

    /// The regime descriptors, with option defaults and limits from the
    /// latest parameters.
    static func regimeDescriptors(parameters p: GermanParameters?) -> [RegimeDescriptor] {
        let drv: OptionField = .choice(
            "drv", "Statutory pension insurance",
            [("none", "None"), ("voluntary", "Voluntary contributions"),
             ("compulsory", "Compulsory, on application")],
            default: "none",
            help: "Most self-employed people aren't insured in the DRV. Compulsory insurance on application also "
                + "makes Riester possible.")
        let contribution: OptionField = .money(
            "drvContribution", "DRV contribution per year",
            help: "Voluntary: between \(p.map { euros($0.drvVoluntaryMinimum) } ?? "the minimum") and "
                + "\(p.map { euros($0.drvVoluntaryMaximum) } ?? "the maximum"); default the minimum. Compulsory: "
                + "default the standard contribution (\(p.map { euros($0.drvStandardContribution) } ?? "")).")
        let sickPay: OptionField = .bool(
            "sickPay", "Health insurance with sick pay", help: "14.6% instead of 14.0%, with sick pay from day 43.")
        return [
            RegimeDescriptor(
                id: GermanRegime.employee, name: "Employee", scope: .earnedIncome([.employee]),
                summary: "Gross salary less social contributions (pension, unemployment, health, care) up to the "
                    + "ceilings, taxed on the §32a tariff after the €1,230 lump sum. Salary paid into a de.bav account "
                    + "is tax-free; past the standard retirement age, €2,000 a month is tax-free (Aktivrente)."),
            RegimeDescriptor(
                id: GermanRegime.freelancer, name: "Freiberufler", scope: .earnedIncome([.selfEmployed]),
                options: [drv, contribution, sickPay],
                excludes: [GermanRegime.trader],
                summary: "Revenue less costs, taxed on the §32a tariff. Voluntary health and care insurance on all "
                    + "income; pension insurance only if chosen."),
            RegimeDescriptor(
                id: GermanRegime.trader, name: "Gewerbetreibender", scope: .earnedIncome([.selfEmployed]),
                options: [
                    drv, contribution, sickPay,
                    .percent("hebesatz", "Trade-tax multiplier (Hebesatz)",
                             range: (p?.tradeTax.minimumMultiplier ?? 2)...9, required: true,
                             help: "The municipality's multiplier, e.g. 400% (at least 200%)."),
                ],
                excludes: [GermanRegime.freelancer],
                summary: "As a Freiberufler, plus trade tax on profit above €24,500, credited against income tax up to "
                    + "4 times its base amount."),
        ]
    }
}
