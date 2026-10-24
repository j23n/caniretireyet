import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// The Timeline at *Decades* (UI.md, "Decades"): the decades chart on a
/// card titled by the span it covers ("Now to 95") and how sure the plan is
/// ("Money lasts in 9 of 10 futures"), then *Along the way*, the money
/// typically there as each chapter starts and at the end. On the Mac and
/// iPad *How sure* and *Along the way* are beside the chart.
struct TimelineDecadesView: View {
    let session: PlanSession

    @Environment(LibraryStore.self) private var library
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale

    /// The column beside the chart on the Mac and iPad.
    private static let sideWidth: CGFloat = 300

    var body: some View {
        ScrollView {
            Group {
                if let plan = session.plan {
                    let results = session.baseResults
                    let chapters = session.baseDerived(locale: locale).chapters
                    if layout.isWide {
                        HStack(alignment: .top, spacing: Metrics.l) {
                            chartCard(plan, results: results)
                            VStack(alignment: .leading, spacing: Metrics.l) {
                                if let results {
                                    DecadesHowSureCard(results: results)
                                }
                                alongTheWay(chapters, plan: plan, results: results)
                            }
                            .frame(width: Self.sideWidth)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: Metrics.m) {
                            chartCard(plan, results: results)
                            alongTheWay(chapters, plan: plan, results: results)
                        }
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
            HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
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
                if layout.isWide && results != nil {
                    Spacer(minLength: Metrics.m)
                    DecadesLegend()
                        .fixedSize()
                }
            }
            DecadesChart(plan: plan, results: results, today: .today(), chartHeight: layout.isWide ? 440 : 250,
                         showsLegend: !layout.isWide)
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder
    private func alongTheWay(_ chapters: PlanChaptersModel?, plan: PlanDocument, results: PlanResults?) -> some View {
        if let chapters, let results, !chapters.outcomes.isEmpty {
            DecadesAlongTheWayCard(chapters: chapters, endAge: results.details.endAge, markers: results.markers,
                                   showsTitle: layout.isWide)
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

/// How sure the plan is, on the Mac and iPad beside the decades chart: the
/// futures whose money lasts to the end when you stop at the plan's age
/// ("9 in 10", "futures last to 95, stopping at 63"), and at the age you
/// planned when that's another one ("4 in 10", "if you stop at 55, as
/// planned").
struct DecadesHowSureCard: View {
    let results: PlanResults

    var body: some View {
        let focus = results.details.focus
        let end = results.details.endAge
        VStack(alignment: .leading, spacing: Metrics.m) {
            Text("How sure")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if let success = focus.success {
                figure(DecadesWords.inFutures(success), detail: "futures last to \(end), stopping at \(focus.age)")
            }
            if let target = results.headline.targetAge, target != focus.age,
               let success = results.headline.successAtTarget {
                figure(DecadesWords.inFutures(success), detail: "if you stop at \(target), as planned")
            }
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func figure(_ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.title.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .privacySensitiveInFeedback()
        .accessibilityElement(children: .combine)
    }
}

/// *Along the way* (UI.md, "Decades"): the money typically there as each
/// chapter of the plan starts, and what's typically left at its end, a row
/// each: the age in grey, the chapter, the amount ("41 · Self-employed ·
/// 520.000 €", "95 · Money left · 350.000 €"). On the Mac and iPad, titled,
/// with the plan's other events in a line under the rows.
struct DecadesAlongTheWayCard: View {
    let chapters: PlanChaptersModel
    let endAge: Int
    var markers: [ChartMarker] = []
    var showsTitle = false

    private struct Row: Identifiable {
        var id: Int
        var age: Int
        var name: String
        var amount: Double
    }

    /// Each chapter after the first as it starts, with the money at the end
    /// of the one before, then the money left.
    private var rows: [Row] {
        let all = chapters.chapters.chapters
        var rows: [Row] = []
        for index in all.indices.dropFirst() {
            if let before = chapters.outcomes[index - 1] {
                rows.append(Row(id: rows.count, age: all[index].ages.lowerBound,
                                name: chapters.title(of: all[index]), amount: before.median))
            }
        }
        if let last = all.indices.last, let outcome = chapters.outcomes[last] {
            rows.append(Row(id: rows.count, age: max(endAge, outcome.age), name: "Money left",
                            amount: outcome.median))
        }
        return rows
    }

    /// The plan's events other than when you stop: "New car 2031 · Inheritance 62".
    private var events: String? {
        let labels = markers.filter { $0.kind != .retirement }.map(\.label)
        return labels.isEmpty ? nil : labels.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTitle {
                Text("Along the way")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, Metrics.l)
                    .padding(.bottom, Metrics.xs)
            }
            HStack {
                Text(showsTitle ? "Age" : "At")
                Spacer(minLength: Metrics.s)
                Text("Typically")
            }
            .font(.footnote)
            .foregroundStyle(Palette.mutedInk)
            .padding(.top, showsTitle ? Metrics.xs : Metrics.m)
            .padding(.bottom, 2)
            .accessibilityHidden(true)
            ForEach(rows) { row in
                if row.id > 0 {
                    Divider()
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: "\(row.age)")
                        .monospacedDigit()
                        .foregroundStyle(Palette.mutedInk)
                        .frame(width: 28, alignment: .leading)
                        .privacySensitiveInFeedback()
                    Text(row.name)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .privacySensitiveInFeedback()
                    Spacer(minLength: Metrics.s)
                    AmountText(Decimal(wholeNumber: row.amount), short: true)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .fixedSize()
                        .layoutPriority(1)
                }
                .font(.body)
                .padding(.vertical, 11)
                .accessibilityElement(children: .combine)
            }
            if showsTitle, let events {
                Text(events)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
                    .padding(.top, Metrics.xs)
            }
        }
        .padding(.horizontal, Metrics.l)
        .padding(.bottom, Metrics.xs)
        .padding(.bottom, showsTitle ? Metrics.m : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
