import Foundation
import Model

extension Planner {
    /// A stable hash of a plan's inputs: FNV-1a (64-bit) of its canonical
    /// JSON (sorted keys, decimals in their exact file form), as 16 hex digits.
    /// Headlines record it so charts can mark where the plan changed.
    public static func planHash(_ plan: PlanDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(plan)) ?? Data()
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}

extension PlanResult {
    /// The answer as a headline's summary: success rates to 3 decimals, FI
    /// progress to 2.
    public var headlineSummary: HeadlineSummary {
        HeadlineSummary(
            confidence: .rounded(settings.confidence, scale: 3), earliestAge: answer.earliestAge,
            successAtTarget: answer.successAtTarget.map { .rounded($0, scale: 3) },
            fiProgress: answer.fiProgress.map { .rounded($0, scale: 2) })
    }

    /// The headline to record for the check-in on `date` (default: the
    /// check-in the plan started from).
    public func headline(date: CalendarDate? = nil) -> Headline {
        let summary = headlineSummary
        return Headline(
            date: date ?? start.date, confidence: summary.confidence, earliestAge: summary.earliestAge,
            engine: engine, fiProgress: summary.fiProgress, planHash: planHash,
            successAtTarget: summary.successAtTarget,
            taxParameters: Dictionary(uniqueKeysWithValues: taxParameters.map { (TaxSystemID($0.key), $0.value) }))
    }

    /// A baseline of this result: the fan and the deterministic path at the
    /// focus age, in whole units of the plan's currency at the start date, with a copy of the plan.
    public func baseline(created: CalendarDate, kind: BaselineKind, label: String? = nil) -> Baseline {
        let savings = Dictionary(expectedPath.years.map { ($0.year, $0.savings) }, uniquingKeysWith: { first, _ in first })
        return Baseline(
            created: created, kind: kind, label: label, engine: engine, accounts: start.accounts,
            headline: headlineSummary, plan: (try? JSONValue(encoding: plan)) ?? .object([:]),
            start: BaselineStart(date: start.date, value: start.planAssets),
            taxParameters: Dictionary(uniqueKeysWithValues: taxParameters.map { (TaxSystemID($0.key), $0.value) }),
            years: fan.map { year in
                BaselineYear(
                    year: year.year, expected: .rounded(year.expected, scale: 0), p10: .rounded(year.p10, scale: 0),
                    p25: .rounded(year.p25, scale: 0), p50: .rounded(year.p50, scale: 0),
                    p75: .rounded(year.p75, scale: 0), p90: .rounded(year.p90, scale: 0),
                    savings: savings[year.year].flatMap { abs($0) >= 0.5 ? .rounded($0, scale: 0) : nil })
            })
    }
}
