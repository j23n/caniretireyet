import Model
import SwiftUI

// PLACEHOLDER — Plan feature engineer: replace this screen's content (UI.md,
// "Plan": picker, Results, Progress, Inputs, what-if, comparing plans).
// Keep the name `PlanScreen` and `init(planID:)` (`nil` means the main
// plan): the Plan tab, the sidebar's plans and pushed `PlanID`s create it.
// Publish the plan menu commands with `.focusedSceneValue(\.planActions, …)`
// as below. Runs, results, headlines and baselines are in `PlanStore`.

/// One plan: its answer, charts and inputs.
struct PlanScreen: View {
    let planID: PlanID?

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @State private var message: String?

    init(planID: PlanID? = nil) {
        self.planID = planID
    }

    /// The plan shown: the one asked for, or the main plan, or the first.
    private var plan: PlanDocument? {
        if let planID, let plan = library.library.plans[planID] { return plan }
        return library.mainPlan ?? library.sortedPlans.first
    }

    var body: some View {
        Group {
            if let plan {
                content(for: plan)
            } else {
                ContentUnavailableView {
                    Label("No plans yet", systemImage: AppSymbol.plan)
                } description: {
                    Text("A plan starts from your latest check-in and answers: can I retire yet?")
                }
            }
        }
        .navigationTitle(plan?.name ?? "Plan")
    }

    private func content(for plan: PlanDocument) -> some View {
        let results = plans.results[plan.id]
        let recorded = plans.recordedHeadlines(for: plan.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                if !plans.isAvailable {
                    StatusBanner(.info, "The planner is coming",
                                 message: "Plans can't run in this version yet. Answers recorded at past check-ins are shown.")
                }
                if let message {
                    StatusBanner(.info, message)
                }
                Card("Can I retire yet?") {
                    if let headline = results?.headline ?? recorded.last.map({ PlanHeadline(recorded: $0) }) {
                        Text(headline.canRetireNow ? "Yes." : "Not yet.")
                            .font(.title2.weight(.semibold))
                        if let age = headline.earliestAge {
                            Text("Earliest at \(age), in \(Int((headline.confidence * 10).rounded())) of 10 simulated futures")
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    } else {
                        Text("No answer yet.").foregroundStyle(Palette.secondaryInk)
                    }
                    if plans.isAvailable {
                        Button(plans.isRunning(plan.id) ? "Running…" : "Run") {
                            Task { await plans.run(plan.id) }
                        }
                        .disabled(plans.isRunning(plan.id))
                    }
                }
                if let results {
                    Card("Chance of success by retirement age") {
                        SuccessCurveChart(points: results.successByAge, threshold: results.headline.confidence,
                                          highlightedAge: results.headline.earliestAge)
                    }
                    Card("Your money over time") {
                        FanChart(fan: results.portfolio, markers: results.markers)
                    }
                    Card("Retirement income · median") {
                        IncomeStackChart(segments: results.income, spending: results.spending)
                    }
                }
                if !recorded.isEmpty {
                    Card("Your answer over time") {
                        ForEach(recorded, id: \.date) { headline in
                            LabeledContent(AmountFormat.mediumDate(headline.date)) {
                                Text(headline.earliestAge.map { "Earliest \($0)" } ?? "No age reaches it")
                            }
                        }
                    }
                }
            }
            .padding(Metrics.l)
            .frame(maxWidth: Metrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .focusedSceneValue(\.planActions, actions(for: plan))
    }

    private func actions(for plan: PlanDocument) -> PlanCommandActions {
        PlanCommandActions(
            saveBaseline: {
                do {
                    let id = try plans.saveBaseline(for: plan.id, label: "Saved by hand")
                    message = "Saved baseline \(id)."
                } catch {
                    message = error.localizedDescription
                }
            },
            duplicate: {
                do {
                    let copy = try library.duplicatePlan(plan.id)
                    navigation.showPlan(copy)
                } catch {
                    message = error.localizedDescription
                }
            },
            compare: {
                message = "Comparing plans arrives with the Plan screens."
            })
    }
}

#Preview("Plan") {
    NavigationStack {
        PlanScreen()
    }
    .previewEnvironment()
}
