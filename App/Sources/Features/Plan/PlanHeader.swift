import Glance
import Model
import Planner
import SwiftUI

// The plan's header (UI.md, "The plan"): its name, which is the plan menu,
// and its date. On iPhone a card with *Levers*, which shows the levers
// under it; on the Mac and iPad a header row with the plan's commands, and
// the date in a card of its own beside the levers, over the chance by age.

/// What the plan menu and the header's buttons do, from the screen that
/// shows the plan (``PlanContentView``).
struct PlanActions {
    var newPlan: () -> Void = {}
    var duplicate: () -> Void = {}
    var rename: () -> Void = {}
    var setMain: () -> Void = {}
    var exportCalculations: () -> Void = {}
    var delete: () -> Void = {}
}

/// "Base case ▾": the plans, and what you can do with this one: New Plan,
/// Duplicate, Rename…, Set as Main Plan, *Export Calculations…* under how
/// the results shown were calculated, and Delete….
struct PlanMenu: View {
    enum Style {
        /// Small and grey, over the date (iPhone).
        case caption
        /// The header row's title (the Mac and iPad).
        case title
    }

    let session: PlanSession
    let actions: PlanActions
    var style: Style = .caption

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
                .font(style == .caption ? Font.subheadline : Font.title3.weight(.bold))
                .foregroundStyle(style == .caption ? Palette.secondaryInk : Palette.ink)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

/// The plan's answer in words, as the header and the answer's card say it.
struct PlanAnswerWords {
    /// "27 March 2051", or "You could stop today" or "Not yet" without a
    /// date; `nil` without an answer.
    var date: String?
    /// The earliest age, with a date.
    var age: Int?
    /// "9 of 10".
    var futures = ""
    /// Why there's no date: "No age works out in 9 of 10 futures yet. Try
    /// the levers."
    var note: String?
    /// Without an answer: "Working out your date…", or "Your date shows
    /// here once the plan is calculated."
    var placeholder: String
    /// How far the levers moved the earliest age from the plan's own, in
    /// years; `nil` before they moved, or while their run is out of date.
    var leverYears: Int?
    /// Whether the date is an older answer: the results are out of date,
    /// or only the answer recorded at the last check-in is there.
    var dims = false

    init(session: PlanSession, locale: Locale) {
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
            note = "No age works out in \(futures) futures yet. Try the levers."
        }
        if session.hasWhatIf, !session.whatIfIsOutOfDate, session.baseIsUpToDate,
           let base = session.baseResults?.headline.earliestAge, let now = answer.earliestAge {
            leverYears = now - base
        }
    }

    /// "27 March 2051, at 63".
    var dateAndAge: String? {
        guard let date else { return nil }
        return age.map { "\(date), at \($0)" } ?? date
    }

    /// "A year sooner than the plan", "The same as the plan".
    var leverMove: String? {
        guard let years = leverYears else { return nil }
        if years == 0 { return "The same as the plan" }
        let count = abs(years) == 1 ? "A year" : "\(abs(years)) years"
        return "\(count) \(years < 0 ? "sooner" : "later") than the plan"
    }
}

/// How far the levers moved the date, as a small capsule: green when
/// sooner, amber when later.
struct PlanMoveChip: View {
    let years: Int
    let words: String

    var body: some View {
        let color = years == 0 ? Palette.secondaryInk : years < 0 ? Palette.positive : Palette.warning
        Label {
            Text(verbatim: words)
                .lineLimit(1)
        } icon: {
            Image(systemName: years == 0 ? "equal" : years < 0 ? "arrow.left" : "arrow.right")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, Metrics.s)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .fixedSize()
        .privacySensitiveInFeedback()
    }
}

// MARK: - iPhone

/// The plan's header on iPhone: the plan menu over the date, and *Levers*,
/// which shows the levers under the card. While the levers have moved, how
/// far they moved the date; while a calculation runs, its progress.
struct PlanHeaderCard: View {
    let session: PlanSession
    let actions: PlanActions
    @Binding var showsLevers: Bool

    @Environment(\.locale) private var locale

