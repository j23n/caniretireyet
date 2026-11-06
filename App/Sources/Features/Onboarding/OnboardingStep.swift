import Foundation

/// A step of first launch (UI.md, "Empty states and first launch"), in
/// order. `OnboardingScreen` shows them.
enum OnboardingStep: String, CaseIterable, Sendable {
    /// The question the app answers, and what the tour leads to.
    case welcome
    /// Birth date, country and currency, and whether to keep the library in
    /// iCloud Drive.
    case you
    /// Rough amounts of what you have today, and pay and spending a month.
    case money
    /// Pension and retirement: a state pension, when to retire, and the tax
    /// on investments; *See My Answer* creates the library.
    case later
    /// The first answer, calculated in the tour.
    case answer
    /// What your records show: example tiles of what recording money in
    /// and out adds to the answer.
    case records
    /// Keeping the answer up to date: typing your balances, importing your
    /// statements, or deciding later (``OnboardingModel/KeepUp``).
    case keepUp
    /// The monthly note and *Your year*, the widget, and the disclaimer;
    /// *Start* opens Today.
    case notes

    /// Whether the step comes once *See My Answer* has created the library.
    var comesAfterCreating: Bool {
        self == .answer || self == .records || self == .keepUp || self == .notes
    }

    /// The step after this one; `nil` after the last.
    var next: OnboardingStep? {
        let steps = Self.allCases
        guard let index = steps.firstIndex(of: self), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    /// The step before this one; `nil` for the welcome. *Back* goes there,
    /// from the answer only while the library holds just what the tour
    /// added (`OnboardingModel.previousStep(in:answerIsRunning:)`).
    var previous: OnboardingStep? {
        let steps = Self.allCases
        guard let index = steps.firstIndex(of: self), index > 0 else { return nil }
        return steps[index - 1]
    }

    /// The step's number along the bottom, "Step 1 of 7": every step after
    /// the welcome, which has none.
    var number: Int? {
        guard self != .welcome, let index = Self.allCases.firstIndex(of: self) else { return nil }
        return index
    }

    /// How many steps ``number`` counts.
    static let count = allCases.count - 1
}
