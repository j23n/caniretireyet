import Glance
import Model
import Prices
import Storage
import SwiftUI
import Tracker

// Today's cards (UI.md, "Today"): what moved at the last check-in, as a
// tile, the plan before there is an answer, and what needs attention. The
// answer itself is `TodayAnswerCard`; the other tiles are in
// TodayTiles.swift.

// MARK: - What moved

/// What moved the date at the last check-in, as a wide tile (UI.md, "What
/// moved it"): "What moved it in September", a bar each for what you saved
/// and what markets did, to one scale, and one sentence saying what was
/// saved as time of the plan's spending.
struct TodayMovedTile: View {
    let report: ChangeReport
    /// Its split with saved as the savings rate counts it (Tracker's
    /// `Valuator.savedSplit(of:)`).
    let split: ValueChange
    /// The main plan's retirement spending a year, to say what was saved as
    /// time; `nil` without a main plan.
    var yearlySpending: Decimal?
    @Environment(\.locale) private var locale

    var body: some View {
        let largest = max(abs(split.saved), abs(split.market))
        ColorTile {
            TileLabel(TodayText.movedTitle(from: report.from, to: report.to, today: .today(), saysIt: true,
                                           locale: locale),
                      emoji: "🌤️")
                .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.s)
            Grid(alignment: .leading, horizontalSpacing: Metrics.m, verticalSpacing: Metrics.s) {
                bar("💰 You saved", split.saved, largest: largest, color: Palette.accent)
                bar("📈 Markets", split.market, largest: largest, color: Palette.accent.opacity(0.45))
            }
            if let sentence = TodayText.savedAsTime(saved: split.saved, markets: split.market,
                                                    yearlySpending: yearlySpending) {
                Text(sentence)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
                    .padding(.top, Metrics.s)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A row: its name, its bar against the larger of the two, its amount.
    private func bar(_ label: String, _ value: Decimal, largest: Decimal, color: Color) -> GridRow<some View> {
        // No modifiers on the row itself: they'd turn it into one cell.
        GridRow {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .fixedSize()
            TodayShareBar(share: largest > 0 ? (abs(value) / largest).doubleValue : 0, color: color)
                .frame(maxWidth: .infinity)
            AmountText(value)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .fixedSize()
                .gridColumnAlignment(.trailing)
        }
    }
}

/// A thin bar from the leading edge, `share` of the width: 0 to 1. While
/// amounts are hidden it keeps its length; in a feedback screenshot it hides.
struct TodayShareBar: View {
    let share: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(color)
                .frame(width: share > 0 ? max(proxy.size.width * min(share, 1), 8) : 0)
        }
        .frame(height: 8)
        .privacySensitiveInFeedback()
        .accessibilityHidden(true)
    }
}

// MARK: - Can I retire yet?

