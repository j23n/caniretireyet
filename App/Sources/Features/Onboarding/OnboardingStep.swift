import Foundation

/// A step of first launch (UI.md, "Empty states and first launch"), in
/// order. `OnboardingScreen` shows them.
enum OnboardingStep: String, CaseIterable, Sendable {
    /// The question the app answers, and what the tour leads to.
    case welcome
    /// Birth date, country and currency, and whether to keep the library in
    /// iCloud Drive.
    case you
    /// Round amounts of what you have today, and pay and spending a month.
    case money
    /// A state pension, when to stop, and the tax on investments; *See My
    /// Answer* creates the library.
    case later
    /// The first answer, calculated in the tour.
    case answer
    /// Making the answer real with files: *Import Files…* or *Later*.
    case files
    /// The monthly note and *Your year*, the widget, and the disclaimer;
    /// *Start* opens the Overview.
    case notes

    /// Whether the step comes once *See My Answer* has created the library.
    var comesAfterCreating: Bool {
        self == .answer || self == .files || self == .notes
    }

    /// The step after this one; `nil` after the last.
    var next: OnboardingStep? {
        let steps = Self.allCases
        guard let index = steps.firstIndex(of: self), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    /// The step *Back* goes to: none from the welcome, nor from the
    /// answer, which can't go back to before the library was created.
    var previous: OnboardingStep? {
        let steps = Self.allCases
        guard let index = steps.firstIndex(of: self), index > 0,
              comesAfterCreating == steps[index - 1].comesAfterCreating else { return nil }
        return steps[index - 1]
    }

    /// The questions' steps, numbered "1 of 4" along the bottom; `nil`
    /// for the welcome and the steps after the answer is there.
    var questionNumber: Int? {
        switch self {
        case .you: 1
        case .money: 2
        case .later: 3
        case .answer: 4
        case .welcome, .files, .notes: nil
        }
    }

    /// How many steps ``questionNumber`` counts.
    static let questionCount = 4
}
