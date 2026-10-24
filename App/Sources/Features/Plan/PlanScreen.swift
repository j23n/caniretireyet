import Model
import SwiftUI

/// One plan (UI.md, "Plan"): its name, which is the plan menu (New,
/// Duplicate, Rename, Set as main plan, Export Calculations, Delete), your
/// date and the levers, your chapters, the key numbers and *Assumptions*,
/// what every chapter shares. How you've been doing is on the Timeline.
///
/// *New Plan* and *Duplicate*, moving the levers and *Save as Plan…*, and
/// *Export Calculations…* come with Plus; without it they open the paywall
/// (``PlusStore/unlock(_:then:)``, UI.md "Plus"). Every plan stays open to
/// read, edit and calculate.
///
/// Created by the navigation as `PlanScreen(planID:)`; `nil` is the main plan.
struct PlanScreen: View {
    let planID: PlanID?

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans

    init(planID: PlanID? = nil) {
        self.planID = planID
    }

    /// The plan shown: the one asked for, or the main plan, or the first.
    private var plan: PlanDocument? {
        if let planID, let plan = library.library.plans[planID] { return plan }
        return library.mainPlan ?? library.sortedPlans.first
    }

    var body: some View {
        if let plan {
            PlanContentView(planID: plan.id, library: library, plans: plans)
                .id(plan.id)
        } else {
            PlanEmptyView()
        }
    }
}

/// No plans yet: one clear next step.
struct PlanEmptyView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @State private var error: String?

    var body: some View {
        ContentUnavailableView {
            Label("No plans yet", systemImage: AppSymbol.plan)
        } description: {
            Text(error ?? "A plan starts from your latest check-in and answers: can I retire yet?")
                .privacySensitiveInFeedback(error != nil)
        } actions: {
            Button("Create your first plan") { create() }
                .buttonStyle(.borderedProminent)
                .disabled(!library.canEdit)
        }
        .navigationTitle("Plan")
    }

    private func create() {
        let plan = PlanEditing.newPlan(id: library.newPlanID(for: "Base case"), name: "Base case",
                                       library: library.library, asOf: library.asOfDate)
        do {
            try library.save(plan)
            if library.needsMainPlan { try library.setMainPlan(plan.id) }
            navigation.showPlan(plan.id)
        } catch {
            self.error = LibraryStore.describe(error)
        }
    }
}

/// A plan on screen, laid out for the navigation it's in.
struct PlanContentView: View {
    let planID: PlanID

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(PlusStore.self) private var plus
    @Environment(\.pageLayout) private var layout
    @State private var session: PlanSession
    @State private var showsTargetMix = false
    @State private var isRenaming = false
    @State private var isDeleting = false
    @State private var calculations: PlanCalculationsExport?
    @State private var newName = ""
    @State private var message: String?

    init(planID: PlanID, library: LibraryStore, plans: PlanStore) {
        self.planID = planID
        _session = State(initialValue: PlanSession(planID: planID, library: library, plans: plans))
    }

    /// The sidebar layout (Mac, iPad).
    private var isWide: Bool { layout.isWide }

    private var name: String { session.plan?.name ?? "Plan" }

