import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The Timeline at *Decades* (UI.md, "Decades"): the decades chart on a
/// card titled by the span it covers ("Now to 95") and how sure the plan is
/// ("Money lasts in 9 of 10 futures"), then half tiles, how sure, when you
/// stop, when the pensions start and what's typically left at the end,
/// and *Along the way*, the chapters and their one-offs down a line, with
/// the money typically there as each starts. The same at every width.
struct TimelineDecadesView: View {
    let session: PlanSession

    @Environment(LibraryStore.self) private var library
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            Group {
                if let plan = session.plan {
                    let results = session.baseResults
                    let chapters = session.baseDerived(locale: locale).chapters
                    VStack(alignment: .leading, spacing: Metrics.m) {
                        chartCard(plan, results: results)
                        tiles(chapters, results: results)
                        alongTheWay(chapters, results: results)
                    }
                }
            }
            .padding(layout.gutter)
            .frame(maxWidth: layout.isWide ? Metrics.wideReadableWidth : Metrics.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
    }

    /// The chart on its card, under its title and how sure; on the Mac and
    /// iPad the legend beside the title.
    private func chartCard(_ plan: PlanDocument, results: PlanResults?) -> some View {
        let words = DecadesWords(plan: plan, results: results)
        return VStack(alignment: .leading, spacing: Metrics.m) {
            // The legend beside the title when both fit, else under it.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
                    chartTitle(words)
                    if layout.isWide && results != nil {
                        Spacer(minLength: Metrics.m)
                        DecadesLegend()
                            .fixedSize()
                    }
                }
                VStack(alignment: .leading, spacing: Metrics.s) {
                    chartTitle(words)
                    if layout.isWide && results != nil {
                        DecadesLegend()
                    }
                }
            }
            DecadesChart(plan: plan, results: results, today: .today(), chartHeight: layout.isWide ? 440 : 250,
                         showsLegend: !layout.isWide)
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// "Your money, now to 95" and how sure the plan is.
    private func chartTitle(_ words: DecadesWords) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(layout.isWide ? words.wideTitle : words.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .privacySensitiveInFeedback()
                .accessibilityAddTraits(.isHeader)
            Text(words.subtitle)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .privacySensitiveInFeedback()
        }
    }

    /// How sure, when you stop, when the pensions start, and what's
    /// typically left at the end, half tiles.
    @ViewBuilder
    private func tiles(_ chapters: PlanChaptersModel?, results: PlanResults?) -> some View {
        if let results {
            let all = chapters?.chapters.chapters ?? []
            let left = all.indices.last.flatMap { chapters?.outcomes[$0] }
            let pensions = all.first { $0.kind == .pensions }?.ages.lowerBound
            TileGrid {
                DecadesHowSureTile(results: results)
                    .tileSize(.half)
                HalfTile(tint: .lilac, title: "When you stop", emoji: "🏖️") {
                    Text(verbatim: "\(results.details.focus.age)")
                        .monospacedDigit()
                        .privacySensitiveInFeedback()
                } caption: {
                    Text(results.headline.earliestAge == results.details.focus.age ? "earliest" : "chosen")
                }
                .tileSize(.half)
                if let pensions {
                    HalfTile(tint: .peach, title: "Pensions from", emoji: "🧓") {
                        Text(verbatim: "\(pensions)")
                            .monospacedDigit()
                            .privacySensitiveInFeedback()
                    } caption: {
                        Text("age")
                    }
                    .tileSize(.half)
                }
                if let left {
                    DecadesLeftTile(outcome: left, endAge: results.details.endAge, currency: session.currency)
                        .tileSize(.half)
                }
            }
        }
    }

    @ViewBuilder
    private func alongTheWay(_ chapters: PlanChaptersModel?, results: PlanResults?) -> some View {
        if let chapters, let results, !chapters.outcomes.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.s) {
                SectionHeader("Along the way") {
                    Text("typically, in \(PlanMoney.todaysMoney(session.currency))")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                }
                .padding(.horizontal, Metrics.xs)
                DecadesAlongTheWay(chapters: chapters, results: results,
                                   words: PlanWords(currency: session.currency, locale: locale))
            }
        }
    }
}

