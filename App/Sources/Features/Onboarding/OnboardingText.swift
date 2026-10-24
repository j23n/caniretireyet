import Foundation
import Glance
import Model
import Planner

/// First launch's sentences (UI.md, "Empty states and first launch"), free
/// of SwiftUI so they can be tested.
enum OnboardingText {
    // MARK: About you

    /// Under the country: what it sets. "Totals in Euro, adjusted for
    /// inflation with Germany's prices."; "Totals in Euro." without an
    /// index for it.
    static func countryLine(country: CountryCode?, currency: CurrencyCode, locale: Locale = .current) -> String {
        let name = locale.localizedString(forCurrencyCode: currency.rawValue) ?? currency.rawValue
        guard let index = country.flatMap({ IndexID.consumerPrices($0) }) ?? IndexID.consumerPrices(currency: currency)
        else { return "Totals in \(name)." }
        return "Totals in \(name), adjusted for inflation with \(InflationIndexText.prices(of: index, locale: locale))."
    }

    // MARK: Money

    /// Under pay and spending, as you type: "You save about 1.400 € a
    /// month, a third of your pay.", "You spend all you take home.", or
    /// "You spend about 300 € a month more than you take home."; `nil`
    /// without both.
    static func savingLine(_ answers: StarterAnswers, currency: CurrencyCode,
                           locale: Locale = .current) -> AmountSentence? {
        guard let saving = answers.saving else { return nil }
        let about = StarterSetup.roundedToTwoFigures(abs(saving.perMonth))
        let amount = AmountFormat.amount(about, currency: currency, locale: locale)
        if about == 0 { return "You spend all you take home." }
        if saving.perMonth < 0 { return "You spend about \(amount: amount) a month more than you take home." }
        return "You save about \(amount: amount) a month, \(share(saving.share, locale: locale)) of your pay."
    }

    /// "half", "a third", "a quarter", "a fifth", "two thirds", "three
    /// quarters" when a share is within a point and a half of one, else
    /// "38%".
    static func share(_ fraction: Double, locale: Locale = .current) -> String {
        let words: [(Double, String)] = [(1.0 / 2, "half"), (1.0 / 3, "a third"), (1.0 / 4, "a quarter"),
                                         (1.0 / 5, "a fifth"), (2.0 / 3, "two thirds"), (3.0 / 4, "three quarters")]
        if let match = words.first(where: { abs($0.0 - fraction) < 0.015 }) { return match.1 }
        return AmountFormat.percent(fraction, digits: 0, locale: locale)
    }

    // MARK: Pension and retirement

    /// Under the state pension: where its amount comes from, and what
    /// leaving it empty does.
    static func statePensionNote(country: CountryCode?) -> String {
        "You can find this amount in \(CountryDefaults.statePensionSource(for: country)). Leave it empty to "
            + "plan without a state pension, which is more cautious."
    }

    /// Under the tax rate: prefilled for the country, or what leaving it
    /// empty does.
    static func taxNote(country: CountryCode?, isDefault: Bool, locale: Locale = .current) -> String {
        if isDefault, let country {
            return "Prefilled for \(CountryChoices.name(of: country, locale: locale)). You can change it later in "
                + "the plan."
        }
        return "Leave it empty to plan without tax on investments. You can change it later in the plan."
    }

    // MARK: The answer

    /// Over the answer: "Your last Monday at work could be" when there's a
    /// date, else "Your first answer" (or "Your answer", for a library that
    /// was already there).
    static func revealLead(_ headline: RetirementAnswer, openedExistingLibrary: Bool = false) -> String {
        if LastMonday(headline) != nil { return "Your last Monday at work could be" }
        return openedExistingLibrary ? "Your answer" : "Your first answer"
    }

    /// The answer, big: the last Monday at work, "14 May 2052", else "Yes."
    /// or "Not yet."
    static func revealTitle(_ headline: RetirementAnswer, locale: Locale = .current) -> String {
        if let lastMonday = LastMonday(headline) { return GlanceText.lastMonday(lastMonday.date, locale: locale) }
        return headline.canRetireNow ? "Yes." : "Not yet."
    }

