import Model
import Planner
import SwiftUI
import Tracker

// The chosen year in words (UI.md, "Progress"), said once, under the strip:
// its figures, why it's ahead or behind, and what happened. Everything but
// what happened keeps its size from year to year, so stepping through the
// years moves nothing above it; on the Mac and iPad they're columns when
// there's room.

/// The chosen year under the strip (UI.md, "Progress"): its title, change
/// and where it stands against January, the year in a line, then its
/// figures, why it's ahead or behind, and what happened. On iPhone one
/// after the other with *‹ ›* in the title; on the Mac and iPad in
/// columns, three when there's room, or one after the other in a narrow
/// window, the arrows being above the strip.
struct PlanYearDetails: View {
    let card: PlanProgressTimeline.Card
    let index: Int
    let count: Int
    /// The Mac and iPad: columns, and no arrows of its own.
    var isWide = false
    var onSelect: (Int) -> Void = { _ in }
    /// *Add What You Planned in 2021…*, for a year without a baseline: opens
    /// *Add Past Baseline…* at its start.
    var onAddPastBaseline: ((Int) -> Void)?

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale
    @State private var width: CGFloat = 0
    @State private var fillsPastPrices = false

    private var year: PlanProgressYear { card.year }

    /// Below this width the parts are one after the other, as on iPhone.
    private static let twoColumnWidth: CGFloat = 640
    /// Below this width the figures and why share the first of two columns.
    private static let threeColumnWidth: CGFloat = 860

