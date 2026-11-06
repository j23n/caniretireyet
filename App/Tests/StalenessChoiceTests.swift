import Testing
@testable import CanIRetireYet

/// Settings › Check-in: when a value is old (UI.md, "Settings").
struct StalenessChoiceTests {
    @Test func theChoicesAreNamedAndKeepAnotherNumber() {
        #expect(StalenessChoice.days.map(StalenessChoice.name) == ["45 days", "3 months", "6 months", "A year"])
        #expect(StalenessChoice.options(including: 45) == StalenessChoice.days)
        #expect(StalenessChoice.options(including: 60) == [45, 60, 92, 183, 366])
        #expect(StalenessChoice.name(60) == "60 days")
    }
}
