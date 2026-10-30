import Model
import SwiftUI
import Tracker

/// *Start a month* on iPhone (UI.md, "Your months"): a month with nothing
/// in it yet asks how to fill it in, with a card for each way. *Import CSV*
/// reads the bank's export into lines (``MonthImportSheet``); *Type Totals*
/// takes four numbers from the bank's app (``MonthTypedTotalsSheet``),
/// except for the month still to come. Once either is in, the month's lines
/// screen shows its lines, or the totals typed, in its place.
struct MonthStartView: View {
    let month: AccountMonth
    let currency: CurrencyCode
    let importCSV: () -> Void
    let typeTotals: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.m) {
                AmountSentenceText(question)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
                choice("Import CSV",
                       detail: "Your bank's export for the month. Every line is kept, to check one by one.",
                       action: importCSV)
                if !MonthText.isStillToCome(month.through) {
                    choice("Type Totals", detail: "Four numbers from your bank's app, when there's no CSV.",
                           action: typeTotals)
                }
            }
            .padding(layout.gutter)
        }
    }

    /// "Opens at 412,30 €. How do you want to fill in October?"
    private var question: AmountSentence {
        let ask = "How do you want to fill in \(AmountFormat.monthName(month.through, locale: locale))?"
        guard let opening = month.opening else { return AmountSentence(ask) }
        let amount = AmountFormat.amount(opening, currency: currency, precision: .cents, locale: locale)
        return "Opens at \(amount: amount). " + AmountSentence(ask)
    }

    private func choice(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Metrics.m) {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Palette.accent)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Metrics.s)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.mutedInk)
                    .accessibilityHidden(true)
            }
            .padding(Metrics.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!library.canEdit)
    }
}
