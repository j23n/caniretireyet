import Foundation

/// What the app's answers are and aren't: a line under every answer to
/// "Can I retire yet?" (onboarding, the Overview, the plan's results) and
/// the whole of it in Settings' About section.
enum AboutText {
    /// The short form, under an answer.
    static let disclaimer = "Estimates, not financial or tax advice."

    /// On the onboarding's welcome.
    static let welcome = "The answers are estimates, not financial or tax advice."

    /// Settings' About section: what the results are, and how plans treat taxes.
    static let about = "Results are estimates from a simplified model with the returns, taxes and pensions you "
        + "enter. Plans take your income and pensions after tax, and tax your investments at the rates you set. "
        + "They aren't financial, tax or legal advice: check important decisions with a professional."
}
