import Model
import Planner
import SwiftUI
import Tracker

// A year in words (UI.md, "Progress"): under the strip on iPhone, in each
// year's card on the Mac and iPad.

/// The chosen year under the strip on iPhone (UI.md, "Progress"): its
/// title and change, *‹ ›* to step through the years, and its words.
struct PlanYearDetails: View {
    let card: PlanProgressTimeline.Card
    let index: Int
    let count: Int
    var onSelect: (Int) -> Void = { _ in }
    /// *Add What You Planned in 2021…*, for a year without a baseline: opens
    /// *Add Past Baseline…* at its start.
    var onAddPastBaseline: ((Int) -> Void)?

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    private var year: PlanProgressYear { card.year }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack(alignment: .center, spacing: Metrics.s) {
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
                Spacer(minLength: Metrics.s)
                if count > 1 {
                    PlanStepButtons(index: index, count: count, select: onSelect)
                }
            }
            PlanYearWords(card: card, onAddPastBaseline: onAddPastBaseline)
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: shape)
        .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
    }
}

/// A year in words (UI.md, "Progress"), said once: the year in a line; what
/// you saved and what markets added, as a bar with a mark at what its
/// baseline planned you'd save by then; what happened, a row a month; and
/// why you're ahead or behind. Under the strip on iPhone
/// (``PlanYearDetails``), in each year's card on the Mac and iPad.
struct PlanYearWords: View {
    let card: PlanProgressTimeline.Card
    /// *Add What You Planned in 2021…*, for a year without a baseline.
    var onAddPastBaseline: ((Int) -> Void)?

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale
    @State private var fillsPastPrices = false

    private var year: PlanProgressYear { card.year }