    var body: some View {
        planLayout
            .personalNavigationTitle(name, hidden: "Plan")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            // On iPhone the header card names the plan and holds its menu.
            .toolbar(isWide ? .automatic : .hidden, for: .navigationBar)
            #endif
            .toolbar { planToolbar }
            .task(id: library.revision) {
                await session.refresh()
            }
            .task { takeRoute() }
            .onChange(of: navigation.planRoute) { takeRoute() }
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, Metrics.l)
                        .padding(.vertical, Metrics.s)
                        .background(.regularMaterial, in: Capsule())
                        .privacySensitiveInFeedback()
                        .padding(Metrics.l)
                        .transition(.opacity)
                }
            }
            .task(id: message) {
                guard message != nil else { return }
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation { message = nil }
            }
            .alert("Rename plan", isPresented: $isRenaming) {
                TextField("Name", text: $newName)
                Button("Rename") { rename() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Delete “\(name)”?", isPresented: $isDeleting, titleVisibility: .visible) {
                Button("Delete Plan", role: .destructive) { delete() }
            } message: {
                Text("The dates it worked out at your check-ins stay in the library.")
            }
            .sheet(item: $calculations) { export in
                PlanCalculationsSheet(export: export)
            }
            .focusedSceneValue(\.planActions, PlanCommandActions(
                duplicate: { duplicate() },
                recalculate: { session.calculate() },
                exportCalculations: { exportCalculations() }))
            .onDisappear { session.saveNow() }
    }

    /// Opens where ``AppNavigation/planRoute`` asks, once, when it's for
    /// this plan: e.g. the Target mix sheet from a screenshot's launch.
    private func takeRoute() {
        guard let route = navigation.planRoute, planID == route.plan ?? library.settings.mainPlan else { return }
        navigation.planRoute = nil
        if route.opensTargetMix { showsTargetMix = true }
    }

    // MARK: Layouts

    /// The plan. On the Mac the page has a fixed minimum
    /// (``FixedMinimumSize``), as the window's root has: measured through
    /// the page, its minimum moved as the page laid out for the width it
    /// got, and never settled ("needing another Update Constraints in
    /// Window pass").
    @ViewBuilder
    private var planLayout: some View {
        let page = PlanTimelineView(session: session, showsTargetMix: $showsTargetMix, actions: planActions)
            .environment(\.pageLayout, PageLayout(isWide: isWide))
        if isWide {
            page
                .fixedMinimumSize(width: 320, height: 300)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            page
        }
    }

    // MARK: Toolbar

    /// *Calculate* or *Recalculate* on the Mac and iPad. The plan menu is the
    /// page's title (``PlanMenu``); on iPhone the page has no bar.
    @ToolbarContentBuilder
    private var planToolbar: some ToolbarContent {
        if isWide {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    session.calculate()
                } label: {
                    // Not the run's progress: the toolbar mustn't redraw with every progress update.
                    Label(session.shownResults == nil ? "Calculate" : "Recalculate", systemImage: "arrow.clockwise")
                }
                .help("Calculate the plan with its inputs and your latest data (⌘R)")
                .disabled(session.isRunning)
            }
        }
    }

    /// What the plan menu (Base case ▾) and the header's buttons do.
    private var planActions: PlanActions {
        PlanActions(
            newPlan: { newPlan() },
            duplicate: { duplicate() },
            rename: {
                newName = name
                isRenaming = true
            },
            setMain: { setMain() },
            exportCalculations: { exportCalculations() },
            delete: { isDeleting = true })
    }

    // MARK: Actions

    /// *New Plan*: a second plan, and every one after it, comes with Plus.
    private func newPlan() {
        plus.unlock(.morePlans) { createPlan() }
    }

    private func createPlan() {
        let name = PlanEditing.uniqueName("New plan", among: library.library.plans.values)
        let plan = PlanEditing.newPlan(id: library.newPlanID(for: name), name: name, library: library.library,
                                       asOf: library.asOfDate)
        do {
            try library.save(plan)
            navigation.showPlan(plan.id)
        } catch {
            message = LibraryStore.describe(error)
        }
    }

    /// *Duplicate*: another plan, so it comes with Plus.
    private func duplicate() {
        plus.unlock(.morePlans) { duplicatePlan() }
    }

    private func duplicatePlan() {
        session.saveNow()
        do {
            let copy = try library.duplicatePlan(planID)
            navigation.showPlan(copy)
        } catch {
            message = LibraryStore.describe(error)
        }
    }

    private func rename() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.edit { $0.name = trimmed }
        session.saveNow()
    }

    private func setMain() {
        do {
            try library.setMainPlan(planID)
            message = "“\(name)” is now the main plan."
        } catch {
            message = LibraryStore.describe(error)
        }
    }

    private func delete() {
        session.saveNow()
        do {
            try library.deletePlan(planID)
            if let next = library.sortedPlans.first {
                navigation.showPlan(next.id)
            } else {
                navigation.selectedPlan = nil
                if isWide { navigation.showToday() }
            }
        } catch {
            message = LibraryStore.describe(error)
        }
    }

    /// Export Calculations…: every calculation behind this plan's answer,
    /// with its what-if, as a Markdown file, with Plus. Pending edits are
    /// saved first.
    private func exportCalculations() {
        plus.unlock(.exportCalculations) {
            session.saveNow()
            calculations = PlanCalculationsExport.source(session: session, library: library)
                .map(PlanCalculationsExport.init(source:))
        }
    }
}

#Preview("Plan") {
    NavigationStack {
        PlanScreen()
    }
    .previewEnvironment()
}

#Preview("No plans") {
    NavigationStack {
        PlanScreen()
    }
    .previewEnvironment(PreviewLibrary.empty)
}