    /// Under it, the age and how sure: "At 58, in 9 of 10 futures.", "You
    /// could retire today, in at least 9 of 10 futures.", or "No age works
    /// in 9 of 10 futures yet."
    static func revealLine(_ headline: RetirementAnswer) -> String {
        let futures = GlanceText.futures(headline.confidence)
        if headline.canRetireNow { return "You could retire today, in at least \(futures) futures." }
        guard let age = headline.earliestAge else { return "No age works in \(futures) futures yet." }
        return "At \(age), in \(futures) futures."
    }

    // MARK: The answer, once you've stopped working

    /// Whether your money lasts to the plan's end in the plan's share of
    /// futures, retiring at your age today.
    static func moneyLasts(_ headline: RetirementAnswer) -> Bool {
        headline.canRetireNow || (headline.successAtTarget ?? 0) >= headline.confidence
    }

    /// The answer's first words once you've stopped working: "Yes." when
    /// your money lasts, else "Not quite."
    static func retiredTitle(_ headline: RetirementAnswer) -> String {
        moneyLasts(headline) ? "Yes." : "Not quite."
    }

    /// "Your money lasts to 95 in at least 9 of 10 futures.", or "Your
    /// money lasts to 95 in 7 of 10 futures. Your plan aims for 9 of 10."
    /// (the share rounded down to tenths).
    static func retiredLine(_ headline: RetirementAnswer, endAge: Int) -> String {
        let aim = GlanceText.futures(headline.confidence)
        if moneyLasts(headline) { return "Your money lasts to \(endAge) in at least \(aim) futures." }
        let tenths = Int(((headline.successAtTarget ?? headline.successToday ?? 0) * 10).rounded(.down))
        let share = tenths == 0 ? "fewer than 1 of 10" : "\(tenths) of 10"
        return "Your money lasts to \(endAge) in \(share) futures. Your plan aims for \(aim)."
    }

    /// "Spending up to 2.300 € a month lasts in 9 of 10 futures."; `nil`
    /// without a sustainable spending.
    static func retiredSpendingLine(_ headline: RetirementAnswer, currency: CurrencyCode,
                                    locale: Locale = .current) -> AmountSentence? {
        guard let perYear = headline.sustainableSpending, perYear > 0 else { return nil }
        let about = StarterSetup.roundedToTwoFigures(perYear / 12)
        let amount = AmountFormat.amount(about, currency: currency, locale: locale)
        return "Spending up to \(amount: amount) a month lasts in \(GlanceText.futures(headline.confidence)) futures."
    }

    /// Under the fan: what its lines are, and what the answer is.
    static func fanLine(confidence: Double, hasStoppedWorking: Bool = false) -> String {
        let bands = "Each band shows how your money could develop across thousands of simulated futures."
        if hasStoppedWorking { return bands + " The answer is whether it lasts in \(GlanceText.futures(confidence))." }
        return bands + " The answer is the earliest age that works in \(GlanceText.futures(confidence))."
    }

    /// After the line: the answer stands on the rough amounts of first launch.
    static let sketch = "It's a first sketch from the numbers you gave; adding your accounts makes it exact."

    /// The lever: "Saving 340 € more a month would make it 2050." with the
    /// year the last Monday at work would move to, else "would make it 2
    /// years sooner".
    static func leverSentence(perMonth: Decimal, years: Int, lastMonday: CalendarDate?, currency: CurrencyCode,
                              locale: Locale = .current) -> AmountSentence {
        let amount = AmountFormat.amount(perMonth, currency: currency, locale: locale)
        if let lastMonday {
            return "Saving \(amount: amount) more a month would make it \(String(lastMonday.year - years))."
        }
        let sooner = years == 1 ? "a year sooner" : "\(years) years sooner"
        return "Saving \(amount: amount) more a month would make it \(sooner)."
    }
}
