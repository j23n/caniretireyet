import Foundation
import Model
import Planner
import Testing
@testable import CanIRetireYet

/// What the plan's *What if* tile says once something is changed (UI.md,
/// "The plan").
struct PlanWhatIfTextTests {
    private let english = Locale(identifier: "en_US")
    private let plan = PlanDocument(id: "base", name: "Base case", retirement: PlanRetirement(age: .age(55)),
                                    spending: PlanSpending(working: 30_000, retired: 36_000))

    private func changes(_ whatIf: PlanWhatIf) -> [AmountSentence] {
        PlanWhatIfText.changes(PlanWhatIfModel(plan: plan, results: nil, whatIf: whatIf),
                               words: PlanWords(currency: "EUR", locale: english))
    }

    @Test func withoutAChangeItSaysNothing() {
        #expect(changes(PlanWhatIf()).isEmpty)
    }

    @Test func itSaysWhatChangedInTheSlidersOrder() throws {
        let said = changes(PlanWhatIf(retirementAge: 52, retiredSpending: 33_600))
        try #require(said.count == 2)
        #expect(said[0].text == "Stop at 52")
        #expect(!said[0].hasAmounts)
        // Spending a month, as the slider says it; the amount hides with the eye.
        let amount = AmountFormat.amount(2_800, currency: "EUR", locale: english)
        #expect(said[1].text == "Spend \(amount) a month")
        #expect(said[1].hasAmounts)
    }
}