    var body: some View {
        let state = session.state
        let words = PlanAnswerWords(session: session, locale: locale)
        VStack(alignment: .leading, spacing: Metrics.s) {
            HStack(alignment: .center, spacing: Metrics.m) {
                VStack(alignment: .leading, spacing: 2) {
                    PlanMenu(session: session, actions: actions)
                    if let date = words.dateAndAge {
                        Text(verbatim: date)
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .opacity(words.dims ? Metrics.dimmedOpacity : 1)
                            .privacySensitiveInFeedback()
                            .accessibilityLabel(Text(verbatim: "\(date), in \(words.futures) futures"))
                    } else {
                        Text(words.placeholder)
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Metrics.s)
                leversButton
            }
            if let note = words.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
            }
            if let years = words.leverYears, let move = words.leverMove {
                PlanMoveChip(years: years, words: move)
            }
            if state.isRunning, !session.isRunningWhatIf, let progress = session.runProgress {
                PlanRunProgressView(progress: progress, isCheckIn: session.isCheckInRun,
                                    onCancel: session.isCheckInRun ? nil : { session.cancel() })
                    .padding(.top, Metrics.xs)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// *Levers*: tinted, or filled once a lever has moved.
    private var leversButton: some View {
        let moved = session.hasWhatIf
        return Button {
            withAnimation(.snappy) { showsLevers.toggle() }
        } label: {
            HStack(spacing: Metrics.xs) {
                Text("Levers")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(showsLevers ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(moved ? Color.white : Palette.accent)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(moved ? Palette.accent : Palette.accent.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityValue(showsLevers ? Text("Shown") : Text("Hidden"))
        .accessibilityHint("Shows the levers that move your date")
    }
}

// MARK: - Mac and iPad

/// The header row on the Mac and iPad: the plan menu as its title, how the
/// results shown were calculated, and the plan's commands: *Assumptions…*,
/// *Target Mix…*, *Duplicate* and *Save as Plan…*, which keeps the levers
/// where they are as a plan of its own once one has moved.
struct PlanWideHeader: View {
    let session: PlanSession
    let actions: PlanActions
    var onAssumptions: () -> Void = {}
    var onTargetMix: () -> Void = {}

    @Environment(PlusStore.self) private var plus
    @Environment(\.locale) private var locale
    @State private var isNaming = false

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.s) {
            VStack(alignment: .leading, spacing: 2) {
                PlanMenu(session: session, actions: actions, style: .title)
                Text(session.shownResults.map { PlanRunText.calculated($0, locale: locale) } ?? "Not calculated yet")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: Metrics.m)
            ViewThatFits(in: .horizontal) {
                buttons(all: true)
                buttons(all: false)
            }
        }
        .planSaveAsPlan(session: session, isPresented: $isNaming)
    }

    private func buttons(all: Bool) -> some View {
        HStack(spacing: Metrics.s) {
            if all {
                Button("Assumptions…", action: onAssumptions)
                Button("Target Mix…", action: onTargetMix)
                Button("Duplicate", action: actions.duplicate)
            }
            Button("Save as Plan…") {
                plus.unlock(.morePlans) { isNaming = true }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.hasWhatIf || !session.canEdit)
            .help("Keep the levers where they are as a plan of its own")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .fixedSize()
    }
}

/// The answer's card on the Mac and iPad: "Earliest last Monday, in 9 of 10
/// futures", the date large with the age beside it and how sure stopping at
/// the plan's own age is ("Stop at 55: 4 in 10"), or how far the levers
/// moved it; then the chance by retirement age. While a calculation runs,
/// its progress.
struct PlanAnswerCard: View {
    let session: PlanSession

    @Environment(\.locale) private var locale

    var body: some View {
        let state = session.state
        let words = PlanAnswerWords(session: session, locale: locale)
        VStack(alignment: .leading, spacing: Metrics.xs) {
            if let date = words.date {
                let eyebrow: String = session.hasWhatIf ? "With your levers, in \(words.futures) futures"
                    : "Earliest last Monday, in \(words.futures) futures"
                Text(verbatim: eyebrow)
                    .font(.subheadline)
                    .foregroundStyle(session.hasWhatIf ? Palette.accent : Palette.secondaryInk)
                    .lineLimit(1)
                    .privacySensitiveInFeedback()
                HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
                    Text(verbatim: date)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .opacity(words.dims ? Metrics.dimmedOpacity : 1)
                        .privacySensitiveInFeedback()
                    if let age = words.age {
                        Text(verbatim: "at \(age)")
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .fixedSize()
                            .privacySensitiveInFeedback()
                    }
                    if let years = words.leverYears, let move = words.leverMove {
                        PlanMoveChip(years: years, words: move)
                    } else if let target = targetChance(state.results) {
                        Text(verbatim: target)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                            .lineLimit(1)
                            .padding(.horizontal, Metrics.s)
                            .padding(.vertical, 3)
                            .background(Palette.accent.opacity(0.12), in: Capsule())
                            .fixedSize()
                            .privacySensitiveInFeedback()
                    }
                }
                if let note = words.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .privacySensitiveInFeedback()
                }
            } else {
                Text(words.placeholder)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.isRunning, !session.isRunningWhatIf, let progress = session.runProgress {
                PlanRunProgressView(progress: progress, isCheckIn: session.isCheckInRun,
                                    onCancel: session.isCheckInRun ? nil : { session.cancel() })
                    .padding(.top, Metrics.xs)
            }
            if let results = state.results {
                PlanSuccessChart(session: session, results: results)
                    .padding(.top, Metrics.s)
            }
        }
        .padding(.horizontal, Metrics.l)
        .padding(.vertical, Metrics.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface()
    }

    /// "Stop at 55: 4 in 10": how sure stopping at the plan's own age is,
    /// when that isn't the earliest age.
    private func targetChance(_ results: PlanResults?) -> String? {
        guard let headline = results?.headline, let target = headline.targetAge,
              let success = headline.successAtTarget, target != headline.earliestAge else { return nil }
        return "Stop at \(target): \(PlanTimelineText.tenths(success)) in 10"
    }
}

// MARK: - Save as Plan

extension View {
    /// *Save as Plan…*'s alert: a name for a new plan with the levers where
    /// they are ("Base case, changed" when left empty). The new plan opens,
    /// and this plan's levers reset.
    func planSaveAsPlan(session: PlanSession, isPresented: Binding<Bool>) -> some View {
        modifier(PlanSaveAsPlan(session: session, isPresented: isPresented))
    }
}

/// *Save as Plan…*'s alerts (``SwiftUI/View/planSaveAsPlan(session:isPresented:)``).
struct PlanSaveAsPlan: ViewModifier {
    let session: PlanSession
    @Binding var isPresented: Bool

    @Environment(AppNavigation.self) private var navigation
    @State private var newName = ""
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .alert("Save as plan", isPresented: $isPresented) {
                TextField("Name", text: $newName)
                Button("Save") { save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A new plan with the levers where they are. This plan stays as it was.")
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
            let id = try session.saveAsPlan(named: newName)
            navigation.showPlan(id)
        } catch {
            self.error = LibraryStore.describe(error)
        }
    }
}
