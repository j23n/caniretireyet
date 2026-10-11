import Model
import SwiftUI

/// Trends' *Year by year* (UI.md, "Trends"): a row per calendar year, newest
/// first, graded in words on what you control (*You saved*, *You spent*)
/// and what markets did, never as a letter or a score. On the Mac and iPad
/// a table with the amounts each word compares under it; on iPhone the
/// words alone. A row opens its year on Progress.
struct PlanYearGradesTable: View {
    let years: [PlanYearGrade]
    var isWide = false
    let onShowYear: (Int) -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    private var yearWidth: CGFloat { isWide ? 84 : 56 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlanYearColumns(yearWidth: yearWidth) {
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

    private func row(_ grade: PlanYearGrade) -> some View {
        PlanYearColumns(yearWidth: yearWidth) {
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
            if grade.hasBaseline {
                cell(grade.saved?.words, amounts: savedAmounts(grade))
                cell(grade.spent?.words, amounts: spentAmounts(grade))
            } else {
                Text(PlanYearGrade.noPlan)
                    .font(PlanProgressFont.text)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutValue(key: PlanYearColumns.Span.self, value: 2)
            }
            cell(grade.marketYear?.word, amounts: marketAmounts(grade))
        }
    }

    /// A grade, "—" without one; on the Mac and iPad the amounts it
    /// compares under it, which hide with the eye.
    private func cell(_ words: String?, amounts: AmountSentence?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(words ?? PlanYearGrade.ungraded)
                .font(PlanProgressFont.text)
                .foregroundStyle(words == nil ? Palette.secondaryInk : Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
            if isWide, let amounts {
                AmountSentenceText(amounts)
                    .font(PlanProgressFont.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func amount(_ value: Decimal) -> AmountSentence {
        .amount(AmountFormat.amount(value, currency: library.baseCurrency, locale: locale))
    }

    /// "20.486 € · planned 13.463 €", "… by now" for the year still going.
    private func savedAmounts(_ grade: PlanYearGrade) -> AmountSentence {
        guard let planned = grade.plannedSaving else { return amount(grade.putIn) }
        let byNow = grade.isSoFar ? " by now" : ""
        return "\(amount(grade.putIn)) · planned \(amount(planned))\(byNow)"
    }

    /// "31.600 € a year · planned 36.000 €"; `nil` without money out recorded.
    private func spentAmounts(_ grade: PlanYearGrade) -> AmountSentence? {
        guard let spent = grade.moneyOutPerYear else { return nil }
        guard let planned = grade.plannedSpending else { return "\(amount(spent)) a year" }
        return "\(amount(spent)) a year · planned \(amount(planned))"
    }

    /// "+12.400 € · 9%": what markets added, and its share of what you had going in.
    private func marketAmounts(_ grade: PlanYearGrade) -> AmountSentence? {
        guard grade.marketYear != nil else { return nil }
        let added = AmountSentence.amount(AmountFormat.signedAmount(grade.markets, currency: library.baseCurrency,
                                                                    locale: locale))
        let share = AmountFormat.percent(grade.markets / grade.start, digits: 0, signed: true, locale: locale)
        return "\(added) · \(share)"
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
