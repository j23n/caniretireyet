import Foundation
import Model

extension Planner {
    /// A stable hash of a plan's inputs: FNV-1a (64-bit) of its canonical
    /// JSON (sorted keys, decimals in their exact file form), as 16 hex digits.
    /// Headlines record it so charts can mark where the plan changed.
    public static func planHash(_ plan: PlanDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return FNV1a.hexHash((try? encoder.encode(plan)) ?? Data())
    }

    /// A readiness (1 is 100%) as headlines record it: rounded down to whole
    /// percent, allowing for the binary representation (0.58 stays 0.58), so
    /// a recorded 1 means retiring today reaches the confidence level.
    public static func recordedReadiness(_ readiness: Double) -> Decimal {
        .roundedDown(readiness, scale: 2)
    }
}

extension PlanResult {
    /// The answer as a headline's summary: success rates to 3 decimals,
    /// readiness as headlines record it (``Planner/recordedReadiness(_:)``).
    public var headlineSummary: HeadlineSummary {
        HeadlineSummary(
            confidence: .rounded(answer.confidence, scale: 3), earliestAge: answer.earliestAge,
            successAtTarget: answer.successAtTarget.map { .rounded($0, scale: 3) },
            readiness: answer.readiness.map(Planner.recordedReadiness))
    }

    /// The headline to record for the check-in on `date` (default: the
    /// check-in the plan started from).
    public func headline(date: CalendarDate? = nil) -> Headline {
        let summary = headlineSummary
        return Headline(
            date: date ?? start.date, coastAge: answer.agesWithout.coast?.earliestAge,
            confidence: summary.confidence, earliestAge: summary.earliestAge, engine: engine,
            paceAge: answer.agesWithout.pace?.earliestAge, planHash: planHash,
            readiness: summary.readiness, successAtTarget: summary.successAtTarget)
    }

    /// A baseline of this result: the fan and the deterministic path at the
    /// focus age, in whole units of the base currency at the start date, with a copy of the plan.
    public func baseline(created: CalendarDate, kind: BaselineKind, label: String? = nil) -> Baseline {
        let savings = Dictionary(expectedPath.years.map { ($0.year, $0.savings) }, uniquingKeysWith: { first, _ in first })
        return Baseline(
            created: created, kind: kind, label: label, engine: engine, accounts: start.accounts,
            headline: headlineSummary, plan: (try? JSONValue(encoding: plan)) ?? .object([:]),
            start: BaselineStart(date: start.date, value: start.planAssets),
            years: fan.map { year in
                BaselineYear(
                    year: year.year, expected: .rounded(year.expected, scale: 0), p10: .rounded(year.p10, scale: 0),
                    p25: .rounded(year.p25, scale: 0), p50: .rounded(year.p50, scale: 0),
                    p75: .rounded(year.p75, scale: 0), p90: .rounded(year.p90, scale: 0),
                    savings: savings[year.year].flatMap { abs($0) >= 0.5 ? .rounded($0, scale: 0) : nil })
            })
    }
}
