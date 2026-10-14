import Glance
import Model
import SwiftUI

extension SavingAsTime {
    /// "You saved 1.500 €, about 2½ weeks of the life you plan. Markets
    /// added about 7 more." (UI.md, "Saving as time"): the amount hides
    /// with the eye, the time doesn't give it away on its own.
    func sentence(saved: Decimal, currency: CurrencyCode, locale: Locale = .current) -> AmountSentence {
        var sentence: AmountSentence =
            "You saved \(amount: AmountFormat.amount(saved, currency: currency, locale: locale)), \(savedText)."
        if let markets = marketsSentence { sentence.append(words: " " + markets) }
        return sentence
    }
}

/// What a change saved, said as time of the life the plan describes, under
/// *What moved*, *This year* and the check-in's ending (UI.md, "Saving as
/// time"); nothing without a saving or the plan's spending.
struct SavingAsTimeText: View {
    let saved: Decimal
    let markets: Decimal
    /// The main plan's retirement spending a year (Planner's `MilestoneLadder.spending`).
    let yearlySpending: Decimal?

    @Environment(\.baseCurrency) private var currency
    @Environment(\.locale) private var locale

    var body: some View {
        if let time = SavingAsTime(saved: saved, markets: markets, yearlySpending: yearlySpending) {
            AmountSentenceText(time.sentence(saved: saved, currency: currency, locale: locale))
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