/// Before the main plan has an answer (UI.md, "Today"): a card with the
/// next step, *Create a plan* or *Calculate* the main plan. With an answer,
/// ``TodayAnswerCard`` says it instead.
struct TodayPlanCard: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @State private var error: String?

    var body: some View {
        Card("Your last Monday at work") {
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

    /// "Base case can't be calculated: …", with *Try Again* and *Open Plan*.
    private func cantCalculate(_ plan: PlanDocument, error: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Label("\(plan.name) can't be calculated: \(error)", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
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
                        .privacySensitiveInFeedback()
                } else {
                    Text("Working out \(plan.name)…")
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
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
                    .privacySensitiveInFeedback()
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

}

// MARK: - Needs attention

/// Only shown when something needs you: stale accounts, accounts with
/// problems in their trades (opening the account), prices that are missing
/// or couldn't be fetched, past prices and exchange rates the history is
/// missing (opening *Fill In Past Prices*), the library's own state (merged
/// sync conflicts, save errors, unreadable files) and plan warnings.
///
/// A compact row each, with its action: on iPhone an icon, what and why,
/// and the action at the trailing edge, in a card without a title; on the
/// Mac and iPad titled "Needs attention", with an orange edge, the action
/// under each. The first three show; *N More* shows the rest.
struct TodayAttentionCard: View {
    /// The day Today reports on.
    let today: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(CheckInStore.self) private var checkIn
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @State private var fillsPastPrices = false
    @State private var showsAll = false

    /// How many items show before *N More*.
    private static let shownAtFirst = 3

    var body: some View {
        let items = self.items
        let showsBanners = LibraryStatusBanners.showsAny(for: library)
        if !items.isEmpty || showsBanners {
            let shown = showsAll ? items : Array(items.prefix(Self.shownAtFirst))
            VStack(alignment: .leading, spacing: 0) {
                if layout.isWide {
                    SectionHeader("Needs attention")
                        .padding(.top, Metrics.l)
                        .padding(.bottom, Metrics.xs)
                }
                if showsBanners {
                    LibraryStatusBanners()
                        .padding(.vertical, Metrics.m)
                }
                ForEach(shown) { item in
                    if item.id != shown.first?.id {
                        Divider()
                    }
                    row(for: item)
                }
                if items.count > Self.shownAtFirst {
                    let toggle = showsAll ? "Show Fewer" : "\(items.count - shown.count) More"
                    Divider()
                    Button(toggle) {
                        showsAll.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(Palette.accent)
                    .padding(.vertical, Metrics.m)
                }
            }
            .padding(.horizontal, Metrics.l)
            .padding(.bottom, layout.isWide ? Metrics.xs : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .overlay {
                if layout.isWide {
                    Rectangle()
                        .fill(Palette.warning)
                        .frame(width: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Needs attention")
            .pastPricesSheet(isPresented: $fillsPastPrices)
        }
    }

    private var items: [TodayAttentionItem] {
        var items = TodayAttention.items(
            library: library.library, valuator: library.valuator, on: today,
            stalenessThreshold: preferences.stalenessThreshold, locale: locale)
        if checkIn.hasDraft, let failures = checkIn.priceList?.failures, !failures.isEmpty {
            items.append(TodayAttentionItem(
                id: "checkin.prices", systemImage: "tag.slash",
                title: failures.count == 1 ? "A price couldn't be fetched" : "\(failures.count) prices couldn't be fetched",
                detail: "Type them in under Instruments", target: .instruments))
        }
        if let main = library.settings.mainPlan, let error = plans.errors[main] {
            items.append(TodayAttentionItem(
                id: "plan.error", systemImage: "exclamationmark.triangle",
                title: "\(library.mainPlan?.name ?? "Your plan") couldn't run", detail: error, target: .plan))
        }
        if let main = library.settings.mainPlan, let bridge = plans.results(of: main)?.details.focus.bridges.first,
           bridge.share >= 0.05 {
            let futures = Int(wholeNumber: bridge.share * 100)
            let age = bridge.accessibleFromAge.map { " at \($0)" } ?? ""
            items.append(TodayAttentionItem(
                id: "plan.bridge", systemImage: "lock",
                title: "Money could run short",
                detail: "In \(futures) of 100 futures, before your pension money opens\(age)",
                target: .plan))
        }
        return items
    }

    @ViewBuilder
    private func row(for item: TodayAttentionItem) -> some View {
        switch item.target {
        case .account(let id):
            NavigationLink(value: id) {
                TodayAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        case .instrument(let id):
            NavigationLink {
                InstrumentEditor(instrumentID: id)
            } label: {
                TodayAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        case .instruments:
            NavigationLink {
                InstrumentsScreen()
            } label: {
                TodayAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        case .plan:
            Button {
                navigation.showPlan()
            } label: {
                TodayAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        case .fillPastPrices:
            Button {
                fillsPastPrices = true
            } label: {
                TodayAttentionRow(item: item)
            }
            .buttonStyle(.plain)
        }
    }
}

/// One item: what and why, and its action. On iPhone a warning icon at the
/// leading edge and the action at the trailing one; on the Mac and iPad the
/// action under the words, why in orange.
private struct TodayAttentionRow: View {
    let item: TodayAttentionItem
    @Environment(\.pageLayout) private var layout

    var body: some View {
        Group {
            if layout.isWide {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    words(detail: Palette.warning)
                    action
                }
            } else {
                HStack(spacing: Metrics.m) {
                    Image(systemName: item.systemImage)
                        .font(.title3)
                        .foregroundStyle(Palette.warning)
                        .accessibilityHidden(true)
                    words(detail: Palette.secondaryInk)
                    Spacer(minLength: Metrics.s)
                    action
                }
            }
        }
        .padding(.vertical, layout.isWide ? Metrics.s : Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func words(detail: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .privacySensitiveInFeedback()
            Text(item.detail)
                .font(.footnote)
                .foregroundStyle(detail)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
        }
    }

    /// The action, drawn as a small button: the whole row is the button.
    private var action: some View {
        Text(item.action)
            .font(layout.isWide ? .caption : .subheadline)
            .foregroundStyle(layout.isWide ? Palette.ink : Palette.accent)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, layout.isWide ? Metrics.s : Metrics.m)
            .padding(.vertical, layout.isWide ? 3 : 6)
            .background(Palette.page, in: Capsule())
    }
}

#Preview("Cards") {
    let valuator = PreviewLibrary.valuator
    let date = PreviewLibrary.latestCheckIn
    NavigationStack {
        ScrollView {
            VStack(spacing: Metrics.m) {
                if let report = valuator.changeSinceLastCheckIn(asOf: date) {
                    TileGrid {
                        TodayMovedTile(report: report, split: valuator.savedSplit(of: report))
                            .tileSize(.wide)
                    }
                }
                if let report = valuator.changeThisYear(asOf: date) {
                    TileGrid {
                        TodayYearTile(report: report, split: valuator.savedSplit(of: report))
                            .tileSize(.small)
                        CheckInTile(status: CheckInStatus(lastCheckIn: date, nextCheckIn: date.adding(months: 1),
                                                          daysUntilDue: 6, isDue: false))
                            .tileSize(.half)
                        CoastAgeTile(age: 71, target: 67, size: .half)
                            .tileSize(.half)
                    }
                }
                // Before the main plan's first calculation.
                TodayPlanCard()
                TodayAttentionCard(today: date)
            }
            .padding()
        }
        .background(Palette.page)
    }
    .previewEnvironment()
}
