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

    /// The step's number along the bottom, "Step 1 of 6": every step after
    /// the welcome, which has none.
    var number: Int? {
        guard self != .welcome, let index = Self.allCases.firstIndex(of: self) else { return nil }
        return index
    }

    /// How many steps ``number`` counts.
    static let count = allCases.count - 1
}
