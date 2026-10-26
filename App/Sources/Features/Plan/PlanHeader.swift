import Glance
import Model
import Planner
import SwiftUI

// What Ahead's header shares (UI.md, "Ahead"): the plan menu, the plan's
// answer in words, and *Save as a New Plan…*.

/// What the plan menu and the header's buttons do, from the screen that
/// shows the plan (``PlanContentView``).
struct PlanActions {
    var newPlan: () -> Void = {}
    var duplicate: () -> Void = {}
    var rename: () -> Void = {}
    var setMain: () -> Void = {}
    var assumptions: () -> Void = {}
    var targetMix: () -> Void = {}
    var flexibleSpending: () -> Void = {}
    var exportCalculations: () -> Void = {}
    var delete: () -> Void = {}
}

/// "Base case ▾": the plans, and what you can do with this one: New Plan,
/// Duplicate, Rename…, Set as Main Plan; what every chapter shares,
/// *Assumptions…* (taxes among them), *Target Mix…* and *Flexible
/// Spending…*; *Export Calculations…* under how the results shown were
/// calculated; and Delete….
struct PlanMenu: View {
    let session: PlanSession
    let actions: PlanActions

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale

    private var name: String { session.plan?.name ?? "Plan" }
    private var isMain: Bool { library.settings.mainPlan == session.planID }

    var body: some View {
        Menu {
            Section("Plans") {
                ForEach(library.sortedPlans) { plan in
                    Button {
                        navigation.showPlan(plan.id)
                    } label: {
                        if plan.id == session.planID {
                            Label(plan.name, systemImage: "checkmark")
                        } else {
                            Text(plan.name)
                        }
                    }
                }
            }
            Section {
                Button(action: actions.newPlan) {
                    Label("New Plan", systemImage: "plus")
                }
                Button(action: actions.duplicate) {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                Button(action: actions.rename) {
                    Label("Rename…", systemImage: "pencil")
                }
                Button(action: actions.setMain) {
                    Label("Set as Main Plan", systemImage: "star")
                }
                .disabled(isMain)
            }
            .disabled(!library.canEdit)
            Section {
                Button(action: actions.assumptions) {
                    Label("Assumptions…", systemImage: "slider.horizontal.3")
                }
                Button(action: actions.targetMix) {
                    Label("Target Mix…", systemImage: "chart.pie")
                }
                Button(action: actions.flexibleSpending) {
                    Label("Flexible Spending…", systemImage: "arrow.down.right")
                }
                .disabled(!library.canEdit)
            }
            // How the answer shown was calculated, above what's behind it.
            Section(session.shownResults.map { PlanRunText.calculated($0, locale: locale) } ?? "Not calculated yet") {
                Button(action: actions.exportCalculations) {
                    Label("Export Calculations…", systemImage: "function")
                }
            }
            Section {
                Button(role: .destructive, action: actions.delete) {
                    Label("Delete…", systemImage: "trash")
                }
                .disabled(!library.canEdit)
            }
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .personalControl()
        .accessibilityLabel(Text("Plan: \(name)"))
    }

    private var label: some View {
        HStack(spacing: Metrics.xs) {
            if isMain {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("Main plan")
            }
            Text(name)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

/// The plan's answer in words, as Ahead's answer card says it.
struct PlanAnswerWords {
    /// "27 March 2051", or "You could stop today" or "Not yet" without a
    /// date; `nil` without an answer.
    var date: String?
    /// The earliest age, with a date.
    var age: Int?
    /// "9 of 10".
    var futures = ""
    /// Why there's no date: "No age works out in 9 of 10 futures yet. Try
    /// What if."
    var note: String?
    /// Without an answer: "Working out your date…", or "Your date shows
    /// here once the plan is calculated."
    var placeholder: String
    /// How far the levers moved the date from the plan's own; `nil` before
    /// they moved, or while their run is out of date.
    var leverMove: PlanDateMove?
    /// Whether the date is an older answer: the results are out of date,
    /// or only the answer recorded at the last check-in is there.
    var dims = false

    @MainActor init(session: PlanSession, locale: Locale) {
        let state = session.state
        placeholder = state.isRunning ? "Working out your date…" : "Your date shows here once the plan is calculated."
        guard let answer = state.results?.headline ?? state.recorded else { return }
        futures = GlanceText.futures(answer.confidence)
        dims = state.dimsResults || state.results == nil
        if let lastMonday = LastMonday(answer) {
            date = GlanceText.lastMonday(lastMonday.date, locale: locale)
            age = lastMonday.age
        } else {
            date = answer.canRetireNow ? "You could stop today" : "Not yet"
        }
        if !answer.canRetireNow, answer.earliestAge == nil {
            note = "No age works out in \(futures) futures yet. Try What if."
        }
        if session.hasWhatIf, !session.whatIfIsOutOfDate, session.baseIsUpToDate, let base = session.baseResults {
            leverMove = PlanDateMove(from: base.headline, to: answer)
        }
    }

    /// "27 March 2051, at 63".
    var dateAndAge: String? {
        guard let date else { return nil }
        return age.map { "\(date), at \($0)" } ?? date
    }
}

// MARK: - Save as Plan

extension View {
    /// *Save as a New Plan…*'s alert: a name for a new plan with the levers
    /// where they are, or with `document`, the plan with a change ("Base
    /// case, changed" when left empty). The new plan opens; with the levers,
    /// this plan's levers reset. `onSaved` follows a save.
    func planSaveAsPlan(session: PlanSession, isPresented: Binding<Bool>, document: PlanDocument? = nil,
                        onSaved: @escaping () -> Void = {}) -> some View {
        modifier(PlanSaveAsPlan(session: session, isPresented: isPresented, document: document, onSaved: onSaved))
    }
}

/// *Save as a New Plan…*'s alerts
/// (``SwiftUI/View/planSaveAsPlan(session:isPresented:document:onSaved:)``).
struct PlanSaveAsPlan: ViewModifier {
    let session: PlanSession
    @Binding var isPresented: Bool
    /// The plan with a change; `nil` saves the levers.
    let document: PlanDocument?
    let onSaved: () -> Void

    @Environment(AppNavigation.self) private var navigation
    @State private var newName = ""
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .alert("Save as a new plan", isPresented: $isPresented) {
                TextField("Name", text: $newName)
                Button("Save") { save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(document == nil ? "A new plan with the levers where they are. This plan stays as it was."
                     : "A new plan with this change. This plan stays as it was.")
            }
            .alert("The plan wasn't saved", isPresented: Binding(get: { error != nil },
                                                                 set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
            .onChange(of: isPresented) {
                if isPresented { newName = "" }
            }
    }

    private func save() {
        do {
            let id: PlanID
            if let document {
                id = try session.saveAsNewPlan(document, named: newName)
            } else {
                id = try session.saveAsPlan(named: newName)
            }
            onSaved()
            navigation.showPlan(id)
        } catch {
            self.error = LibraryStore.describe(error)
        }
    }
}