    /// One part after the other: on iPhone, and on the Mac and iPad when
    /// the page is too narrow for columns.
    private var stacks: Bool { !isWide || (width > 0 && width < Self.twoColumnWidth) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.l) {
                header
                if stacks {
                    summary
                    PlanYearFigures(card: card, showsBar: isWide)
                    PlanYearWhy(card: card, onAddPastBaseline: onAddPastBaseline)
                    PlanYearHappenings(card: card)
                } else {
                    columns
                }
                notes
            }
        }
        .measuringWidth($width)
        .pastPricesSheet(isPresented: $fillsPastPrices)
    }

    /// The year, its change and where it stands; the year in a line beside
    /// them in columns, *‹ ›* on iPhone.
    private var header: some View {
        HStack(alignment: .center, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    Text(year.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    if !year.isLatest {
                        Text(PlanProgressText.change(year, currency: card.currency, hidesAmounts: hidesAmounts,
                                                     locale: locale))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                    }
                }
                standing
            }
            Spacer(minLength: Metrics.s)
            if !stacks {
                summary
                    .multilineTextAlignment(.trailing)
            } else if !isWide && count > 1 {
                PlanStepButtons(index: index, count: count, select: onSelect)
            }
        }
    }

    /// "21.572 € ahead of January", in orange when behind plan
    /// (``PlanBaselineComparison/Standing``), else green; else why it isn't
    /// measured.
    @ViewBuilder
    private var standing: some View {
        if let against = PlanProgressText.againstJanuary(year, currency: card.currency, hidesAmounts: hidesAmounts,
                                                         locale: locale) {
            Text(against)
                .font(PlanProgressFont.caption.weight(.semibold))
                .foregroundStyle(PlanBaselineComparison.Standing.color(of: year.position))
        } else {
            Text(PlanProgressText.unmeasured(year))
                .font(PlanProgressFont.caption)
                .foregroundStyle(Palette.mutedInk)
        }
    }

    /// The year in a line, one line always: "A year sooner, and past
    /// 150.000 €.", or for a quiet year "A quiet year."
    private var summary: some View {
        Text(card.summary ?? (year.isLatest ? "A quiet year so far." : "A quiet year."))
            .font(stacks ? PlanProgressFont.summary : PlanProgressFont.text)
            .foregroundStyle(stacks ? Palette.ink : Palette.secondaryInk)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// Three columns, or two when narrow: the figures over why in the first.
    @ViewBuilder
    private var columns: some View {
        if width == 0 || width >= Self.threeColumnWidth {
            EqualColumns(spacing: Metrics.xl) {
                PlanYearFigures(card: card, showsBar: true)
                PlanYearWhy(card: card, onAddPastBaseline: onAddPastBaseline)
                PlanYearHappenings(card: card)
            }
        } else {
            EqualColumns(spacing: Metrics.xl) {
                VStack(alignment: .leading, spacing: Metrics.l) {
                    PlanYearFigures(card: card, showsBar: true)
                    PlanYearWhy(card: card, onAddPastBaseline: onAddPastBaseline)
                }
                PlanYearHappenings(card: card)
            }
        }
    }

    /// Check-ins that stop early, and missing prices or rates.
    @ViewBuilder
    private var notes: some View {
        if let note = PlanProgressText.pricesNote(year, locale: locale) {
            Text(note)
                .font(PlanProgressFont.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !year.isComplete || card.actual.contains(where: { !$0.isComplete }) {
            OldPriceNoteView(text: "Some prices or exchange rates were missing: those holdings count as zero, "
                                 + "and the line is dotted there.",
                             systemImage: "exclamationmark.triangle") { fillsPastPrices = true }
        }
    }
}

/// A year's figures in a line under its graph on the Mac and iPad: what you
/// saved, what markets did and the earliest age at its end.
struct PlanYearCardFooter: View {
    let card: PlanProgressTimeline.Card

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    private func item(_ title: String, _ value: String) -> Text {
        let name = Text(title).foregroundStyle(Palette.secondaryInk)
        let figure = Text(value).fontWeight(.semibold).foregroundStyle(Palette.ink)
        return Text("\(name) \(figure)")
    }

    var body: some View {
        let year = card.year
        let saved = hidesAmounts ? AmountFormat.hidden
            : AmountFormat.amount(year.change.newMoney, currency: card.currency, locale: locale)
        let markets = hidesAmounts ? AmountFormat.hidden
            : AmountFormat.signedAmount(year.change.market, currency: card.currency, locale: locale)
        HStack(spacing: Metrics.s) {
            item("Saved", saved)
            Spacer(minLength: Metrics.xs)
            item("Markets", markets)
            Spacer(minLength: Metrics.xs)
            item("Age", year.answerTo?.earliestAge.map { "\($0)" } ?? "–")
        }
        .font(.caption)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }
}

/// The year's figures, two by two: what you saved and what markets did,
/// against what its baseline planned and expected; how the earliest age
/// moved; and how many of the baseline's futures are below you. On the Mac
/// and iPad, above them, saving and markets as one bar with a mark at what
/// was planned.
struct PlanYearFigures: View {
    let card: PlanProgressTimeline.Card
    var showsBar = false

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    private var year: PlanProgressYear { card.year }

    private func amount(_ value: Decimal) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(abs(value), currency: card.currency, locale: locale)
    }

    var body: some View {
        let explanation = year.explanation?.inWholeUnits
        let byNow = year.isLatest ? " by now" : ""
        let saved = year.change.newMoney
        let market = year.change.market
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: Metrics.m) {
            if showsBar {
                PlanYearSavingBar(card: card)
            }
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                GridRow {
                    figure(saved >= 0 ? "You saved" : "You took out", amount(saved),
                           detail: explanation.map { "planned \(amount($0.plannedSaving))\(byNow)" },
                           titleColor: Palette.ink.opacity(0.8))
                    figure(market >= 0 ? "Markets added" : "Markets took", amount(market),
                           detail: explanation.map { "expected \(amount($0.expectedMarket))" },
                           titleColor: market >= 0 ? Palette.accent : Palette.orangeStroke)
                }
                GridRow {
                    figure("Earliest age", age, detail: ageMove,
                           detailColor: (year.ageChange ?? 0) < 0 ? Palette.accent : Palette.secondaryInk)
                    figure("Its futures", futures,
                           detail: year.position == nil ? PlanProgressText.unmeasured(year)
                               : year.isLatest ? "are below you now" : "ended below you")
                }
            }
            .background(Palette.border)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
        }
    }

    /// "56 → 55", "55", "–".
    private var age: String {
        switch (year.answerFrom?.earliestAge, year.answerTo?.earliestAge) {
        case let (from?, to?) where from != to: "\(from) → \(to)"
        case let (_, to?): "\(to)"
        default: "–"
        }
    }

    /// "a year sooner", "2 years later", "no change".
    private var ageMove: String? {
        guard let change = year.ageChange else { return nil }
        guard change != 0 else { return "no change" }
        return PlanProgressText.move(years: change)
    }

    /// How many of the baseline's 100 futures are below your money: "92 in 100".
    private var futures: String {
        guard let position = year.position else { return "–" }
        if let percentile = position.percentile { return "\(Int(wholeNumber: percentile)) in 100" }
        if position.isAboveNinetieth { return "Over 9 in 10" }
        if position.isBelowTenth { return "Under 1 in 10" }
        return "–"
    }

    /// A figure: its title, the figure, and a line under it, always there so
    /// every figure is as tall as the others.
    private func figure(_ title: String, _ value: String, detail: String?, titleColor: Color = Palette.secondaryInk,
                        detailColor: Color = Palette.secondaryInk) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(PlanProgressFont.caption.weight(.semibold))
                .foregroundStyle(titleColor)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
            Text(detail ?? " ")
                .font(PlanProgressFont.caption)
                .foregroundStyle(detailColor)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card)
        .accessibilityElement(children: .combine)
    }
}

