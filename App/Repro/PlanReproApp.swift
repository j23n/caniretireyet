import Model
import SwiftUI

// TEMPORARY: a harness that plays the Plan screen's scenarios on a real
// planner run, to find the crash when switching to Progress during a
// calculation. Built only by App/repro.yml and .github/workflows/repro.yml.

@main
struct PlanReproApp: App {
    @State private var model = Repro.model(for: Repro.scenario)

    var body: some Scene {
        WindowGroup {
            ReproRoot(scenario: Repro.scenario)
                .previewEnvironment(model: model)
                .frame(minWidth: 900, minHeight: 700)
        }
    }
}

enum Repro {
    static var scenario: String {
        ProcessInfo.processInfo.environment["REPRO_SCENARIO"] ?? "switch"
    }

    /// The made-up library, with fewer runs, and for some scenarios without
    /// the plan's answers and baselines (a first check-in) or with one answer.
    @MainActor
    static func model(for scenario: String) -> AppModel {
        var library = PreviewLibrary.library
        for id in Array(library.plans.keys) {
            library.plans[id]?.simulation.runs = 800
        }
        let main: PlanID = library.settings.mainPlan ?? "base"
        switch scenario {
        case "checkIn", "checkInSwitch":
            library.projections[main] = nil
        case "single":
            let last = library.headlines(for: main).last
            library.projections[main] = PlanProjections(
                headlines: last.map { [$0.date.year: HeadlineFile(headlines: [$0])] } ?? [:])
        default:
            break
        }
        let defaults = UserDefaults(suiteName: "repro-\(scenario)") ?? .standard
        return AppModel(preferences: AppPreferences(defaults: defaults), privacy: PrivacySettings(defaults: defaults),
                        library: .inMemory(library), prices: PriceStore(service: nil),
                        planEngine: PlannerPlanEngine(), draftURL: nil)
    }

    static func say(_ text: String) {
        print("REPRO \(scenario): \(text)")
        fflush(stdout)
    }

    static func finish() -> Never {
        say("OK")
        exit(0)
    }
}

struct ReproRoot: View {
    let scenario: String

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @State private var part: PlanPart = .results
    @State private var session: PlanSession?

    #if os(macOS)
    private let isWide = true
    #else
    private let isWide = false
    #endif

    var body: some View {
        NavigationStack {
            if let session {
                ReproPlanContent(session: session, part: $part, isWide: isWide)
            } else {
                Text("Starting…")
            }
        }
        .task { await play() }
    }

    private var main: PlanID { library.settings.mainPlan ?? "base" }

    private func play() async {
        let session = PlanSession(planID: main, library: library, plans: plans)
        self.session = session
        Task {
            try? await Task.sleep(for: .seconds(240))
            Repro.say("TIMEOUT")
            exit(2)
        }
        try? await Task.sleep(for: .seconds(1))
        switch scenario {
        case "single":
            part = .progress
            try? await Task.sleep(for: .seconds(3))
        case "switch":
            session.calculate()
            await waitUntilRunning()
            try? await Task.sleep(for: .seconds(1))
            Repro.say("switching to Progress while running")
            part = .progress
            await waitUntilDone()
            Repro.say("run done on Progress")
            try? await Task.sleep(for: .seconds(2))
            part = .results
            try? await Task.sleep(for: .seconds(1))
        case "toggle":
            session.calculate()
            await waitUntilRunning()
            var count = 0
            while plans.isRunning(main) {
                part = part == .progress ? .results : .progress
                count += 1
                try? await Task.sleep(for: .milliseconds(400))
            }
            Repro.say("toggled \(count) times")
            try? await Task.sleep(for: .seconds(1))
        case "inputs":
            session.calculate()
            await waitUntilRunning()
            try? await Task.sleep(for: .seconds(1))
            part = .inputs
            try? await Task.sleep(for: .seconds(1))
            part = .progress
            await waitUntilDone()
            try? await Task.sleep(for: .seconds(1))
        case "checkIn":
            part = .progress
            try? await Task.sleep(for: .seconds(1))
            plans.recordCheckInAnswer(on: library.latestCheckIn ?? .today())
            while plans.checkInAnswer?.isRunning != false {
                try? await Task.sleep(for: .milliseconds(100))
            }
            Repro.say("check-in answer recorded: \(plans.checkInAnswer?.headline?.earliestAge.map(String.init) ?? "none")")
            try? await Task.sleep(for: .seconds(3))
        case "checkInSwitch":
            plans.recordCheckInAnswer(on: library.latestCheckIn ?? .today())
            try? await Task.sleep(for: .seconds(1))
            part = .progress
            while plans.checkInAnswer?.isRunning != false {
                try? await Task.sleep(for: .milliseconds(100))
            }
            Repro.say("check-in answer recorded")
            try? await Task.sleep(for: .seconds(3))
        case "whatIf":
            session.calculate()
            await waitUntilDone()
            session.set(.retirementAge, to: 50)
            session.runWhatIf()
            await waitUntilRunning()
            try? await Task.sleep(for: .seconds(1))
            part = .progress
            await waitUntilDone()
            try? await Task.sleep(for: .seconds(1))
        default:
            Repro.say("unknown scenario")
        }
        Repro.finish()
    }

    private func waitUntilRunning() async {
        while !plans.isRunning(main) {
            try? await Task.sleep(for: .milliseconds(20))
        }
        Repro.say("running")
    }

    private func waitUntilDone() async {
        while plans.isRunning(main) {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

/// `PlanContentView`'s layouts, with the part driven from outside.
struct ReproPlanContent: View {
    let session: PlanSession
    @Binding var part: PlanPart
    let isWide: Bool

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @State private var showsInspector = true
    @State private var showsWhatIf = false

    var body: some View {
        layout
            .environment(\.baseCurrency, session.currency)
            .navigationTitle(session.plan?.name ?? "Plan")
            .toolbar { toolbar }
            .task(id: library.revision) {
                await session.refresh()
            }
    }

    @ViewBuilder
    private var layout: some View {
        if isWide {
            widePart
                .inspector(isPresented: $showsInspector) {
                    PlanInspector(session: session)
                        .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
                }
        } else {
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
                }
        }
    }

    @ViewBuilder
    private var compactPart: some View {
        switch part {
        case .results:
            PlanResultsView(session: session, isWide: false, onWhatIf: { showsWhatIf = true })
        case .progress:
            PlanProgressView(session: session, isWide: false, onSaveBaseline: {})
        case .inputs:
            PlanInputsView(session: session)
        }
    }

    @ViewBuilder
    private var widePart: some View {
        if part == .progress {
            PlanProgressView(session: session, isWide: true, onSaveBaseline: {})
        } else {
            PlanResultsView(session: session, isWide: true)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
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
                    session.calculate()
                } label: {
                    Label(session.shownResults == nil ? "Calculate" : "Recalculate", systemImage: "arrow.clockwise")
                }
                .disabled(!plans.isAvailable || session.isRunning)
                Button {
                    showsInspector.toggle()
                } label: {
                    Label("Inputs", systemImage: "sidebar.trailing")
                }
            }
        }
    }
}
