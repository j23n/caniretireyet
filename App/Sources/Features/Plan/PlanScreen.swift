import Model
import SwiftUI

/// One plan (UI.md, "Plan"): a plan picker (New, Duplicate, Rename, Delete,
/// Set as main plan, Export Calculations), then Plan, Progress and Trends.
///
/// - **Plan**: the answer, your life as a strip of chapters with one graph
///   running through them, the chosen chapter in words with its settings,
///   and *Assumptions…*, what every chapter shares.
/// - **Progress**: whether you're on track, and each year as a card on a
///   strip that opens at today, with its story below.
/// - **Trends**: how you've actually been doing over your whole history:
///   where your money came from, the answer at each check-in, and each year
///   graded in words; a year opens on Progress.
///
/// On iPhone (tabs) a segmented Plan | Progress | Trends, and What-if is a
/// bottom sheet; on the Mac and iPad (sidebar) the same in the toolbar,
/// with Trends' grain and span beside it, and What-if in a column beside
/// the plan.
///
/// The plan is calculated only on request: *Calculate* / *Recalculate* in
/// the results, the toolbar and the Plan menu (⌘R), *Run What-If*.
///
/// *New Plan* and *Duplicate*, What if, *Save Baseline…* and *Export
/// Calculations…* come with Plus; without it they open the paywall
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

/// The parts of a plan.
enum PlanPart: String, CaseIterable, Hashable, Identifiable {
    case plan
    case progress
    case trends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: "Plan"
        case .progress: "Progress"
        case .trends: "Trends"
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
    @Environment(\.locale) private var locale
    @State private var session: PlanSession
    @State private var part: PlanPart = .plan
    /// The year Progress opens on, from a row of Trends' *Year by year*.
    @State private var progressYear: Int?
    @State private var showsInspector = false
    @State private var showsWhatIf = false
    @State private var showsTargetMix = false
    @State private var isRenaming = false
    @State private var isDeleting = false
    @State private var isSavingBaseline = false
    @State private var calculations: PlanCalculationsExport?
    @State private var newName = ""
    @State private var baselineLabel = ""
    @State private var message: String?

    init(planID: PlanID, library: LibraryStore, plans: PlanStore) {
        self.planID = planID
        _session = State(initialValue: PlanSession(planID: planID, library: library, plans: plans))
    }

    /// The sidebar layout (Mac, iPad): What-if in the inspector.
    private var isWide: Bool { layout.isWide }

    private var name: String { session.plan?.name ?? "Plan" }

    private var inspectorTitle: String { showsWhatIfColumn ? "Hide What If" : "Show What If" }

    /// What if beside the plan (the Mac and iPad): only with the plan, whose
    /// answer it changes.
    private var showsWhatIfColumn: Bool { showsInspector && part == .plan }

    var body: some View {
        planLayout
            .personalNavigationTitle(name, hidden: "Plan")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
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
            .alert("Save baseline", isPresented: $isSavingBaseline) {
                TextField("Label, e.g. Before going part-time", text: $baselineLabel)
                Button("Save") { saveBaseline() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A baseline remembers this projection, so you can compare your actual numbers against it later.")
            }
            .confirmationDialog("Delete “\(name)”?", isPresented: $isDeleting, titleVisibility: .visible) {
                Button("Delete Plan", role: .destructive) { delete() }
            } message: {
                Text("Its saved baselines and recorded answers stay in the library.")
            }
            .sheet(item: $calculations) { export in
                PlanCalculationsSheet(export: export)
            }
            .focusedSceneValue(\.planActions, PlanCommandActions(
                saveBaseline: { startSavingBaseline() },
                duplicate: { duplicate() },
                recalculate: { session.calculate() },
                exportCalculations: { exportCalculations() }))
            .onDisappear { session.saveNow() }
    }

    /// Opens where ``AppNavigation/planRoute`` asks, once, when it's for
    /// this plan: e.g. Progress from the Overview's *On track?*.
    private func takeRoute() {
        guard let route = navigation.planRoute, planID == route.plan ?? library.settings.mainPlan else { return }
        navigation.planRoute = nil
        part = route.part
        if route.opensWhatIf {
            plus.unlock(.whatIf) {
                if isWide { showsInspector = true } else { showsWhatIf = true }
            }
        }
        if route.opensTargetMix { showsTargetMix = true }
    }

    // MARK: Layouts

    @ViewBuilder
    private var planLayout: some View {
        if isWide {
            wideLayout
        } else {
            compactLayout
        }
    }

    /// iPhone: Plan | Progress | Trends.
    private var compactLayout: some View {
        partView
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Show", selection: $part) {
                    ForEach(PlanPart.allCases) { part in
                        Text(part.title).tag(part)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, Metrics.l)
                .padding(.vertical, Metrics.s)
                .background(Palette.page)
            }
            .sheet(isPresented: $showsWhatIf) {
                ScrollView {
                    PlanWhatIfPanel(session: session)
                        .padding(Metrics.l)
                }
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
            }
    }

