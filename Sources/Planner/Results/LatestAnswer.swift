import Foundation
import Model
import Tracker

/// A plan's latest answer to "can I retire yet?", picked by one rule that
/// the Overview, the Plan screens, Progress and the widgets all follow: the
/// plan's latest results, unless a check-in recorded a newer answer than
/// they could have seen (on the other device, say, while these were kept
/// on this one); else the last answer recorded at a check-in.
public struct LatestAnswer: Hashable, Sendable {
    /// The answer.
    public var answer: RetirementAnswer
    /// The results it comes from; `nil` for a recorded answer.
    public var results: PlanResults?
    /// The headline it was recorded as; `nil` for an answer from results.
    public var recorded: Headline?

    /// The latest answer from `results` (the plan's latest, if any) and the
    /// headlines `recorded` at check-ins, oldest first; `nil` without either.
    /// `timeZone` gives the day the results were calculated on.
    public init?(results: PlanResults?, recorded: [Headline], birthDate: CalendarDate?,
                 timeZone: TimeZone = .current) {
        if let latest = Self.latestResults(results, recorded: recorded, timeZone: timeZone) {
            answer = latest.headline
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
    public init?(plan: PlanID, library: Library, results: PlanResults?) {
        self.init(results: results, recorded: library.headlines(for: plan),
                  birthDate: library.settings.person?.birthDate)
    }

    /// `results`, unless a check-in recorded an answer dated after both the
    /// date they start from and the day they were calculated (in
    /// `timeZone`): then that answer is the latest, and the results aren't.
    ///
    /// The start alone isn't enough: a plan can start before its last
    /// recorded answer, from a date of its own, or from an earlier check-in
    /// once the one the answer was recorded at is gone (starting estimates
    /// replaced by imported values, a value deleted). Results calculated
    /// since are still the latest.
    public static func latestResults(_ results: PlanResults?, recorded: [Headline],
                                     timeZone: TimeZone = .current) -> PlanResults? {
        guard let results else { return nil }
        if let last = recorded.last, last.date > results.start.date,
           last.date > CalendarDate(results.computedAt, in: timeZone) {
            return nil
        }
        return results
    }
}
