import Foundation
import Testing
@testable import CanIRetireYet

/// A plan's results are kept on the device and come back, up to date,
/// when the library opens again, without calculating (UI.md, "Calculating").
@MainActor
struct KeptResultsTests {
    @Test func keptResultsComeBackUpToDate() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeptResultsTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let main = try #require(PreviewLibrary.library.settings.mainPlan)

        let first = openLibrary(keepingResultsIn: folder)
        let results = await first.plans.run(main)
        #expect(results != nil)

        // The results are written just after the run, off the main thread:
        // the library opened again until they're there.
        var reopened: AppModel?
        for _ in 0..<40 {
            let model = openLibrary(keepingResultsIn: folder)
            await model.plans.restoreKeptResults()
            if model.plans.results[main] != nil {
                reopened = model
                break
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        let model = try #require(reopened, "The kept results didn't come back.")
        #expect(model.plans.staleReasons(of: main).isEmpty, "The kept results came back out of date.")
        #expect(!model.plans.isRunning(main))
    }

    /// The made-up library in memory, its results kept in `folder`.
    private func openLibrary(keepingResultsIn folder: URL) -> AppModel {
        let model = AppModel.preview(planEngine: PreviewPlanEngine(delay: .zero),
                                     planResults: PlanResultsArchive(root: folder), defaults: "kept-results-tests")
        model.plans.inMemoryLibrary = URL(fileURLWithPath: "/screen-tests/example", isDirectory: true)
        return model
    }
}