/// The decades card's words: "Now to 95", and how sure the plan is.
struct DecadesWords {
    let plan: PlanDocument
    let results: PlanResults?

    private var endAge: Int { results?.details.endAge ?? plan.effectiveEndAge }

    /// "Now to 95".
    var title: String { "Now to \(endAge)" }

    /// "Your money, now to 95", on the Mac and iPad.
    var wideTitle: String { "Your money, now to \(endAge)" }

    /// "Money lasts in 9 of 10 futures" when you stop at the plan's answer,
    /// "At 55, money lasts in 4 of 10 futures" at another age; "Your
    /// records to now" without results.
    var subtitle: String {
        guard let results, let success = results.details.focus.success else { return "Your records to now" }
        let futures = Self.futures(success)
        let age = results.details.focus.age
        if results.headline.earliestAge == age || results.headline.canRetireNow {
            return "Money lasts in \(futures) futures"
        }
        return "At \(age), money lasts in \(futures) futures"
    }

    /// A share as "9 of 10", "86 of 100": the Plan screen's words.
    static func futures(_ share: Double) -> String {
        GlanceText.futures((share * 100).rounded() / 100)
    }

    /// "9 in 10", as *How sure* says it large.
    static func inFutures(_ share: Double) -> String {
        futures(share).replacingOccurrences(of: " of ", with: " in ")
    }
}

/// How sure the plan is, as a half tile (UI.md, "Decades"): "🎯 How
/// sure", the futures whose money lasts to the end when you stop at the
/// plan's age ("9 in 10"), and a dot for each of 10.
struct DecadesHowSureTile: View {
    let results: PlanResults

    var body: some View {
        let focus = results.details.focus
        HalfTile(tint: .sky, title: "How sure", emoji: "🎯") {
            Text(verbatim: focus.success.map(DecadesWords.inFutures) ?? "–")
                .monospacedDigit()
                .privacySensitiveInFeedback()
        } caption: {
            if let success = focus.success {
                FuturesDots(share: success, size: 6)
                    .privacySensitiveInFeedback()
            }
        }
    }
}

/// A dot for each of 10 futures, filled in the tile's accent for those the
/// money lasts in.
struct FuturesDots: View {
    let share: Double
    var size: CGFloat = 9

