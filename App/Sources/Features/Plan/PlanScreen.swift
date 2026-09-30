import Model
import SwiftUI

/// One plan (UI.md, "Plan"): a plan picker (New, Duplicate, Rename, Delete,
/// Set as main plan, Compare), then Results, Progress and Inputs.
///
/// - **iPhone** (tabs): a segmented Results | Progress | Inputs; What-if is a
///   bottom sheet; while editing Inputs a small pill keeps the answer in view.
/// - **Mac and iPad** (sidebar): Results | Progress in the content area and
///   Inputs with What-if in the inspector, so results update next to the
///   field being edited.
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
    case results
    case progress
    case inputs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .results: "Results"
        case .progress: "Progress"
        case .inputs: "Inputs"
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
                                       settings: library.settings, asOf: library.asOfDate,
                                       registry: AppTaxRegistry.standard)
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
    @State private var session: PlanSession
    @State private var part: PlanPart = .results
    @State private var showsInspector = true
    @State private var showsWhatIf = false
    @State private var isComparing = false
    @State private var isRenaming = false
    @State private var isDeleting = false
    @State private var isSavingBaseline = false
    @State private var newName = ""
    @State private var baselineLabel = ""
    @State private var message: String?

    init(planID: PlanID, library: LibraryStore, plans: PlanStore) {
        self.planID = planID
        _session = State(initialValue: PlanSession(planID: planID, library: library, plans: plans))
    }

    /// The sidebar layout (Mac, iPad): Inputs in the inspector.
    private var isWide: Bool { navigation.layout == .sidebar }

    private var name: String { session.plan?.name ?? "Plan" }

    private var inspectorTitle: String { showsInspector ? "Hide Inputs" : "Show Inputs" }

    var body: some View {
        planLayout
            .navigationTitle(name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { planToolbar }
            .task(id: library.revision) {
                await session.refresh()
            }
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
                TextField("Label, e.g. Before forfettario", text: $baselineLabel)
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
            .navigationDestination(isPresented: $isComparing) {
                PlanCompareScreen(firstID: planID)
            }
            .focusedSceneValue(\.planActions, PlanCommandActions(
                saveBaseline: { startSavingBaseline() },
                duplicate: { duplicate() },
                compare: { isComparing = true }))
            .onDisappear { session.saveNow() }
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

    /// iPhone: Results | Progress | Inputs.
    private var compactLayout: some View {
        compactPart
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: Metrics.s) {
                    Picker("Show", selection: $part) {
                        ForEach(PlanPart.allCases) { part in
                            Text(part.title).tag(part)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if part == .inputs {
                        PlanAnswerPill(session: session)
                    }
                }
                .padding(.horizontal, Metrics.l)
                .padding(.vertical, Metrics.s)
                .background(Palette.page)
            }
            .sheet(isPresented: $showsWhatIf) {
                ScrollView {
                    PlanWhatIfPanel(session: session, showsAnswer: true)
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
        case .results:
            PlanResultsView(session: session, isWide: false, onWhatIf: { showsWhatIf = true })
        case .progress:
            PlanProgressView(session: session, isWide: false, onSaveBaseline: { startSavingBaseline() })
        case .inputs:
            PlanInputsView(session: session)
        }
    }

    /// Mac and iPad: Results | Progress, with Inputs and What-if in the inspector.
    private var wideLayout: some View {
        widePart
            .inspector(isPresented: $showsInspector) {
                PlanInspector(session: session)
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
            }
    }

    @ViewBuilder
    private var widePart: some View {
        if part == .progress {
            PlanProgressView(session: session, isWide: true, onSaveBaseline: { startSavingBaseline() })
        } else {
            PlanResultsView(session: session, isWide: true)
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
                    Text("Results").tag(PlanPart.results)
                    Text("Progress").tag(PlanPart.progress)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isComparing = true
                } label: {
                    Label("Compare…", systemImage: "square.split.2x1")
                }
                .disabled(library.library.plans.count < 2)
                Button {
                    startSavingBaseline()
                } label: {
                    Label("Save Baseline…", systemImage: "bookmark")
                }
                .disabled(!library.canEdit)
                Button {
                    showsInspector.toggle()
                } label: {
                    Label(inspectorTitle, systemImage: "sidebar.trailing")
                }
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
                    isComparing = true
                } label: {
                    Label("Compare…", systemImage: "square.split.2x1")
                }
                .disabled(library.library.plans.count < 2)
                Button {
                    startSavingBaseline()
                } label: {
                    Label("Save Baseline…", systemImage: "bookmark")
                }
            }
            .disabled(!library.canEdit)
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
        .accessibilityLabel(Text("Plan: \(name)"))
    }

    // MARK: Actions

    private func newPlan() {
        let name = PlanEditing.uniqueName("New plan", among: library.library.plans.values)
        let plan = PlanEditing.newPlan(id: library.newPlanID(for: name), name: name, settings: library.settings,
                                       asOf: library.asOfDate, registry: AppTaxRegistry.standard)
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

/// The Mac's inspector: Inputs, with What-if pinned below.
struct PlanInspector: View {
    let session: PlanSession

    var body: some View {
        PlanInputsView(session: session, isInspector: true)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    PlanWhatIfPanel(session: session)
                        .padding(Metrics.m)
                }
                .background(.bar)
            }
    }
}

/// A small pill that keeps the answer in view while you edit (iPhone).
struct PlanAnswerPill: View {
    let session: PlanSession

    private var text: String {
        guard let results = session.shownResults else { return "No answer yet" }
        if results.headline.canRetireNow { return "Yes, today" }
        return results.headline.earliestAge.map { "Earliest \($0)" } ?? "No age reaches it yet"
    }

    var body: some View {
        HStack(spacing: Metrics.xs) {
            if session.isRunning {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(text)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .contentTransition(.numericText())
        .animation(.default, value: text)
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