    /// Opens the What-if sheet, on iPhone, with Plus; `nil` on the Mac and iPad.
    private var openWhatIfSheet: (() -> Void)? {
        guard !isWide else { return nil }
        return { plus.unlock(.whatIf) { showsWhatIf = true } }
    }

    /// The part shown. On iPhone *What if…* on the answer opens the
    /// What-if sheet; on the Mac and iPad What if is in the toolbar, and
    /// takes a column beside the plan, which narrows its page.
    @ViewBuilder
    private var partView: some View {
        switch part {
        case .plan:
            PlanTimelineView(session: session, showsTargetMix: $showsTargetMix,
                             onWhatIf: openWhatIfSheet, onShowProgress: { part = .progress },
                             onExport: { exportCalculations() })
                .environment(\.pageLayout, PageLayout(isWide: isWide, besideWhatIf: showsWhatIfColumn))
        case .progress:
            PlanProgressView(session: session, onSaveBaseline: { startSavingBaseline() },
                             onShowPlan: { part = .plan }, openingYear: $progressYear)
        case .trends:
            PlanTrendsView(session: session, onShowYear: showProgress(of:))
        }
    }

    /// Mac and iPad: Plan | Progress | Trends, with What if in a column
    /// beside the plan.
    ///
    /// On the Mac the page has a fixed minimum (``FixedMinimumSize``), as
    /// the window's root has: measured through the page, its minimum moved
    /// as the page laid out for the width it got (a strip, a row that
    /// wraps), and switching to Progress while the plan calculated never
    /// settled ("needing another Update Constraints in Window pass"). What
    /// if is a column of its own width beside it, not an inspector: the
    /// window's split view wouldn't narrow the page for the inspector,
    /// which then ran past the window's edge. The column scrolls, so its
    /// content doesn't move the minimum either.
    private var wideLayout: some View {
        HStack(spacing: 0) {
            partView
                .fixedMinimumSize(width: 320, height: 300)
                // Flexible, so the page takes what the column leaves.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if showsWhatIfColumn {
                Divider()
                PlanInspector(session: session)
                    .frame(width: PlanInspector.width)
                    .transition(.move(edge: .trailing))
            }
        }
    }

    /// Progress, opened on `year`.
    private func showProgress(of year: Int) {
        progressYear = year
        part = .progress
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var planToolbar: some ToolbarContent {
        ToolbarItem(placement: isWide ? .navigation : .principal) {
            planMenu
        }
        if isWide {
            ToolbarItem(placement: .principal) {
                HStack(spacing: Metrics.m) {
                    Picker("Show", selection: $part) {
                        ForEach(PlanPart.allCases) { part in
                            Text(part.title).tag(part)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    if part == .trends, library.library.accountsTurningOffTrends.isEmpty {
                        PlanTrendsControls()
                            .fixedSize()
                    }
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    session.calculate()
                } label: {
                    // Not the run's progress: the toolbar mustn't redraw with every progress update.
                    Label(session.shownResults == nil ? "Calculate" : "Recalculate", systemImage: "arrow.clockwise")
                }
                .help("Calculate the plan with its inputs and your latest data (⌘R)")
                .disabled(session.isRunning)
                Button {
                    startSavingBaseline()
                } label: {
                    Label("Save Baseline…", systemImage: "bookmark")
                }
                .disabled(!library.canEdit)
                Button {
                    if showsWhatIfColumn {
                        withAnimation(.snappy) { showsInspector = false }
                    } else {
                        // From Progress or Trends, What if opens with the plan.
                        plus.unlock(.whatIf) {
                            withAnimation(.snappy) {
                                part = .plan
                                showsInspector = true
                            }
                        }
                    }
                } label: {
                    Label(inspectorTitle, systemImage: "slider.horizontal.3")
                }
                .help("What if: try a change before you make it in the plan")
            }
        }
    }

    /// "Base case ▾": the plans, and what you can do with this one.
    private var planMenu: some View {
        Menu {
            Section("Plans") {
                ForEach(library.sortedPlans) { plan in
                    Button {
                        navigation.showPlan(plan.id)
                    } label: {
                        if plan.id == planID {
                            Label(plan.name, systemImage: "checkmark")
                        } else {
                            Text(plan.name)
                        }
                    }
                }
            }
            Section {
                Button {
                    newPlan()
                } label: {
                    Label("New Plan", systemImage: "plus")
                }
                Button {
                    duplicate()
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button {
                    newName = name
                    isRenaming = true
                } label: {
                    Label("Rename…", systemImage: "pencil")
                }
                Button {
                    setMain()
                } label: {
                    Label("Set as Main Plan", systemImage: "star")
                }
                .disabled(library.settings.mainPlan == planID)
                Button {
                    startSavingBaseline()
                } label: {
                    Label("Save Baseline…", systemImage: "bookmark")
                }
            }
            .disabled(!library.canEdit)
            // How the answer shown was calculated, above what's behind it.
            Section(session.shownResults.map { PlanRunText.calculated($0, locale: locale) } ?? "Not calculated yet") {
                Button {
                    exportCalculations()
                } label: {
                    Label("Export Calculations…", systemImage: "function")
                }
            }
            Section {
                Button(role: .destructive) {
                    isDeleting = true
                } label: {
                    Label("Delete…", systemImage: "trash")
                }
                .disabled(!library.canEdit)
            }
        } label: {
            HStack(spacing: Metrics.xs) {
                if library.settings.mainPlan == planID {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.accent)
                        .accessibilityLabel("Main plan")
                }
                Text(name)
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        // The label draws its own chevron; the toolbar would add a second one.
        .menuIndicator(.hidden)
        .personalControl()
        .accessibilityLabel(Text("Plan: \(name)"))
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
                if isWide { navigation.showOverview() }
            }
        } catch {
            message = LibraryStore.describe(error)
        }
    }

    /// *Save Baseline…*, with Plus. The yearly baselines check-ins save
    /// for the main plan don't need it.
    private func startSavingBaseline() {
        plus.unlock(.baselines) {
            baselineLabel = ""
            isSavingBaseline = true
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

    private func saveBaseline() {
        let label = baselineLabel
        Task {
            do {
                _ = try await session.saveBaseline(label: label)
                let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                message = trimmed.isEmpty ? "Baseline saved." : "Saved the baseline “\(trimmed)”."
            } catch {
                message = LibraryStore.describe(error)
            }
        }
    }
}

/// What if beside the plan on the Mac and iPad: its sliders and the answer they give.
struct PlanInspector: View {
    let session: PlanSession

    /// The column's width.
    static let width: CGFloat = 340

    var body: some View {
        ScrollView {
            PlanWhatIfPanel(session: session)
                .padding(Metrics.l)
        }
        .background(Palette.card)
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