/// What you saved and what markets added as one bar, with a mark where the
/// baseline planned your saving to reach.
struct PlanYearSavingBar: View {
    let card: PlanProgressTimeline.Card

    private var year: PlanProgressYear { card.year }

    /// What the year's baseline planned you'd save over the same stretch as
    /// the bar; `nil` without one, or when it started later in the year.
    private var plannedSaving: Decimal? {
        guard let explanation = year.explanation, let baseline = year.baseline?.baseline,
              baseline.start.date <= year.from, explanation.plannedSaving > 0 else { return nil }
        return explanation.plannedSaving
    }

    var body: some View {
        let saved = max(0, year.change.newMoney.doubleValue)
        let markets = max(0, year.change.market.doubleValue)
        let planned = plannedSaving?.doubleValue
        let full = max(saved + markets, planned ?? 0, 1)
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Palette.gridline.opacity(0.6))
                    .frame(height: 10)
                HStack(spacing: 2) {
                    Rectangle()
                        .fill(Palette.secondaryInk.opacity(0.45))
                        .frame(width: max(0, width - 2) * CGFloat(saved / full))
                    Rectangle()
                        .fill(Palette.accent)
                        .frame(width: max(0, width - 2) * CGFloat(markets / full))
                }
                .frame(height: 10)
                .clipShape(Capsule())
                if let planned {
                    let at = width * CGFloat(planned / full)
                    Capsule()
                        .fill(Palette.ink.opacity(0.8))
                        .frame(width: 2, height: 16)
                        .offset(x: min(max(0, at - 1), width - 2), y: -3)
                    Text(year.isLatest ? "planned by now" : "planned")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize()
                        .position(x: min(max(at, 44), width - 44), y: 22)
                }
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}

/// Why the year is ahead of or behind its baseline (PROGRESS.md, *Why*;
/// UI.md, "Progress"), in the same four rows every year, so stepping
/// through the years moves nothing under it: the gap going into the year,
/// saving against the plan, markets against what was expected, and the
/// rest (inflation, values without new money, exchange rates). Each with a
/// bar and its amount, in whole units, adding up to the total; then what
/// the baseline expected.
struct PlanYearWhy: View {
    let card: PlanProgressTimeline.Card
    /// *Add What You Planned in 2021…*, for a year without a baseline.
    var onAddPastBaseline: ((Int) -> Void)?

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    private var year: PlanProgressYear { card.year }

    private struct Row: Identifiable {
        var title: String
        var value: Decimal
        var id: String { title }
    }

