import Foundation

/// What the app's answers are and aren't: a line under every answer to
/// "Can I retire yet?" (onboarding, the Overview, the plan's results) and
/// the whole of it in Settings' About section.
enum AboutText {
    /// The short form, under an answer.
    static let disclaimer = "Estimates, not financial or tax advice."

    /// On the onboarding's welcome.
    static let welcome = "The answers are estimates, not financial or tax advice."

    /// Settings' About section: what the results are, and which tax rules
    /// plans know (`AppTaxRegistry.standard`; the Swiss cantons in
    /// docs/tax/CH.md).
    static let about = "Results are estimates from simplified models of tax and pension rules, which change every "
        + "year. They aren't financial, tax or legal advice: check important decisions with a professional. "
        + "Tax rules cover Italy, Switzerland (the cantons of Zurich and Ticino) and Germany for 2026; "
        + "elsewhere plans use a generic system with flat rates you choose."
}