    private func amount(_ value: Decimal) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(abs(value), currency: card.currency, locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            if let summary = card.summary {
                Text(summary)
                    .font(PlanProgressFont.summary)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = PlanProgressText.pricesNote(year, locale: locale) {
                Text(note)
                    .font(PlanProgressFont.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if year.from != year.to {
                savedAndMarkets
            }
            if !card.noteRows.isEmpty {
                monthRows
            }
            if year.baseline == nil, let onAddPastBaseline {
                Button("Add What You Planned in \(String(year.year))…") { onAddPastBaseline(year.year) }
                    .buttonStyle(.borderless)
                    .font(PlanProgressFont.text.weight(.semibold))
            }
            if year.position != nil {
                Divider()
                if let explanation = year.explanation {
                    PlanGapExplanationView(explanation: explanation, year: year,
                                           currency: year.positionCurrency ?? card.currency)
                } else if let january = PlanProgressText.january(year, hidesAmounts: hidesAmounts, locale: locale) {
                    Text(january)
                        .font(PlanProgressFont.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !year.isComplete || card.actual.contains(where: { !$0.isComplete }) {
                OldPriceNoteView(text: "Some prices or exchange rates were missing: those holdings count as zero, "
                                     + "and the line is dotted there.",
                                 systemImage: "exclamationmark.triangle") { fillsPastPrices = true }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pastPricesSheet(isPresented: $fillsPastPrices)
    }

    /// What the year's baseline planned you'd save over the same stretch as
    /// the bar; `nil` without one, or when it started later in the year.
    private var plannedSaving: Decimal? {
        guard let explanation = year.explanation, let baseline = year.baseline?.baseline,
              baseline.start.date <= year.from, explanation.plannedSaving > 0 else { return nil }
        return explanation.plannedSaving
    }

    /// What you saved and what markets added as one bar, with a mark where
    /// the baseline planned your saving to reach; under it, the two in
    /// words, in the bar's colours.
    private var savedAndMarkets: some View {
        let saved = max(0, year.change.newMoney.doubleValue)
        let markets = max(0, year.change.market.doubleValue)
        let planned = plannedSaving?.doubleValue
        let full = max(saved + markets, planned ?? 0)
        return VStack(alignment: .leading, spacing: Metrics.xs) {
            if full > 0 {
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
                .frame(height: plannedSaving == nil ? 10 : 30)
                .accessibilityHidden(true)
            }
            savedAndMarketsText
        }
    }

    /// "You saved 20.486 € · markets added 6.628 €", each in its colour on the bar.
    private var savedAndMarketsText: Text {
        let saved = year.change.newMoney
        let markets = year.change.market
        let savedWords = saved >= 0 ? "You saved \(amount(saved))" : "You took out \(amount(saved))"
        let marketWords = markets >= 0 ? "markets added \(amount(markets))" : "markets took \(amount(markets))"
        let savedText = Text(savedWords).foregroundStyle(Palette.ink.opacity(0.8))
        let marketText = Text(marketWords).foregroundStyle(markets >= 0 ? Palette.accent : Palette.orangeStroke)
        let dot = Text(" · ").foregroundStyle(Palette.secondaryInk)
        return Text("\(savedText)\(dot)\(marketText)")
            .font(PlanProgressFont.text.weight(.semibold))
    }

    /// What happened, a row a month; a month with a milestone is flagged.
    private var monthRows: some View {
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

/// Why the year is ahead of or behind its baseline (PROGRESS.md, *Why*;
/// UI.md, "Progress"), a row each: the gap going into the year (what you
/// had against what the baseline started from or expected); what you saved
/// against what it planned; what markets did against what it expected;
/// what inflation took; the rest. Each in the baseline's money, adding up
/// to the total under them: ahead of or behind January.
struct PlanGapExplanationView: View {
    let explanation: GapExplanation
    let year: PlanProgressYear
    let currency: CurrencyCode

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    private struct Row: Identifiable {
        var title: String
        var value: Decimal
        var detail: String?
        var id: String { title }
    }

    private func amount(_ value: Decimal) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.amount(abs(value), currency: currency, locale: locale)
    }

    private func signed(_ value: Decimal) -> String {
        hidesAmounts ? AmountFormat.hidden : AmountFormat.signedAmount(value, currency: currency, locale: locale)
    }

    /// "Why you're ahead", "Why you ended behind".
    private var title: String {
        let side = explanation.end >= 0 ? "ahead" : "behind"
        return year.isLatest ? "Why you're \(side)" : "Why you ended \(side)"
    }

    private var rows: [Row] {
        let expectation = year.expectation(locale: locale)
        let byNow = year.isLatest ? " by now" : ""
        var rows: [Row] = []
        if abs(explanation.start) >= 1 {
            rows.append(startRow)
        }
        let saved = explanation.newMoney >= 0 ? "You saved \(amount(explanation.newMoney))"
            : "You took out \(amount(explanation.newMoney))"
        let planned = explanation.plannedSaving >= 0 ? "planned \(amount(explanation.plannedSaving))"
            : "planned you'd take out \(amount(explanation.plannedSaving))"
        rows.append(Row(title: "Saving", value: explanation.saving,
                        detail: "\(saved); \(expectation) \(planned)\(byNow)."))
        let market = explanation.market >= 0 ? "They added \(amount(explanation.market))"
            : "They took \(amount(explanation.market))"
        let expected = explanation.expectedMarket >= 0 ? "expected \(amount(explanation.expectedMarket))"
            : "expected them to take \(amount(explanation.expectedMarket))"
        rows.append(Row(title: "Markets", value: explanation.markets,
                        detail: "\(market); \(expectation) \(expected)."))
        if let inflation = explanation.inflation {
            rows.append(Row(title: "Inflation", value: inflation))
        }
        if abs(explanation.other) >= 1 {
            rows.append(Row(title: "Other", value: explanation.other,
                            detail: "Balances that changed without a recorded flow, and exchange rates."))
        }
        return rows
    }

    /// The gap where the stretch starts: carried into the year ("On 31 Dec
    /// you had 134.392 €; January started from 121.835 €."), or, on a
    /// baseline's own start later in the year, your money then as the
    /// library values it now against what it started from.
    private var startRow: Row {
        let baselineStart = year.baseline?.baseline.start.date
        let start = max(year.from, baselineStart ?? year.from)
        let expectation = year.expectation(locale: locale)
        let day = AmountFormat.shortDate(start, locale: locale)
        let expected = baselineStart.map { $0 >= year.from } == true
            ? "\(expectation) started from \(amount(explanation.expectedStart))"
            : "\(expectation) expected \(amount(explanation.expectedStart))"
        if start == year.from {
            return Row(title: "Going into \(year.year)", value: explanation.start,
                       detail: "On \(day) you had \(amount(explanation.actualStart)); \(expected).")
        }
        return Row(title: "On \(day)", value: explanation.start,
                   detail: "You had \(amount(explanation.actualStart)), as the library values it now; \(expected).")
    }

    /// "Ahead of January", "Ended behind your 2021 plan".
    private var totalTitle: String {
        let expectation = year.expectation(locale: locale)
        let side = explanation.end >= 0 ? "ahead of" : "behind"
        return year.isLatest ? "\(side.prefix(1).uppercased() + side.dropFirst()) \(expectation)"
            : "Ended \(side) \(expectation)"
    }

    /// "January expected 137.280 € by now, in January's money." For a past
    /// year, how it compares with the baseline's futures.
    private var totalDetail: String? {
        guard let position = year.position else { return nil }
        let expectation = year.expectation(locale: locale)
        let when = year.isLatest ? "by now" : "by \(AmountFormat.shortDate(year.to, locale: locale))"
        var text = "\(year.expectationTitle(locale: locale)) expected \(amount(position.median)) \(when)"
        if explanation.inflation != nil { text += ", in \(expectation)'s money" }
        text += "."
        guard !year.isLatest else { return text }
        if let percentile = position.percentile {
            text += " That's more than in \(Int(wholeNumber: percentile)) of its 100 futures."
        } else if position.isAboveNinetieth {
            text += " That's more than in 9 of its 10 futures."
        } else if position.isBelowTenth {
            text += " That's less than in 9 of its 10 futures."
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(title)
                .font(PlanProgressFont.text.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                rowView(title: row.title, value: row.value, detail: row.detail)
            }
            Divider()
            rowView(title: totalTitle, value: explanation.end, detail: totalDetail, isTotal: true)
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    private func rowView(title: String, value: Decimal, detail: String?, isTotal: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(title)
                    .fontWeight(isTotal ? .semibold : .regular)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: Metrics.s)
                Text(signed(value))
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .foregroundStyle(value >= 0 ? Palette.positive : Palette.orangeStroke)
            }
            .font(PlanProgressFont.text)
            if let detail {
                Text(detail)
                    .font(PlanProgressFont.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
