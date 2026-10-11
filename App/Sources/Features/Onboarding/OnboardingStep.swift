import Foundation

/// A step of first launch (UI.md, "Empty states and first launch"), in
/// order. `OnboardingScreen` shows them.
enum OnboardingStep: String, CaseIterable, Sendable {
    /// What the app does: check-ins, plans and their answer, files you own.
    case welcome
    /// Where to keep the data.
    case location
    /// Name, birth date, base currency and country.
    case you
    /// Take-home pay, spending, the age to retire at and the reminder;
    /// *Create library*.
    case money
    /// Adding accounts or importing a spreadsheet, once the library exists.
    case accounts
    /// The disclaimer, last; *Start* opens the app.
    case disclaimer

    /// Whether the step comes once *Create library* has created the library.
    var comesAfterCreating: Bool {
        self == .accounts || self == .disclaimer
    }

    /// The step after this one; `nil` after the last.
    var next: OnboardingStep? {
        let steps = Self.allCases
        guard let index = steps.firstIndex(of: self), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    /// The step *Back* goes to: none from the welcome, nor from the
    /// accounts step, which can't go back to before the library was
    /// created.
    var previous: OnboardingStep? {
        let steps = Self.allCases
        guard let index = steps.firstIndex(of: self), index > 0,
              comesAfterCreating == steps[index - 1].comesAfterCreating else { return nil }
        return steps[index - 1]
    }
}
