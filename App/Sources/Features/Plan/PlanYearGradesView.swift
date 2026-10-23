import Glance
import Model
import Planner
import SwiftUI

/// Trends' *Year by year* (UI.md, "Trends"): a row per calendar year, newest
/// first, graded in words on what you control (*You saved*, *You spent*)
/// and what markets did, never as a letter or a score, with the amounts
/// each word compares under it. A row opens its year on Progress.
struct PlanYearGradesTable: View {
    let years: [PlanProgressYear]
    let onShowYear: (Int) -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale

    /// The Mac and iPad: the amounts in full, on a line. On iPhone they're
    /// short (`20,5K €`), a line each, in a smaller font, so they fit its
    /// narrow columns.
    private var isWide: Bool { layout.isWide }

    private var yearWidth: CGFloat { isWide ? 84 : 56 }

    private var columnSpacing: CGFloat { isWide ? Metrics.m : Metrics.s }

    private var amountsFont: Font { isWide ? PlanProgressFont.caption : .caption2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanYearColumns(yearWidth: yearWidth, spacing: columnSpacing) {
                Color.clear.frame(height: 0)
                header("You saved")
                header("You spent")
                header("Markets")
            }
            .padding(.bottom, Metrics.s)
            .accessibilityHidden(true)
            ForEach(years) { grade in
                Divider()
                Button {
                    onShowYear(grade.year)
                } label: {
                    row(grade)
                        .padding(.vertical, Metrics.s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: grade.spoken))
                .accessibilityHint("Opens the year on Progress")
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(PlanProgressFont.caption.weight(.semibold))
            .foregroundStyle(Palette.secondaryInk)
    }

    private func row(_ grade: PlanProgressYear) -> some View {
        PlanYearColumns(yearWidth: yearWidth, spacing: columnSpacing) {
            VStack(alignment: .leading, spacing: 1) {
                Text(String(grade.year))
                    .font(PlanProgressFont.text.weight(.semibold))
                    .monospacedDigit()
                if grade.isSoFar {
                    Text("so far")
                        .font(PlanProgressFont.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .foregroundStyle(Palette.ink)
            .privacySensitiveInFeedback()
            if grade.baseline != nil {
                cell(grade.savedGrade?.words, amounts: savedAmounts(grade))
                cell(grade.spent?.words, amounts: spentAmounts(grade))
            } else {
                Text(PlanProgressYear.noPlan)
                    .font(PlanProgressFont.text)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutValue(key: PlanYearColumns.Span.self, value: 2)
            }
            cell(grade.marketYear?.word, amounts: marketAmounts(grade))
        }
    }

    /// A grade, "—" without one, and the amounts it compares under it,
    /// which hide with the eye: joined by " · " on the Mac and iPad, a line
    /// each on iPhone.
    private func cell(_ words: String?, amounts: [AmountSentence]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(words ?? PlanProgressYear.ungraded)
                .font(PlanProgressFont.text)
                .foregroundStyle(words == nil ? Palette.secondaryInk : Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
            if !amounts.isEmpty {
                AmountSentenceText(amounts.joined(separator: isWide ? " · " : "\n"))
                    .font(amountsFont)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// `20.486 €` on the Mac and iPad, `20,5K €` on iPhone.
    private func amount(_ value: Decimal, signed: Bool = false) -> AmountSentence {
        let currency = library.baseCurrency
        if !isWide {
            return .amount(ShortAmount.text(value, currency: currency, locale: locale, thousands: true,
                                            signed: signed))
        }
        return .amount(signed
            ? AmountFormat.signedAmount(value, currency: currency, locale: locale)
            : AmountFormat.amount(value, currency: currency, locale: locale))
    }

    /// "20.486 €", "planned 13.463 €", "… by now" for the year still going
    /// on the Mac and iPad; on iPhone the year's "so far" says it.
    private func savedAmounts(_ grade: PlanProgressYear) -> [AmountSentence] {
        guard let planned = grade.plannedSaving else { return [amount(grade.saved)] }
        let byNow = grade.isSoFar && isWide ? " by now" : ""
        return [amount(grade.saved), "planned \(amount(planned))\(byNow)"]
    }

    /// "31.600 € a year", "planned 36.000 €"; none without money in and out recorded.
    private func spentAmounts(_ grade: PlanProgressYear) -> [AmountSentence] {
        guard let spent = grade.spentPerYear else { return [] }
        // On iPhone "a year" wraps as one, under the amount.
        let aYear = isWide ? "a year" : "a\u{00A0}year"
        let perYear: AmountSentence = "\(amount(spent)) \(aYear)"
        guard let planned = grade.plannedSpending else { return [perYear] }
        return [perYear, "planned \(amount(planned))"]
    }

    /// "+12.400 €", "+9%": what markets added, and its share of what you had going in.
    private func marketAmounts(_ grade: PlanProgressYear) -> [AmountSentence] {
        guard grade.marketYear != nil else { return [] }
        let markets = grade.change.market
        let share = AmountFormat.percent(markets / grade.change.start, digits: 0, signed: true, locale: locale)
        return [amount(markets, signed: true), AmountSentence(share)]
    }
}

/// *Year by year*'s columns: the year at a fixed width, then three equal
/// columns for the words; a cell can span more than one (``Span``), as
/// "No plan to compare with" does. The header and every row share it, so
/// the columns line up.
struct PlanYearColumns: Layout {
    var yearWidth: CGFloat
    var spacing: CGFloat = Metrics.m

    /// The columns after the year's.
    private static let columns = 3
    /// The width laid out when the parent offers none.
    private static let fallbackWidth: CGFloat = 480

    /// How many columns a cell spans: 1 unless set.
    struct Span: LayoutValueKey {
        static let defaultValue = 1
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? Self.fallbackWidth
        let heights = zip(subviews, widths(width, subviews: subviews)).map { subview, width in
            subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: nil))
            x += width + spacing
        }
    }

    /// Each subview's width: the first the year's, the others their columns'.
    private func widths(_ total: CGFloat, subviews: Subviews) -> [CGFloat] {
        let count = CGFloat(Self.columns)
        let column = max(0, (total - yearWidth - spacing * count) / count)
        return subviews.indices.map { index in
            guard index != subviews.startIndex else { return yearWidth }
            let span = CGFloat(max(1, subviews[index][Span.self]))
            return column * span + spacing * (span - 1)
        }
    }
}
