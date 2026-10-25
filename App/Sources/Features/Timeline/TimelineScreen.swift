import Model
import Planner
import SwiftUI

/// The Timeline (UI.md, "Timeline"): your money and your date over time,
/// at three zooms, always of the main plan.
///
/// - **Year**: one year, its check-ins, your money against what you
///   planned in January, and what moved your date (``PlanProgressView``).
/// - **Decades**: your records to now, then the plan's futures to its end
///   (``TimelineDecadesView``, ``DecadesChart``).
/// - **Look back**: your whole history by month, quarter or year: savings
///   rate, your date check-in by check-in, money in and out
///   (``PlanTrendsView``).
///
/// On iPhone the zoom is a segmented control under the large title; on the Mac
/// and iPad it's in the toolbar, with Look back's grain and span beside it.
struct TimelineScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans

    init() {}

    /// The main plan, else the first.
    private var plan: PlanDocument? {
        library.mainPlan ?? library.sortedPlans.first
    }

    var body: some View {
        Group {
            if let plan, !library.hasNoAccounts {
                TimelineContentView(planID: plan.id, library: library, plans: plans)
                    .id(plan.id)
            } else {
                ContentUnavailableView {
                    Label("Nothing to show yet", systemImage: AppSymbol.timeline)
                } description: {
                    Text(library.hasNoAccounts
                         ? "Your timeline starts with your first values. Import a file to add them."
                         : "Your timeline follows your main plan. Create one on the Plan tab.")
                }
                .background(Palette.page)
            }
        }
        .navigationTitle("Timeline")
    }
}

/// The Timeline of one plan, at the zoom the navigation asks for.
private struct TimelineContentView: View {
    let planID: PlanID

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.pageLayout) private var layout
    @State private var session: PlanSession

    init(planID: PlanID, library: LibraryStore, plans: PlanStore) {
        self.planID = planID
        _session = State(initialValue: PlanSession(planID: planID, library: library, plans: plans))
    }

    var body: some View {
        // A large title on iPhone, as on Today, with the zoom under it. The
        // title is drawn here: the system's large title doesn't show above
        // a pinned inset.
        zoomView
            #if os(iOS)
            .toolbar(layout.isWide ? .automatic : .hidden, for: .navigationBar)
            #endif
            .safeAreaInset(edge: .top, spacing: 0) {
                if !layout.isWide {
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        Text("Timeline")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, Metrics.s)
                        zoomPicker
                        if navigation.timelineZoom == .lookBack, library.library.accountsTurningOffTrends.isEmpty {
                            PlanTrendsControls()
                        }
                    }
                    .padding(.horizontal, Metrics.l)
                    .padding(.vertical, Metrics.s)
                    .background(Palette.page)
                }
            }
            .toolbar {
                if layout.isWide {
                    ToolbarItem(placement: .principal) {
                        zoomPicker
                            .fixedSize()
                    }
                    // Look Back's time span apart from the zoom, so the two
                    // don't read as one control.
                    if navigation.timelineZoom == .lookBack, library.library.accountsTurningOffTrends.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            PlanTrendsControls()
                                .fixedSize()
                        }
                    }
                }
            }
            .task(id: library.revision) {
                await session.refresh()
            }
            .onDisappear { session.saveNow() }
    }

    private var zoomPicker: some View {
        @Bindable var navigation = navigation
        return Picker("Zoom", selection: $navigation.timelineZoom) {
            ForEach(TimelineZoom.allCases) { zoom in
                Text(zoom.title).tag(zoom)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var zoomView: some View {
        @Bindable var navigation = navigation
        switch navigation.timelineZoom {
        case .year:
            PlanProgressView(session: session, onShowPlan: { navigation.showPlan(planID) },
                             openingYear: $navigation.timelineYear)
        case .decades:
            TimelineDecadesView(session: session)
        case .lookBack:
            PlanTrendsView(session: session)
        }
    }
}

#Preview("Timeline") {
    NavigationStack {
        TimelineScreen()
    }
    .previewEnvironment()
}
