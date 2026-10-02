/// The keys of the tax state the German system carries from one year to the
/// next. Everything in it depends only on the plan (never on the markets), so
/// the state from `fixedAssessment` and from `assess` is the same. Other
/// systems copy the state forward, so the keys survive a period abroad.
enum GermanStateKey {
    /// A pension's fixed exempt amount (Rentenfreibetrag), in nominal euros
    /// of the year it was fixed: `de.pension.<id>.exemptAmount`.
    static func exemptAmount(_ pension: String) -> String { "de.pension.\(pension).exemptAmount" }
    /// Set once the system has seen a pension, so checks run in its first year only.
    static func seen(_ pension: String) -> String { "de.pension.\(pension).seen" }
    /// Last year's insured earnings, for Riester's minimum own contribution.
    static let priorInsuredEarnings = "de.prior.insuredEarnings"
    /// Years a PKV premium has been paid, for its real growth.
    static let pkvYears = "de.pkv.years"
    /// Set once the KVdR test has been reported.
    static let kvdrChecked = "de.kvdr.checked"
}
