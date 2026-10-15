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

    /// "You're 34." under the birth date; `nil` without one.
    static func ageLine(birthDate: CalendarDate?, today: CalendarDate = .today()) -> String? {
        guard let birthDate, birthDate <= today else { return nil }
        return "You're \(birthDate.wholeYears(to: today))."
    }

    // MARK: Money

    /// Under pay and spending, as you type: "So you save about 1.400 € a
    /// month, a third of your pay.", "So you spend all you take home.", or
    /// "You spend about 300 € a month more than you take home."; `nil`
    /// without both.
    static func savingLine(_ answers: StarterAnswers, currency: CurrencyCode,
                           locale: Locale = .current) -> AmountSentence? {
        guard let saving = answers.saving else { return nil }
        let about = StarterSetup.roundedToTwoFigures(abs(saving.perMonth))
        let amount = AmountFormat.amount(about, currency: currency, locale: locale)
        if about == 0 { return "So you spend all you take home." }
        if saving.perMonth < 0 { return "You spend about \(amount: amount) a month more than you take home." }
        return "So you save about \(amount: amount) a month, \(share(saving.share, locale: locale)) of your pay."
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

    // MARK: Later in life

    /// Under the state pension: where its amount comes from, and what
    /// leaving it empty does.
    static func statePensionNote(country: CountryCode?) -> String {
        "\(CountryDefaults.statePensionSource(for: country).capitalizedFirst) has this. Leave it empty to plan "
            + "without it, which is more cautious."
    }

    /// Under the tax rate: prefilled for the country, or what leaving it
    /// empty does.
    static func taxNote(country: CountryCode?, isDefault: Bool, locale: Locale = .current) -> String {
        if isDefault, let country {
            return "Prefilled for \(CountryChoices.name(of: country, locale: locale)). Change it any time in the plan."
        }
        return "Leave it empty to plan without tax on investments; the plan says so. Change it any time."
    }

    // MARK: The answer

    /// The answer's first words: "Not yet." or "Yes."
    static func revealTitle(_ headline: RetirementAnswer) -> String {
        headline.canRetireNow ? "Yes." : "Not yet."
    }

    /// The answer in a sentence: "You could retire at 58, in about 24
    /// years.", "You could retire today, in at least 9 of 10 futures.", or
    /// "No age up to 85 works in 9 of 10 futures yet."
    static func revealLine(_ headline: RetirementAnswer, today: CalendarDate) -> String {
        let futures = GlanceText.futures(headline.confidence)
        if headline.canRetireNow { return "You could retire today, in at least \(futures) futures." }
        guard let age = headline.earliestAge else { return "No age works in \(futures) futures yet." }
        guard let date = headline.earliestDate, let countdown = RetirementCountdown(from: today, to: date) else {
            return "You could retire at \(age)."
        }
        return "You could retire at \(age), \(lowercasedFirst(countdown.spokenHeadlineText))."
    }

    /// Under the ring: how ready, and how sure. "You have 13% of what
    /// retiring today would need. At 58, your money lasts to 95 in 9 of
    /// 10 futures."
    static func readinessLine(_ headline: RetirementAnswer, endAge: Int, locale: Locale = .current) -> String {
        var sentences: [String] = []
        if let readiness = PlanResultsText.readiness(headline, locale: locale) {
            sentences.append("You have \(readiness).")
        }
        let futures = GlanceText.futures(headline.confidence)
        if let age = headline.earliestAge, !headline.canRetireNow {
            sentences.append("At \(age), your money lasts to \(endAge) in \(futures) futures.")
        }
        return sentences.joined(separator: " ")
    }

    /// Under the fan: what its lines are, and what the answer is.
    static func fanLine(confidence: Double) -> String {
        "Each band holds possible futures of your money, played out thousands of times. The answer is the "
            + "earliest age that works in \(GlanceText.futures(confidence))."
    }

    /// The lever: "Save 340 € more a month" over "about 2 years sooner".
    static func lever(perMonth: Decimal, years: Int, currency: CurrencyCode,
                      locale: Locale = .current) -> (action: AmountSentence, effect: String) {
        let amount = AmountFormat.amount(perMonth, currency: currency, locale: locale)
        let effect = years == 1 ? "about a year sooner" : "about \(years) years sooner"
        return ("Save \(amount: amount) more a month", effect)
    }

    private static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
