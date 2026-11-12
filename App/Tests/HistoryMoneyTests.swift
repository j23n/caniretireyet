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

    @Test func theNotesNameTheMonthsWithoutAnInflationValue() {
        #expect(PlanMoney.missingInflationNote([], locale: english) == nil)
        #expect(PlanMoney.missingInflationNote(["2024-03-31"], locale: english)
            == "Shown as recorded: Mar 2024 has no inflation value yet.")
        #expect(PlanMoney.missingInflationNote(["2024-03-31", "2024-04-30", "2024-05-31"], locale: english)
            == "Shown as recorded: Mar – May 2024 have no inflation values yet.")
        #expect(PlanMoney.missingInflationNote(["2024-03-31", "2025-08-31"], locale: english)
            == "Shown as recorded: 2 months between Mar 2024 and Aug 2025 have no inflation values yet.")
        #expect(PlanMoney.pastAsRecordedNote([], locale: english) == nil)
        #expect(PlanMoney.pastAsRecordedNote(["2024-03-31", "2024-04-30"], locale: english)
            == "Your past is as recorded, not in today's money like the futures: "
            + "Mar – Apr 2024 have no inflation values yet.")
    }
}