    var body: some View {
        let filled = Int((min(1, max(0, share)) * 10).rounded())
        HStack(spacing: size > 6 ? 2 : 1) {
            ForEach(0..<10, id: \.self) { index in
                Circle()
                    .fill(index < filled ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.12)))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// What's typically left at the plan's end, as a half tile: "🏁 Left at
/// 95", the median future's money, in today's money.
struct DecadesLeftTile: View {
    let outcome: PlanChaptersModel.Outcome
    let endAge: Int
    let currency: CurrencyCode

    var body: some View {
        HalfTile(tint: .butter, title: "Left at \(max(endAge, outcome.age))", emoji: "🏁") {
            AmountText(Decimal(wholeNumber: outcome.median), currency: currency, short: true)
        } caption: {
            Text("typically")
        }
    }
}

/// *Along the way* (UI.md, "Decades"): the plan's chapters down a line, a
/// dot in each one's colour, then its end. Each chapter says when it starts
/// and its name ("41 · Self-employed"), the money typically there as it
/// starts, its month's money ("5.000 € take-home, 3.000 € spent, 2.000 €
/// saved a month"), where 8 in 10 futures are as a bar, and its one-offs.
/// The end says what's typically left and how often it runs out first.
struct DecadesAlongTheWay: View {
    let chapters: PlanChaptersModel
    let results: PlanResults
    let words: PlanWords

    @Environment(\.locale) private var locale

    private struct Stop: Identifiable {
        var id: Int
        var color: Color
        var title: String
        /// The money typically there; `nil` for the first chapter, which starts now.
        var median: Double?
        var range: ClosedRange<Double>?
        var summary: AmountSentence
        var oneOffs: [AmountSentence]
        var isEnd = false
    }

    private var stops: [Stop] {
        let all = chapters.chapters.chapters
        let lines = PlanChapterLine.lines(model: chapters, results: results, words: words)
        var stops: [Stop] = lines.map { line in
            let index = line.index
            let before = index > 0 ? chapters.outcomes[index - 1] : nil
            let start = index == 0 ? "Now" : "\(all[index].ages.lowerBound)"
            return Stop(id: index, color: PlanChapterColors.color(line.style), title: "\(start) · \(line.title)",
                        median: before?.median, range: before.map { $0.low...max($0.low, $0.high) },
                        summary: line.summary, oneOffs: line.oneOffs)
        }
        if let last = all.indices.last, let outcome = chapters.outcomes[last] {
            var summary = AmountSentence("Left over, typically.")
            if let success = results.details.focus.success, success < 0.995 {
                summary += " Runs out first in \(DecadesWords.futures(1 - success)) futures."
            }
            stops.append(Stop(id: stops.count, color: Palette.ink,
                              title: "\(max(results.details.endAge, outcome.age)) · The plan's end",
                              median: outcome.median, range: nil, summary: summary, oneOffs: [], isEnd: true))
        }
        return stops
    }

    var body: some View {
        let stops = self.stops
        let largest = max(stops.compactMap { $0.range?.upperBound }.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(stops) { stop in
                row(stop, isLast: stop.id == stops.last?.id, largest: largest)
            }
        }
        .padding(.horizontal, Metrics.l)
        .padding(.vertical, Metrics.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func row(_ stop: Stop, isLast: Bool, largest: Double) -> some View {
        HStack(alignment: .top, spacing: Metrics.m) {
            VStack(spacing: 2) {
                Circle()
                    .fill(stop.isEnd ? AnyShapeStyle(Palette.card) : AnyShapeStyle(stop.color))
                    .overlay {
                        if stop.isEnd { Circle().strokeBorder(Palette.ink, lineWidth: 2) }
                    }
                    .frame(width: 14, height: 14)
                    .padding(.top, 16)
                if !isLast {
                    Rectangle()
                        .fill(Palette.border)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 14)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    Text(stop.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .privacySensitiveInFeedback()
                    Spacer(minLength: Metrics.s)
                    if let median = stop.median {
                        AmountText(Decimal(wholeNumber: median), currency: words.currency, short: true)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                if !stop.summary.isEmpty {
                    AmountSentenceText(stop.summary)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let range = stop.range, let median = stop.median {
                    rangeBar(range, median: median, largest: largest)
                        .padding(.top, Metrics.xs)
                    AmountSentenceText("8 in 10 futures: \(amount: short(range.lowerBound)) to "
                                       + "\(amount: short(range.upperBound))")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                ForEach(Array(stop.oneOffs.enumerated()), id: \.offset) { _, oneOff in
                    AmountSentenceText("🗓️ " + oneOff)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                if !isLast { Divider() }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Where 8 in 10 futures are, washed in the accent on a grey track
    /// from zero to the largest, with a tick at the median.
    private func rangeBar(_ range: ClosedRange<Double>, median: Double, largest: Double) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = { (value: Double) in CGFloat(max(0, min(1, value / largest))) * width }
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.page)
                Capsule().fill(Palette.accent.opacity(0.28))
                    .frame(width: max(4, x(range.upperBound) - x(range.lowerBound)))
                    .offset(x: x(range.lowerBound))
                Capsule().fill(Palette.accent)
                    .frame(width: 3, height: 12)
                    .offset(x: min(max(0, x(median) - 1.5), width - 3))
            }
        }
        .frame(height: 8)
        .privacySensitiveInFeedback()
        .accessibilityHidden(true)
    }

    private func short(_ value: Double) -> String {
        ShortAmount.text(Decimal(wholeNumber: value), currency: words.currency, locale: locale)
    }
}
