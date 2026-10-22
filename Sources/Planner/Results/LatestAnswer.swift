import Foundation
import Model
import Tracker

/// A plan's latest answer to "can I retire yet?", picked by one rule that
/// the Overview, the Plan screens, Progress and the widgets all follow: the
/// plan's latest results, unless they're out of date with the library and
/// a check-in recorded a newer answer since the date they start from (on
/// the other device, say, while these were kept on this one); else the last
/// answer recorded at a check-in.
public struct LatestAnswer: Hashable, Sendable {
    /// The answer.
    public var answer: RetirementAnswer
    /// The results it comes from; `nil` for a recorded answer.
    public var results: PlanResults?
    /// The headline it was recorded as; `nil` for an answer from results.
    public var recorded: Headline?

    /// The latest answer from `results` (the plan's latest, if any) and the
    /// headlines `recorded` at check-ins, oldest first; `nil` without either.
    /// `upToDate` says whether `results` were calculated from the library
    /// as it is now (``latestResults(_:recorded:upToDate:)``).
    public init?(results: PlanResults?, recorded: [Headline], birthDate: CalendarDate?, upToDate: Bool) {
        if let latest = Self.latestResults(results, recorded: recorded, upToDate: upToDate) {
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
    public init?(plan: PlanID, library: Library, results: PlanResults?, upToDate: Bool) {
        self.init(results: results, recorded: library.headlines(for: plan),
                  birthDate: library.settings.person?.birthDate, upToDate: upToDate)
    }

    /// `results`, unless they're out of date with the library (`upToDate`
    /// is false: its check-ins, accounts or prices changed since they were
    /// calculated) and a check-in recorded an answer after the date they
    /// start from: then that answer is the latest, and the results aren't.
    ///
    /// Results up to date with the library saw every check-in it holds, so
    /// they're the latest whatever date they start from: a plan can start
    /// before its last recorded answer, from a date of its own, or from an
    /// earlier check-in once the one the answer was recorded at is gone
    /// (starting estimates replaced by imported values, a value deleted).
    public static func latestResults(_ results: PlanResults?, recorded: [Headline],
                                     upToDate: Bool) -> PlanResults? {
        guard let results else { return nil }
        if !upToDate, let last = recorded.last, last.date > results.start.date { return nil }
        return results
    }
}
