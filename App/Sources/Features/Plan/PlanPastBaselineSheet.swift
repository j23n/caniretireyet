import Model
import SwiftUI
import Tracker

/// *Add Past Baseline…* (PROGRESS.md, "Past baselines"): what you planned on
/// a day before you used the app. You pick the day and say what you planned
/// then (pay, spending, when to stop working, spending in retirement, a
/// month each); the rest is today's plan. The app calculates it from your
/// plan assets that day and saves it, and the years without their own
/// baseline are measured against it.
struct PlanPastBaselineSheet: View {
    let session: PlanSession

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// The plan as you had it then: a copy of today's.
    @State private var draft: PlanDocument
    @State private var day: Date
    @State private var name = ""
    @State private var isSaving = false
    @State private var failure: String?

    /// - Parameter day: the day it starts on, when a year asked for it (its
    ///   first); else today. Out of range, it moves into it (``chooseDay()``).
    init(session: PlanSession, plan: PlanDocument, startingOn day: CalendarDate? = nil) {
        self.session = session
        _draft = State(initialValue: plan)
        _day = State(initialValue: day?.dateValue ?? Date())
    }

    /// The days it can start on: from the first record of a plan asset to the latest check-in.
    private var range: ClosedRange<Date>? {
        let valuator = library.valuator
        guard let first = valuator.firstValuationDate(in: .planAssets),
              let latest = valuator.checkInDates(in: .planAssets).last, first <= latest else { return nil }
        return first.dateValue...latest.dateValue
    }

    private var start: CalendarDate { CalendarDate(day, in: .current) }

    private var currency: CurrencyCode { session.currency }

    var body: some View {
        NavigationStack {
            Form {
                if let range {
                    Section {
                        DatePicker("Planned on", selection: $day, in: range, displayedComponents: .date)
                        LabeledContent("Plan assets then") {
                            AmountText(library.valuator.total(on: start, in: .planAssets).total, currency: currency)
                        }
                    } footer: {
                        Text("The plan starts from your plan assets on this day, as your history values them.")
                    }
                    Section {
                        if !draft.work.isEmpty {
                            PlanNumberRow("Take-home pay",
                                          value: $draft.work[planSafe: 0, default: draft.work[0]].netIncome.perMonth,
                                          unit: "/month")
                        }
                        PlanNumberRow("Spending while working", value: $draft.spending.working.perMonth,
                                      unit: "/month")
                        Toggle("Stop working as early as you can", isOn: $draft.planRetiresEarliest)
                        if !draft.planRetiresEarliest {
                            Stepper("Stop working at \(draft.planRetirementAge)", value: $draft.planRetirementAge,
                                    in: 30...85)
                        }
                        PlanNumberRow("Spending in retirement", value: $draft.spending.retired.perMonth,
                                      unit: "/month")
                    } header: {
                        Text("What you planned then")
                    } footer: {
                        Text("A month, in \(PlanMoney.todaysMoney(currency)). Returns, taxes, pensions, events and "
                            + "the rest are as in today's plan.")
                    }
                    Section {
                        TextField("Name", text: $name, prompt: Text(defaultName))
                    } footer: {
                        Text("Calculated with today's planner, so it's labelled as added later.")
                    }
                } else {
                    Section {
                        Text("A past baseline starts on a day your history has values for. Add your history first.")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                if let failure {
                    Section {
                        PlanIssueLine(message: failure, isError: true)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Past Baseline")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Calculate and Save") { save() }
                            .disabled(range == nil)
                    }
                }
            }
        }
        .onAppear(perform: chooseDay)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    /// "What I planned in 2021".
    private var defaultName: String {
        "What I planned in \(start.year)"
    }

    /// Keeps the day it was opened on when it's in range; else starts on
    /// the end of the first month with a record, or the first record when
    /// the day asked for is before it.
    private func chooseDay() {
        guard let range, !range.contains(day) else { return }
        let first = CalendarDate(range.lowerBound, in: .current)
        day = day < range.lowerBound ? range.lowerBound : min(first.yearMonth.lastDay.dateValue, range.upperBound)
    }

    private func save() {
        let day = start
        var past = draft
        // The work you did then pays from that day, even if today's job started later.
        if !past.work.isEmpty, past.work[0].from > day {
            past.work[0].from = day
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? defaultName : trimmed
        isSaving = true
        failure = nil
        Task {
            do {
                try await plans.savePastBaseline(for: session.planID, document: past, from: day, label: label)
                dismiss()
            } catch {
                failure = PlanStore.describe(error)
                isSaving = false
            }
        }
    }
}
