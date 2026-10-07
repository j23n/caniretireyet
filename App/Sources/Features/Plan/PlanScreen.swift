import Model
import SwiftUI

/// One plan (UI.md, "Plan"): a plan picker (New, Duplicate, Rename, Delete,
/// Set as main plan, Export Calculations), then Plan and Progress.
///
/// - **Plan**: the answer, your life as a strip of chapters with one graph
///   running through them, the chosen chapter in words with its settings,
///   and the assumptions every chapter shares.
/// - **Progress**: whether you're on track, and each year as a card on a
///   strip that opens at today, with its story below.
///
/// On iPhone (tabs) a segmented Plan | Progress, and What-if is a bottom
/// sheet; on the Mac and iPad (sidebar) the same in the toolbar, and
/// What-if in the inspector.
///
/// The plan is calculated only on request: *Calculate* / *Recalculate* in
/// the results, the toolbar and the Plan menu (⌘R), *Run What-If*.
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: "Plan"
        case .progress: "Progress"
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
            if library.settings.mainPlan == nil { try library.setMainPlan(plan.id) }
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
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @State private var session: PlanSession
    @State private var part: PlanPart = .plan
    @State private var showsInspector = false
    @State private var showsWhatIf = false
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
    private var isWide: Bool { navigation.layout == .sidebar }

    private var name: String { session.plan?.name ?? "Plan" }

    private var inspectorTitle: String { showsWhatIfColumn ? "Hide What If" : "Show What If" }

    /// What if beside the plan (the Mac and iPad): only with the plan, whose
    /// answer it changes.
    private var showsWhatIfColumn: Bool { showsInspector && part == .plan }

    var body: some View {
        planLayout
            .environment(\.baseCurrency, session.currency)
            .navigationTitle(name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { planToolbar }
            .task(id: library.revision) {
                await session.refresh()
            }
            .task { takeRequests() }
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, Metrics.l)
                        .padding(.vertical, Metrics.s)
                        .background(.regularMaterial, in: Capsule())
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

    /// A part, or What if, asked for at launch (``AppNavigation/requestedPlanPart``).
    private func takeRequests() {
        if let requested = navigation.requestedPlanPart {
            part = requested
        }
        if navigation.requestsWhatIf {
            if isWide { showsInspector = true } else { showsWhatIf = true }
        }
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

    /// iPhone: Plan | Progress.
    private var compactLayout: some View {
        compactPart
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

    @ViewBuilder
    private var compactPart: some View {
        switch part {
        case .plan:
            PlanTimelineView(session: session, isWide: false, onWhatIf: { showsWhatIf = true },
                             onShowProgress: { part = .progress }, onExport: { exportCalculations() })
        case .progress:
            PlanProgressView(session: session, isWide: false, onSaveBaseline: { startSavingBaseline() },
                             onShowPlan: { part = .plan })
        }
    }

    /// Mac and iPad: Plan | Progress, with What if in a column beside it.
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
            widePart
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

    @ViewBuilder
    private var widePart: some View {
        if part == .progress {
            PlanProgressView(session: session, isWide: true, onSaveBaseline: { startSavingBaseline() },
                             onShowPlan: { part = .plan })
        } else {
            // What if is in the toolbar.
            PlanTimelineView(session: session, isWide: true, besideWhatIf: showsWhatIfColumn,
                             onShowProgress: { part = .progress }, onExport: { exportCalculations() })
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var planToolbar: some ToolbarContent {
        ToolbarItem(placement: isWide ? .navigation : .principal) {
            planMenu
        }
        if isWide {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $part) {
                    Text("Plan").tag(PlanPart.plan)
                    Text("Progress").tag(PlanPart.progress)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    session.calculate()
                } label: {
                    // Not `session.state`: the toolbar mustn't redraw with every progress update.
                    Label(session.shownResults == nil ? "Calculate" : "Recalculate", systemImage: "arrow.clockwise")
                }
                .help("Calculate the plan with its inputs and your latest data (⌘R)")
                .disabled(!plans.isAvailable || session.isRunning)
                Button {
                    startSavingBaseline()
                } label: {
                    Label("Save Baseline…", systemImage: "bookmark")
                }
                .disabled(!library.canEdit)
                Button {
                    withAnimation(.snappy) {
                        // From Progress, What if opens with the plan.
                        if part == .progress {
                            part = .plan
                            showsInspector = true
                        } else {
                            showsInspector.toggle()
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
                .disabled(!plans.isAvailable)
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
        .accessibilityLabel(Text("Plan: \(name)"))
    }

    // MARK: Actions

    private func newPlan() {
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

    private func duplicate() {
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

    private func startSavingBaseline() {
        baselineLabel = ""
        isSavingBaseline = true
    }

    /// Export Calculations…: every calculation behind this plan's answer,
    /// with its what-if, as a Markdown file. Pending edits are saved first.
    private func exportCalculations() {
        guard plans.isAvailable else { return }
        session.saveNow()
        calculations = PlanCalculationsExport.source(session: session, library: library)
            .map(PlanCalculationsExport.init(source:))
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
    .previewEnvironment(model: AppModel.preview(planEngine: PlanPreviewEngine()))
}

#Preview("No plans") {
    NavigationStack {
        PlanScreen()
    }
    .previewEnvironment(PreviewLibrary.empty)
}
