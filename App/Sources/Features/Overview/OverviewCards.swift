import Glance
import Model
import Prices
import Storage
import SwiftUI
import Tracker

// The Overview's answer and its cards below the chart (UI.md, "Overview"):
// since the last check-in, this year, the answer before there is one, what
// needs attention, and the allocation.

// MARK: - Since last check-in

/// The change since the previous check-in (UI.md, "Since last check-in"),
/// which the hero number above says ("▲ +5.730 € in September"): the
/// totals before and after, and a bar each for markets, new money and
/// other, from a shared zero line (``WaterfallChart``). Titled by the month
/// it covers when the check-in before was the end of the month before.
struct OverviewChangeCard: View {
    let report: ChangeReport
    @Environment(\.locale) private var locale

    private var title: String {
        guard let month = GlanceText.coveredMonth(from: report.from, to: report.to) else {
            return "Since last check-in"
        }
        return "What moved in \(GlanceText.month(month, relativeTo: .today(), locale: locale))"
    }

    var body: some View {
        Card(title) {
            VStack(alignment: .leading, spacing: Metrics.m) {
                WaterfallChart(change: report.total,
                               from: AmountFormat.shortDate(report.from, relativeTo: .today(), locale: locale),
                               to: AmountFormat.shortDate(report.to, relativeTo: .today(), locale: locale),
                               showsChange: false)
                Text(Self.explanation(report.total))
                    .font(.footnote)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// What the bars mean, under them; *Other* only when there is some.
    static func explanation(_ change: ValueChange) -> String {
        var text = "Markets: prices, exchange rates and interest. New money: what you added or took out."
        if change.other != 0 {
            text += " Other: changes in accounts without new money recorded."
        }
        return text
    }
}

// MARK: - This year

/// How net worth changed since 31 December of last year (UI.md, "This
/// year"), split as *What moved* splits a check-in's change: markets, new
/// money and other, so what you saved stands apart from what markets did.
/// The hero says this year's change in per cent; this card leads with it
/// in money ("▲ +18.240 € since 31 Dec 2025"), and in per cent while
/// amounts are hidden.
struct OverviewYearCard: View {
    /// Tracker's `Valuator.changeThisYear(asOf:)`.
    let report: ChangeReport
    @Environment(\.locale) private var locale

    var body: some View {
        Card("This year") {
            VStack(alignment: .leading, spacing: Metrics.m) {
                WaterfallChart(change: report.total,
                               from: AmountFormat.shortDate(report.from, relativeTo: .today(), locale: locale),
                               to: AmountFormat.shortDate(report.to, relativeTo: .today(), locale: locale))
                Text(OverviewChangeCard.explanation(report.total))
                    .font(.footnote)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Can I retire yet?

/// "Can I retire yet?" (UI.md, "Overview"). With the main plan's answer
/// (its latest results, or the headline recorded at the last check-in) it
/// leads the screen, above net worth: "Not yet · earliest at 54", how long
/// to go, how close your plan assets are to what retiring today needs
/// (``PlanReadinessView``, with an ⓘ), and how you compare with the
/// baseline Progress measures its latest year against; tapping it opens
/// the plan, and *Calculate* runs the plan when the answer isn't current.
/// Without an answer it's a card below the chart with the next step:
/// *Create a plan*, or *Calculate* the main plan.
///
/// The answer opens the plan with a tap gesture rather than being a
/// button, so the ⓘ and *Calculate* inside it get their own taps; the
/// chevron is the button VoiceOver and keyboards use.
struct OverviewAnswerView: View {
    /// The main plan's answer (``PlanStore/mainHeadline``); `nil` without
    /// a main plan or before its first calculation.
    let headline: PlanHeadline?
    /// The day the Overview reports on.
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @State private var error: String?

    var body: some View {
        if let headline, let plan = library.mainPlan {
            hero(headline, plan: plan)
        } else {
            Card("Can I retire yet?") {
                Group {
                    if let plan = library.mainPlan {
                        waiting(for: plan)
                    } else {
                        noPlan
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The answer, leading the screen.
    private func hero(_ headline: PlanHeadline, plan: PlanDocument) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack {
                Text("Can I retire yet?")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: Metrics.s)
                Button {
                    navigation.showPlan()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.mutedInk)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open the plan")
            }
            answer(headline, plan: plan, gap: baselineGap(for: plan))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            navigation.showPlan()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open the plan") {
            navigation.showPlan()
        }
    }

    /// Without a main plan: create the first plan, as the Plan screen does,
    /// or open the plans to choose one; when the main plan's file couldn't
    /// be read, its details instead. Why *Create a plan* failed shows under
    /// it until the plans change.
    private var noPlan: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            Text(noPlanText)
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if mainPlanIsUnreadable {
                Button("Show Details") { navigation.show(.sync) }
                    .buttonStyle(.borderedProminent)
            } else if library.sortedPlans.isEmpty {
                Button("Create a plan") { createPlan() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!library.canEdit)
            } else {
                Button("Open Plan") { navigation.showPlan() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .onChange(of: library.sortedPlans.isEmpty) { error = nil }
    }

    private var noPlanText: String {
        if mainPlanIsUnreadable { return "Your main plan's file couldn't be read, so it has no answer." }
        return library.sortedPlans.isEmpty ? "Make a plan to see when you could retire."
            : "Choose a main plan to see when you could retire."
    }

    /// Whether a main plan is chosen but its file couldn't be read.
    private var mainPlanIsUnreadable: Bool {
        guard let main = library.settings.mainPlan else { return false }
        return library.library.plans[main] == nil && library.unloadedFiles.contains(.plan(main))
    }

    @ViewBuilder
    private func answer(_ headline: PlanHeadline, plan: PlanDocument, gap: OverviewBaselineGap?) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(answerText(headline))
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.ink)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 2) {
                if let when = whenText(headline) {
                    Text(when)
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                }
                Text(confidenceText(headline))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
            // Plan assets against what retiring today needs, from the simulation. An answer
            // recorded before that existed has only the old FI progress, which disagreed with
            // the chance of retiring today, so it gets a neutral line instead.
            PlanReadinessView(headline: headline,
                              fallback: headline.recordedOn != nil ? PlanResultsText.readinessNotRecorded : nil)
            if let gap {
                // Ahead, on or behind plan by where you are among the baseline's
                // futures; only behind is a warning. Then the amount against its median.
                HStack(spacing: Metrics.xs) {
                    Text(verbatim: "\(gap.standing.label) ·")
                        .fontWeight(.semibold)
                        .foregroundStyle(gap.standing.color)
                    AmountText(abs(gap.gap), currency: library.baseCurrency)
                        .foregroundStyle(Palette.ink)
                    Text(gapText(gap))
                        .foregroundStyle(Palette.secondaryInk)
                }
                .font(.subheadline)
            }
            runStatus(headline, plan: plan)
            Text(AboutText.disclaimer)
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
        }
    }

    /// Under the answer: when it was recorded at a check-in, a calculation
    /// going on, or that the results are out of date; with *Calculate*
    /// (``PlanStore/run(_:mode:whatIf:focusAge:)``, as *Future* starts it)
    /// when the answer isn't current, or why it can't be calculated, with
    /// *Try Again* and *Open Plan*.
    @ViewBuilder
    private func runStatus(_ headline: PlanHeadline, plan: PlanDocument) -> some View {
        let progress = plans.progress(of: plan.id, .checkIn) ?? plans.progress(of: plan.id, .base)
        let isStale = headline.recordedOn == nil && !plans.staleReasons(of: plan.id).isEmpty
        if let recorded = headline.recordedOn {
            Text("As recorded at the check-in on \(AmountFormat.shortDate(recorded, locale: locale))")
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
        }
        if let progress {
            Text(PlanRunText.status(progress, isCheckIn: plans.isRunning(plan.id, .checkIn), locale: locale))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.mutedInk)
        } else if let error = plans.errors[plan.id], headline.recordedOn != nil || isStale {
            cantCalculate(plan, error: error)
        } else if headline.recordedOn != nil || isStale {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                if isStale {
                    Text("Calculated before your latest changes")
                        .font(.caption)
                        .foregroundStyle(Palette.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Calculate") { Task { await plans.run(plan.id) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(plans.isRunning(plan.id, .base) || plans.isRunning(plan.id, .checkIn))
            }
        }
    }

    /// "Base case can't be calculated: …", with *Try Again* and *Open Plan*.
    private func cantCalculate(_ plan: PlanDocument, error: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Label("\(plan.name) can't be calculated: \(error)", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Metrics.s) {
                Button("Try Again") { Task { await plans.run(plan.id) } }
                Button("Open Plan") { navigation.showPlan(plan.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    /// The main plan without an answer: its calculation going on, why it
    /// can't run (with *Try Again* and *Open Plan*), or *Calculate*.
    @ViewBuilder
    private func waiting(for plan: PlanDocument) -> some View {
        if plans.isRunning(plan.id) {
            HStack(spacing: Metrics.s) {
                ProgressView()
                if let progress = plans.progress(of: plan.id, .checkIn) ?? plans.progress(of: plan.id, .base) {
                    Text("Working out \(plan.name)… \(PlanRunText.overall(progress, locale: locale))")
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                } else {
                    Text("Working out \(plan.name)…")
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        } else if let error = plans.errors[plan.id] {
            cantCalculate(plan, error: error)
        } else {
            VStack(alignment: .leading, spacing: Metrics.m) {
                Text("Calculate \(plan.name) to see when you could retire. Each check-in then records its answer.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Calculate") { Task { await plans.run(plan.id) } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Creates the first plan, "Base case", from the latest check-in, makes
    /// it the main plan and opens it, as the Plan screen's *Create your
    /// first plan* does.
    private func createPlan() {
        let plan = PlanEditing.newPlan(id: library.newPlanID(for: "Base case"), name: "Base case",
                                       library: library.library, asOf: library.asOfDate)
        do {
            try library.save(plan)
            if library.needsMainPlan { try library.setMainPlan(plan.id) }
            error = nil
            navigation.showPlan(plan.id)
        } catch {
            self.error = LibraryStore.describe(error)
        }
    }

    /// Today against the baseline "Are you on track?" and the plan's pill
    /// measure the latest check-in against: its year's
    /// (``PlanProgressYear/latestBaseline(for:library:valuator:asOf:)``);
    /// `nil` without one.
    private func baselineGap(for plan: PlanDocument?) -> OverviewBaselineGap? {
        guard let plan,
              let latest = PlanProgressYear.latestBaseline(for: plan.id, library: library.library,
                                                           valuator: library.valuator, asOf: library.asOfDate)
        else { return nil }
        return OverviewBaselineGap(baseline: latest.entry.baseline, valuator: library.valuator, on: today)
    }

    /// "Yes", "Not yet · earliest at 54", or "Not yet" when no age works out.
    private func answerText(_ headline: PlanHeadline) -> String {
        if headline.canRetireNow { return "Yes" }
        guard let age = headline.earliestAge else { return "Not yet" }
        return "Not yet · earliest at \(age)"
    }

    /// "About 15 years to go · March 2042" (the widgets' ``RetirementCountdown``
    /// in words, ``RetirementCountdown/toGoText``: whole years from two years
    /// on, rounded to the nearest, else months), "You could retire today",
    /// "No retirement age works out yet". `nil` for an answer recorded at a
    /// check-in without a birth date, and for an earliest month that has
    /// passed.
    private func whenText(_ headline: PlanHeadline) -> String? {
        if headline.canRetireNow { return "You could retire today" }
        guard headline.earliestAge != nil else { return "No retirement age works out yet" }
        guard let date = headline.earliestDate ?? recordedEarliestDate(headline),
              let countdown = RetirementCountdown(from: today, to: date)
        else { return nil }
        return "\(countdown.toGoText.capitalizedFirst) · \(GlanceText.monthAndYear(date, locale: locale))"
    }

    /// When an answer recorded at a check-in reaches its earliest age, as the
    /// widgets have it (Glance's `RetirementAnswer.earliestDate`); `nil`
    /// without a birth date.
    private func recordedEarliestDate(_ headline: PlanHeadline) -> CalendarDate? {
        guard let recorded = headline.recordedOn, let age = headline.earliestAge,
              let birthDate = library.settings.person?.birthDate
        else { return nil }
        return RetirementAnswer.earliestDate(age: age, recordedOn: recorded, birthDate: birthDate)
    }

    private func confidenceText(_ headline: PlanHeadline) -> String {
        headline.canRetireNow
            ? "It works in at least \(GlanceText.futures(headline.confidence)) simulated futures"
            : "The first age that works \(GlanceText.inSimulatedFutures(headline.confidence))"
    }

    /// "ahead of your Jan baseline", after the amount against its median,
    /// named as Progress names what a year is measured against: by the
    /// month it starts in the year it was saved for,
    /// January when it starts before it, with that year when it isn't this one
    /// ("Jan 2025"); a past baseline by the year it starts ("ahead of your
    /// 2021 plan").
    private func gapText(_ gap: OverviewBaselineGap) -> String {
        let name: String
        if gap.isPast {
            name = "\(gap.start.year) plan"
        } else {
            let start = max(gap.start, CalendarDate.firstDay(ofYear: gap.created.year))
            name = "\(GlanceText.shortMonth(start, relativeTo: today, locale: locale)) baseline"
        }
        return gap.gap >= 0 ? "ahead of your \(name)" : "behind your \(name)"
    }
}

// MARK: - Needs attention

/// Only shown when something needs you: stale accounts, accounts with
/// problems in their trades (opening the account), prices that are missing
/// or couldn't be fetched, past prices and exchange rates the history is
/// missing (opening *Fill In Past Prices*), the library's own state (merged
/// sync conflicts, save errors, unreadable files) and plan warnings.
struct OverviewAttentionCard: View {
    /// The day the Overview reports on.
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(CheckInStore.self) private var checkIn
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @State private var fillsPastPrices = false

    var body: some View {
        let items = self.items
        let showsBanners = LibraryStatusBanners.showsAny(for: library)
        if !items.isEmpty || showsBanners {
            Card("Needs attention") {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    if showsBanners {
                        LibraryStatusBanners()
                    }
                    ForEach(items) { item in
                        row(for: item)
                    }
                }
            }
            .pastPricesSheet(isPresented: $fillsPastPrices)
        }
    }

    private var items: [OverviewAttentionItem] {
        var items = OverviewAttention.items(
            library: library.library, valuator: library.valuator, on: today,
            stalenessThreshold: preferences.stalenessThreshold, locale: locale)
        if checkIn.hasDraft, let failures = checkIn.priceList?.failures, !failures.isEmpty {
            items.append(OverviewAttentionItem(
                id: "checkin.prices", systemImage: "tag.slash",
                title: failures.count == 1 ? "A price couldn't be fetched" : "\(failures.count) prices couldn't be fetched",
                detail: "Type them in on the check-in's price list.", target: .checkIn))
        }
        if let main = library.settings.mainPlan, let error = plans.errors[main] {
            items.append(OverviewAttentionItem(
                id: "plan.error", systemImage: "exclamationmark.triangle",
                title: "\(library.mainPlan?.name ?? "Your plan") couldn't run", detail: error, target: .plan))
        }
        if let main = library.settings.mainPlan, let bridge = plans.results[main]?.details.focus.bridges.first,
           bridge.share >= 0.05 {
            let futures = Int(wholeNumber: bridge.share * 100)
            let age = bridge.accessibleFromAge.map { " at \($0)" } ?? ""
            items.append(OverviewAttentionItem(
                id: "plan.bridge", systemImage: "lock",
                title: "Money could run short before locked money opens",
                detail: "In \(futures) of 100 simulated futures, it runs out before your pension money becomes "
                    + "available\(age).",
                target: .plan))
        }
        return items
    }

    @ViewBuilder
    private func row(for item: OverviewAttentionItem) -> some View {
        switch item.target {
        case .account(let id):
            NavigationLink(value: id) {
                OverviewAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        case .instrument(let id):
            NavigationLink {
                InstrumentEditor(instrumentID: id)
            } label: {
                OverviewAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        case .checkIn:
            Button {
                navigation.startCheckIn()
            } label: {
                OverviewAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        case .plan:
            Button {
                navigation.showPlan()
            } label: {
                OverviewAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        case .fillPastPrices:
            Button {
                fillsPastPrices = true
            } label: {
                OverviewAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        }
    }
}

/// One item: a warning icon, what it is, what to do, and a chevron.
private struct OverviewAttentionRow: View {
    let item: OverviewAttentionItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
            Image(systemName: item.systemImage)
                .foregroundStyle(Palette.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(item.detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Metrics.s)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.mutedInk)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Metrics.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Allocation

/// Horizontal bars with values and shares, grouped by the chosen dimension.
struct OverviewAllocationCard: View {
    let breakdown: Breakdown
    @Binding var dimension: BreakdownDimension

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.s) {
                BreakdownBars(rows: breakdown.rows, limit: dimension.limit)
                if dimension == .assetClass && breakdown.slices.contains(where: { $0.key == .debts }) {
                    Text("Shares are of what you own; debts are their own bar.")
                        .font(.footnote)
                        .foregroundStyle(Palette.mutedInk)
                }
            }
        } header: {
            SectionHeader("Allocation") {
                Picker("Group by", selection: $dimension) {
                    ForEach(BreakdownDimension.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
        }
    }
}

#Preview("Cards") {
    let valuator = PreviewLibrary.valuator
    let date = PreviewLibrary.latestCheckIn
    NavigationStack {
        ScrollView {
            VStack(spacing: Metrics.l) {
                if let report = valuator.changeSinceLastCheckIn(asOf: date) {
                    OverviewChangeCard(report: report)
                }
                if let report = valuator.changeThisYear(asOf: date) {
                    OverviewYearCard(report: report)
                }
                // Before the main plan's first calculation.
                OverviewAnswerView(headline: nil, today: date)
                OverviewAttentionCard(today: date)
                OverviewAllocationCard(breakdown: valuator.breakdown(by: .assetClass, on: date),
                                       dimension: .constant(.assetClass))
            }
            .padding()
        }
        .background(Palette.page)
    }
    .previewEnvironment()
}
