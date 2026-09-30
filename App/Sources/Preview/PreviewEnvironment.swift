import Model
import SwiftUI

extension View {
    /// Injects preview stores holding `library` (by default the made-up
    /// ``PreviewLibrary``) in memory: nothing is read or written, nothing
    /// is fetched, and plans run on ``PreviewPlanEngine``.
    ///
    ///     #Preview { OverviewScreen().previewEnvironment() }
    ///     #Preview("Empty") { OverviewScreen().previewEnvironment(PreviewLibrary.empty) }
    func previewEnvironment(_ library: Library = PreviewLibrary.library) -> some View {
        appEnvironment(AppModel.preview(library))
    }

    /// Injects the stores of an existing preview model, e.g. one set up with
    /// a check-in in progress.
    func previewEnvironment(model: AppModel) -> some View {
        appEnvironment(model)
    }
}

/// Runs the preview engine on a plan of ``PreviewLibrary`` and shows
/// `content` with the results, for previews of plan charts and screens.
///
///     #Preview { PreviewResultsView { results in FanChart(fan: results.portfolio) } }
struct PreviewResultsView<Content: View>: View {
    var plan: PlanID
    private let content: (PlanResults) -> Content
    @State private var results: PlanResults?

    init(plan: PlanID = "base", @ViewBuilder content: @escaping (PlanResults) -> Content) {
        self.plan = plan
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Metrics.l) {
                if let results {
                    content(results)
                } else {
                    ProgressView()
                }
            }
            .padding()
        }
        .background(Palette.page)
        .previewEnvironment()
        .task {
            let library = PreviewLibrary.library
            guard let document = library.plans[plan] else { return }
            let request = PlanRunRequest(plan: document, library: library, mode: .full, whatIf: nil,
                                         asOf: PreviewLibrary.latestCheckIn)
            results = try? await PreviewPlanEngine(delay: .zero).run(request)
        }
    }
}
