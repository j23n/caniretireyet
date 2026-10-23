import Model
import Planner
import SwiftUI

/// After an import, on Done (UI.md, "Import", "After an import"): the
/// starting estimates the imported accounts can replace, each ticked, with
/// *Replace Estimates*, and the answer that follows. Replacing closes each
/// estimate the day before the real values start, continued by them, or
/// removes it when they reach back to its day, in one edit with a backup;
/// the main plan then runs and records its answer, which shows here with
/// how it moved from the first sketch.
///
/// The first import into a library without an answer runs the main plan
/// on its own, as the tour does. An import opened from a check-in leaves
/// the answer to the check-in.
struct ImportAnswerFollowUp: View {
    enum Style { case section, card }

    let model: ImportController
    let receipt: ImportReceipt
    var style: Style = .card

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.importClose) private var close
    @Environment(\.locale) private var locale
    @State private var unticked: Set<AccountID> = []
    @State private var isReplacing = false
    @State private var error: String?
    /// Whether this Done started the answer shown.
    @State private var startedAnswer = false
    /// The main plan's answer before the estimates were replaced.
    @State private var before: RetirementAnswer?

    var body: some View {
        Group {
            if isOffered {
                switch style {
                case .section:
                    Section {
                        content
                    } header: {
                        Text(header)
                    }
                case .card:
                    VStack(alignment: .leading, spacing: Metrics.m) {
                        Text(header)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.secondaryInk)
                            .accessibilityAddTraits(.isHeader)
                        content
                    }
                    .padding(Metrics.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.card,
                                in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1)
                    }
                }
            }
        }
        .task(id: receipt) { answerFirstImport() }
    }

    // MARK: What's offered

    /// Whether the import counts: it changed something, isn't undone, and
    /// isn't a check-in's.
    private var importCounts: Bool {
        receipt.hasChanges && !receipt.isUndone && model.flow.checkIn == nil
    }

    private var isOffered: Bool {
        importCounts && (!replaceable.isEmpty || startedAnswer)
    }

    /// The open estimates the library's real accounts can replace.
    private var replaceable: [Account] {
        guard !startedAnswer else { return [] }
        return library.library.openStartingEstimates.filter { library.library.replacement(of: $0) != nil }
    }

    private var header: String {
        startedAnswer ? "Your answer" : "Your round amounts"
    }

    @ViewBuilder
    private var content: some View {
        if startedAnswer {
            answer
        } else {
            estimates
        }
    }

    // MARK: Replacing estimates

    @ViewBuilder
    private var estimates: some View {
        Text("These accounts started as round amounts. Replace them with the accounts this import brought in, "
            + "and your answer is calculated again.")
            .font(.callout)
            .foregroundStyle(Palette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        ForEach(replaceable) { estimate in
            Toggle(isOn: Binding(get: { !unticked.contains(estimate.id) }, set: { isOn in
                if isOn { unticked.remove(estimate.id) } else { unticked.insert(estimate.id) }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(estimate.name)
                        .foregroundStyle(Palette.ink)
                    Text(Self.replacedBy(library.library.accountsReplacing(estimate)))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .privacySensitiveInFeedback()
            }
        }
        if let error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(Palette.warning)
        }
        Button {
            Task { await replace() }
        } label: {
            if isReplacing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Replace Estimates")
            }
        }
        .buttonStyle(.bordered)
        .disabled(isReplacing || !library.canEdit || chosen.isEmpty)
    }

    private var chosen: [AccountID] {
        replaceable.map(\.id).filter { !unticked.contains($0) }
    }

    /// "Replaced by Current account and Savings".
    static func replacedBy(_ accounts: [Account]) -> String {
        "Replaced by \(Wording.list(accounts.map(\.name)))"
    }

    private func replace() async {
        isReplacing = true
        defer { isReplacing = false }
        error = nil
        let estimates = chosen
        before = plans.mainHeadline
        do {
            try await library.replaceStartingEstimates(estimates)
            // Changes the receipt, which restarts the first-import task;
            // `runAnswer()` runs the plan once either way.
            model.noteEstimatesReplaced()
            await library.waitForPendingWrites()
            runAnswer()
        } catch {
            self.error = LibraryStore.describe(error)
        }
    }

    // MARK: The answer

    /// The first import into a library with a plan and no answer yet runs
    /// it, unless estimates wait to be replaced first.
    private func answerFirstImport() {
        guard importCounts, !startedAnswer, replaceable.isEmpty, library.canEdit,
              let main = library.settings.mainPlan, library.library.plans[main] != nil,
              library.library.headlines(for: main).isEmpty, plans.checkInAnswer?.isRunning != true
        else { return }
        runAnswer()
    }

    private func runAnswer() {
        guard !startedAnswer, let date = library.latestCheckIn else { return }
        startedAnswer = true
        plans.recordCheckInAnswer(on: date)
    }

    @ViewBuilder
    private var answer: some View {
        if let run = plans.checkInAnswer, let headline = run.headline {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(verbatim: OnboardingText.revealLead(headline) + " "
                     + OnboardingText.revealTitle(headline, locale: locale))
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(OnboardingText.revealLine(headline))
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                if let change = Self.change(from: before, to: headline) {
                    Text(change)
                        .font(.callout)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .privacySensitiveInFeedback()
            // Inside the tour, Today comes after its last step.
            if !navigation.finishesOnboarding {
                Button("Open Plan", action: openPlan)
                    .buttonStyle(.bordered)
            }
        } else if let run = plans.checkInAnswer, run.isRunning {
            HStack(spacing: Metrics.m) {
                ProgressView()
                    .controlSize(.small)
                Text("Calculating your plan with the new values…")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryInk)
            }
        } else {
            Text(plans.checkInAnswer?.error ?? "Your plan couldn't be calculated.")
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "2 years sooner than your first sketch", "The same age as your
    /// first sketch"; `nil` without an earlier answer to compare.
    static func change(from before: RetirementAnswer?, to now: RetirementAnswer) -> String? {
        guard let then = before?.earliestAge, let age = now.earliestAge else { return nil }
        if then == age { return "The same age as your first sketch." }
        let years = abs(age - then)
        let count = years == 1 ? "A year" : "\(years) years"
        return "\(count) \(age < then ? "sooner" : "later") than your first sketch."
    }

    private func openPlan() {
        let navigation = navigation
        if let close {
            close()
        } else {
            model.startOver()
        }
        navigation.showPlan()
    }
}
