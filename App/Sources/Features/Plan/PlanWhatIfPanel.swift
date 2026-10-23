import Glance
import Model
import Planner
import SwiftUI

/// The levers (UI.md, "Plan"): when you stop working, spending and saving
/// a month, and what shares make above inflation, on top of the plan.
/// Moving one moves your date: once the levers rest, a quick estimate runs,
/// then every run, and the date above them follows. *Save as Plan…* keeps
/// the levers where they are as a plan of its own; *Reset* puts them back.
struct PlanLeversCard: View {
    let session: PlanSession

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @State private var isNaming = false
    @State private var newName = ""
    @State private var error: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.m) {
                if let model = session.whatIfModel {
                    ForEach(PlanWhatIfSlider.allCases) { slider in
                        sliderRow(slider, model: model, value: binding(slider))
                    }
                }
                actions
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Palette.critical)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            SectionHeader("Levers") {
                if session.isRunningWhatIf {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Updating your date")
                }
            }
        }
        #if os(iOS)
        // A light tap when the levers move the earliest age (UI.md, "Haptics").
        .sensoryFeedback(.selection, trigger: session.shownResults?.headline.earliestAge)
        #endif
        .alert("Save as plan", isPresented: $isNaming) {
            TextField("Name", text: $newName)
            Button("Save") { saveAsPlan() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A new plan with the levers where they are. This plan stays as it was.")
        }
    }

    /// *Reset* and *Save as Plan…*, once a lever has moved.
    @ViewBuilder
    private var actions: some View {
        if session.hasWhatIf {
            HStack(spacing: Metrics.m) {
                Button("Reset") { session.reset() }
                    .buttonStyle(.borderless)
                Spacer(minLength: 0)
                Button("Save as Plan…") {
                    newName = ""
                    error = nil
                    isNaming = true
                }
                .buttonStyle(.bordered)
                .disabled(!session.canEdit)
            }
            .font(.subheadline)
        } else {
            Text("Move a lever and your date follows.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveAsPlan() {
        do {
            let id = try session.saveAsPlan(named: newName)
            navigation.showPlan(id)
        } catch {
            self.error = LibraryStore.describe(error)
        }
    }

    /// The lever's value in the session: the value shown, and moving it
    /// moves the what-if (``PlanSession/set(_:to:)``).
    private func binding(_ slider: PlanWhatIfSlider) -> Binding<Double> {
        Binding(get: { session.whatIfModel?.value(slider) ?? 0 }, set: { session.set(slider, to: $0) })
    }

    private func sliderRow(_ slider: PlanWhatIfSlider, model: PlanWhatIfModel, value binding: Binding<Double>)
        -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(slider.title)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Metrics.s)
                value(slider, model: model)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(model.isChanged(slider) ? Palette.accent : Palette.ink)
            }
            Slider(value: binding, in: model.range(slider), step: slider.step)
                .disabled(!model.isAvailable(slider) || !session.canEdit)
                .accessibilityLabel(Text(slider.title))
        }
    }

    @ViewBuilder
    private func value(_ slider: PlanWhatIfSlider, model: PlanWhatIfModel) -> some View {
        let number = model.value(slider)
        switch slider {
        case .retirementAge:
            Text("\(Int(wholeNumber: number))")
                .monospacedDigit()
                .privacySensitiveInFeedback()
        case .spending, .saving:
            if model.isAvailable(slider) {
                HStack(spacing: 4) {
                    AmountText(Decimal(wholeNumber: number))
                    Text("a month")
                }
            } else {
                Text("Once calculated")
                    .foregroundStyle(Palette.secondaryInk)
            }
        case .equityReturn:
            Text("\(AmountFormat.percent(number, digits: 2, locale: locale)) a year")
                .monospacedDigit()
                .privacySensitiveInFeedback()
        }
    }
}

/// The plan's date on top of its levers: "27 March 2051, at 63", how sure,
/// and while the levers have moved, where the date was and how far it
/// moved ("A year sooner than the plan").
struct PlanDateHeader: View {
    let session: PlanSession

    @Environment(\.locale) private var locale

    var body: some View {
        let state = session.state
        VStack(alignment: .leading, spacing: Metrics.xs) {
            if let answer = state.results?.headline ?? state.recorded {
                let lastMonday = LastMonday(answer)
                Text(session.hasWhatIf ? "With your levers" : "Your last Monday at work")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(session.hasWhatIf ? Palette.accent : Palette.secondaryInk)
                Text(verbatim: headline(answer, lastMonday: lastMonday))
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .opacity(state.dimsResults ? Metrics.dimmedOpacity : 1)
                    .privacySensitiveInFeedback()
                Text(verbatim: line(answer))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
                if let move = leverMove(answer) {
                    TodayMoveChip(move: move, words: move.years == 0
                                  ? "The same as the plan"
                                  : "\(Self.years(abs(move.years))) \(move.isSooner ? "sooner" : "later") than the plan")
                }
            } else if state.isRunning {
                Text("Working out your date…")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                Text("Your date shows here once the plan is calculated.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.isRunning, !session.isRunningWhatIf, let progress = session.runProgress {
                PlanRunProgressView(progress: progress, isCheckIn: session.isCheckInRun,
                                    onCancel: session.isCheckInRun ? nil : { session.cancel() })
                    .padding(.top, Metrics.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "27 March 2051, at 63", "You could stop today", "Not yet".
    private func headline(_ answer: RetirementAnswer, lastMonday: LastMonday?) -> String {
        if let lastMonday {
            return "\(GlanceText.lastMonday(lastMonday.date, locale: locale)), at \(lastMonday.age)"
        }
        return answer.canRetireNow ? "You could stop today" : "Not yet"
    }

    /// "In 9 of 10 futures.", or why there's no date yet.
    private func line(_ answer: RetirementAnswer) -> String {
        let futures = GlanceText.futures(answer.confidence)
        if answer.canRetireNow || answer.earliestAge != nil { return "In \(futures) futures." }
        return "No age works out in \(futures) futures yet. Try the levers."
    }

    /// How far the levers moved the earliest age from the plan's own.
    private func leverMove(_ answer: RetirementAnswer) -> LastMondayMove? {
        guard session.hasWhatIf, !session.whatIfIsOutOfDate, session.baseIsUpToDate,
              let base = session.baseResults?.headline.earliestAge, let now = answer.earliestAge else { return nil }
        return LastMondayMove(since: .today(), years: now - base)
    }

    private static func years(_ count: Int) -> String {
        count == 1 ? "A year" : "\(count) years"
    }
}

#Preview("Levers") {
    PlanPreviewHost(model: AppModel.preview()) { session in
        ScrollView {
            VStack(spacing: Metrics.l) {
                PlanDateHeader(session: session)
                PlanLeversCard(session: session)
            }
            .padding()
        }
    }
}
