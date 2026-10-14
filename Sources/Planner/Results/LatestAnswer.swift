import Foundation
import Model
import Tracker

/// A plan's latest answer to "can I retire yet?", picked by one rule that
/// the Overview, the Plan screens, Progress and the widgets all follow: the
/// plan's latest results, unless a check-in recorded a newer answer since
/// the date they start from (on the other device, say, while these were
/// kept on this one); else the last answer recorded at a check-in.
public struct LatestAnswer: Hashable, Sendable {
    /// The answer, with its amounts in the library's base currency
    /// (``PlanResults/answer(in:valuator:)``).
    public var answer: RetirementAnswer
    /// The results it comes from; `nil` for a recorded answer.
    public var results: PlanResults?
    /// The headline it was recorded as; `nil` for an answer from results.
    public var recorded: Headline?

    /// The latest answer from `results` (the plan's latest, if any) and the
    /// headlines `recorded` at check-ins, oldest first; `nil` without either.
    public init?(results: PlanResults?, recorded: [Headline], birthDate: CalendarDate?, valuator: Valuator) {
        if let latest = Self.latestResults(results, recorded: recorded) {
            answer = latest.answer(in: valuator.baseCurrency, valuator: valuator)
            self.results = latest
            self.recorded = nil
        } else if let last = recorded.last {
            answer = RetirementAnswer(recorded: last, birthDate: birthDate)
            self.results = nil
            self.recorded = last
        } else {
            return nil
        }
    }

    /// The latest answer of `plan` in `library`, with its latest `results`.
    public init?(plan: PlanID, library: Library, valuator: Valuator, results: PlanResults?) {
        self.init(results: results, recorded: library.headlines(for: plan),
                  birthDate: library.settings.person?.birthDate, valuator: valuator)
    }

    /// `results`, unless a check-in recorded an answer after the date they
    /// start from: then that answer is the latest, and the results aren't.
    public static func latestResults(_ results: PlanResults?, recorded: [Headline]) -> PlanResults? {
        guard let results else { return nil }
        if let last = recorded.last, last.date > results.start.date { return nil }
        return results
    }
}
