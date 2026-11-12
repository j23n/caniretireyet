import Foundation
import Model
import Testing
@testable import CanIRetireYet

/// The net worth charts in today's money (UI.md, "Accounts", "Ahead"): the
/// index they're adjusted with, and the note for months it has no value for.
@MainActor
struct HistoryMoneyTests {
    private let english = Locale(identifier: "en_US")

    @Test func theExampleLibraryHasAnIndexForItsCharts() throws {
        let index = try #require(PlanMoney.historyIndex(PreviewLibrary.library))
        #expect(!index.records.isEmpty)
        #expect(PlanMoney.historyIndex(PreviewLibrary.empty) == nil)
    }

    @Test func theNoteNamesTheMonthsLeftAsRecorded() {
        #expect(PlanMoney.unadjustedNote([], locale: english) == nil)
        #expect(PlanMoney.unadjustedNote(["2024-03-31"], locale: english)
            == "Mar 2024 isn't adjusted for inflation: its value is missing from the inflation index.")
        #expect(PlanMoney.unadjustedNote(["2024-03-31", "2024-04-30", "2024-05-31"], locale: english)
            == "Mar – May 2024 aren't adjusted for inflation: their values are missing from the inflation index.")
    }
}
