import Glance
import Model
import Prices
import Storage
import SwiftUI
import Tracker

// Today's cards (UI.md, "Today"): what moved at the last check-in, as two
// tiles, the plan before there is an answer, and what needs attention. The
// answer itself is `TodayAnswerCard`; the other tiles are in
// TodayTiles.swift.

// MARK: - What moved

/// Your pay at the last check-in, as a wide tile (UI.md, "What moved it"):
/// "💶 Your pay in September", a line each for what came in, what went
/// into a pension and the tax when there's some, and what was spent, then
/// what that left saved; beside them a ring of what came in, split into
/// saved, spent and tax, with what was saved of the pay after tax in its
/// middle. Only when money in and out was recorded.
struct TodayPayTile: View {
    let moved: WhatMoved
    let pay: WhatMoved.Pay

    @Environment(\.locale) private var locale

    var body: some View {
        ColorTile {
            TileLabel(TodayText.payTitle(from: moved.from, to: moved.to, today: .today(), locale: locale),
                      emoji: "💶")
                .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.s)
            HStack(alignment: .center, spacing: Metrics.l) {
                TodayMovedLedger(lines: TodayMoved.payLines(pay), signed: false)
                TodayPayRing(pay: pay)
                    .frame(width: 88, height: 88)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// How net worth moved at the last check-in, as a wide tile (UI.md, "What
/// moved it"): "🌤️ Your net worth in September", a line each for what was
/// saved, markets and the rest, then net worth's change, which they add up
/// to; beside them the same as steps.
struct TodayMovedTile: View {
    let moved: WhatMoved

    @Environment(\.locale) private var locale

    var body: some View {
        let lines = TodayMoved.netWorthLines(moved)
        ColorTile {
            TileLabel(TodayText.netWorthMovedTitle(from: moved.from, to: moved.to, today: .today(), locale: locale),
                      emoji: "🌤️")
                .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.s)
            HStack(alignment: .center, spacing: Metrics.l) {
                TodayMovedLedger(lines: lines, signed: true)
                TodayMovedSteps(lines: lines)
                    .frame(width: 88, height: 80)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A *What moved* tile's lines: a dot in the line's color, its name and its
/// amount; a rule over a line that adds up the ones above it. With
/// `signed`, every amount has its sign.
struct TodayMovedLedger: View {
    let lines: [TodayMovedLine]
    let signed: Bool

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Metrics.s, verticalSpacing: 3) {
            ForEach(lines) { line in
                if line.isSum {
                    Rectangle()
                        .fill(Palette.ink.opacity(line.kind == .total ? 0.9 : 0.3))
                        .frame(height: line.kind == .total ? 1.5 : 1)
                        .gridCellUnsizedAxes(.horizontal)
                }
                // No modifiers on the row itself: they'd turn it into one cell.
                GridRow {
                    Circle()
                        .fill(line.kind.color)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(line.title)
                        .font(font(line))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    AmountText(line.amount, signed: signed)
                        .font(font(line))
                        .lineLimit(1)
                        .fixedSize()
                        .gridColumnAlignment(.trailing)
                }
            }
        }
    }

    private func font(_ line: TodayMovedLine) -> Font {
        .footnote.weight(line.isSum ? .semibold : .regular)
    }
}

/// The pay tile's ring: what came in, split into saved, spent and tax
/// (``TodayMoved/ring(_:)``), and what was saved of the pay after tax in
/// its middle, "39%". While amounts are hidden it keeps its proportions;
/// in a feedback screenshot it hides.
struct TodayPayRing: View {
    let pay: WhatMoved.Pay

    @Environment(\.locale) private var locale

    private let lineWidth: CGFloat = 13

    var body: some View {
        let slices = TodayMoved.ring(pay)
        ZStack {
            Circle()
                .stroke(Palette.gridline, lineWidth: lineWidth)
            ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                let start = slices[..<index].reduce(0) { $0 + $1.share }
                Circle()
                    .trim(from: start, to: start + slice.share)
                    .stroke(slice.kind.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            if let share = pay.savedShare {
                VStack(spacing: 0) {
                    Text(verbatim: AmountFormat.percent(share, digits: 0, locale: locale))
                        .font(.headline.bold())
                    Text("saved")
                        .font(.caption2)
                        .opacity(0.8)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(lineWidth)
            }
        }
        .padding(lineWidth / 2)
        .privacySensitiveInFeedback()
    }
}

/// The net worth tile's steps: a bar for each line, from where the one
/// before it ended (``TodayMoved/steps(_:)``), and the change from zero,
/// to one scale with a line at zero. While amounts are hidden it keeps its
/// proportions; in a feedback screenshot it hides.
struct TodayMovedSteps: View {
    let lines: [TodayMovedLine]

    var body: some View {
        let steps = TodayMoved.steps(lines)
        let low = min(steps.map(\.lowerBound).min() ?? 0, 0)
        let high = max(steps.map(\.upperBound).max() ?? 0, 0)
        let colors = lines.map(\.kind.color)
        Canvas { context, size in
            let span = (high - low).doubleValue
            guard span > 0, !steps.isEmpty else { return }
            let gap: CGFloat = 4
            let width = (size.width - gap * CGFloat(steps.count - 1)) / CGFloat(steps.count)
            func y(_ value: Decimal) -> CGFloat {
                size.height * CGFloat(1 - (value - low).doubleValue / span)
            }
            for (index, step) in steps.enumerated() {
                let top = y(step.upperBound)
                let height = max(y(step.lowerBound) - top, 2)
                let bar = CGRect(x: CGFloat(index) * (width + gap), y: top, width: width, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: 3), with: .color(colors[index]))
            }
            var zero = Path()
            zero.move(to: CGPoint(x: 0, y: y(0)))
            zero.addLine(to: CGPoint(x: size.width, y: y(0)))
            context.stroke(zero, with: .color(Palette.axis), lineWidth: 1)
        }
        .privacySensitiveInFeedback()
        .accessibilityHidden(true)
    }
}

extension TodayMovedLine.Kind {
    /// The line's dot, its slice of the ring and its bar.
    var color: Color {
        switch self {
        case .cameIn: Palette.green
        case .pension: Palette.green.opacity(0.5)
        case .tax: Palette.orange
        case .spent: Palette.orange.opacity(0.5)
        case .saved: Palette.accent
        case .markets: Palette.aqua
        case .oneOff: Palette.yellow
        case .startedWith: Palette.violet
        case .lost: Palette.magenta
        case .other: Palette.mutedInk
        case .total: Palette.ink
        }
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
                    let moved = valuator.whatMoved(report)
                    TileGrid {
                        if let pay = moved.pay {
                            TodayPayTile(moved: moved, pay: pay)
                                .tileSize(.wide)
                        }
                        TodayMovedTile(moved: moved)
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