    private func amount(_ value: Decimal) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(abs(value), currency: card.currency, locale: locale)
    }

    private func signed(_ value: Decimal) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.signedAmount(value, currency: card.currency, locale: locale)
    }

    /// "Why you're ahead", "Why you ended behind"; "Against January" unmeasured.
    private var title: String {
        guard let explanation = year.explanation else { return "Against \(year.expectation(locale: locale))" }
        let side = explanation.end >= 0 ? "ahead" : "behind"
        return year.isLatest ? "Why you're \(side)" : "Why you ended \(side)"
    }

    private func rows(_ explanation: GapExplanation) -> [Row] {
        [Row(title: "Going in", value: explanation.start),
         Row(title: "Saving", value: explanation.saving),
         Row(title: "Markets", value: explanation.markets),
         Row(title: "Other", value: (explanation.inflation ?? 0) + explanation.other)]
    }

    /// "Ahead", "Behind".
    private func totalTitle(_ explanation: GapExplanation) -> String {
        explanation.end >= 0 ? "Ahead" : "Behind"
    }

    /// "January expected 141.463 € by 31 Dec.", "… by now."
    private var expected: String? {
        PlanProgressText.expected(year, amount: { amount($0) }, locale: locale).map { $0 + "." }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(title)
                .font(PlanProgressFont.text.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if let explanation = year.explanation?.inWholeUnits {
                let shown = rows(explanation)
                let largest = max(shown.map { abs($0.value) }.max() ?? 0, 1)
                Grid(alignment: .leading, horizontalSpacing: Metrics.s, verticalSpacing: Metrics.s) {
                    ForEach(shown) { row in
                        GridRow {
                            Text(row.title)
                                .foregroundStyle(Palette.ink)
                            PlanWhyBar(share: (abs(row.value) / largest).doubleValue, isPositive: row.value >= 0)
                            amountText(row.value)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Divider()
                        .gridCellColumns(3)
                    GridRow {
                        Text(totalTitle(explanation))
                            .fontWeight(.semibold)
                            .foregroundStyle(Palette.ink)
                        Color.clear
                            .frame(height: 1)
                        amountText(explanation.end, isTotal: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                .font(PlanProgressFont.text)
                if let expected {
                    Text(expected)
                        .font(PlanProgressFont.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            } else {
                Text(PlanProgressText.january(year, currency: card.currency, hidesAmounts: hidesAmounts, locale: locale)
                    ?? PlanProgressText.unmeasured(year))
                    .font(PlanProgressFont.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if year.baseline == nil, let onAddPastBaseline {
                    Button("Add What You Planned in \(String(year.year))…") { onAddPastBaseline(year.year) }
                        .buttonStyle(.borderless)
                        .font(PlanProgressFont.text.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    private func amountText(_ value: Decimal, isTotal: Bool = false) -> some View {
        Text(value == 0 ? amount(0) : signed(value))
            .fontWeight(isTotal ? .bold : .semibold)
            .monospacedDigit()
            .foregroundStyle(value == 0 ? Palette.mutedInk : value > 0 ? Palette.positive : Palette.orangeStroke)
            .gridColumnAlignment(.trailing)
            .lineLimit(1)
    }
}

/// A row's share of the largest in ``PlanYearWhy``: green for what put you
/// ahead, orange for what put you behind, on a grey track.
struct PlanWhyBar: View {
    let share: Double
    let isPositive: Bool

    var body: some View {
        Capsule()
            .fill(Palette.gridline.opacity(0.6))
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(isPositive ? Palette.green : Palette.orange)
                        .frame(width: max(share > 0 ? 3 : 0, proxy.size.width * CGFloat(min(1, max(0, share)))))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 6, maxHeight: 6)
            .accessibilityHidden(true)
    }
}

/// What happened in the year, a row a month, a month with a milestone
/// flagged and the milestone in bold. The one part of the year's words
/// whose length varies, so it comes last.
struct PlanYearHappenings: View {
    let card: PlanProgressTimeline.Card

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text("What happened")
                .font(PlanProgressFont.text.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if card.noteRows.isEmpty {
                Text(card.year.isLatest ? "Nothing to note yet." : "Nothing to note.")
                    .foregroundStyle(Palette.mutedInk)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(card.noteRows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                            Text(row.month)
                                .foregroundStyle(Palette.secondaryInk)
                                .frame(width: Self.monthWidth, alignment: .leading)
                            if row.hasMilestone {
                                Image(systemName: "flag.fill")
                                    .font(.caption)
                                    .foregroundStyle(Palette.accent)
                                    .accessibilityLabel("Milestone")
                            }
                            Text(row.text)
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .font(PlanProgressFont.text)
    }

    private static var monthWidth: CGFloat {
        #if os(macOS)
        30
        #else
        36
        #endif
    }
}
