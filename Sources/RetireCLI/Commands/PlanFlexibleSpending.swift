import Foundation
import Model
import Planner

/// Flexible spending in the CLI's words (PLANNER.md, "Flexible spending"):
/// the rule for `retire plan show`, and what it did for `retire plan`.
enum PlanFlexibleSpending {
    // MARK: Describing

    /// "on: cuts of 10% of the plan's spending, never below 80% (28,800 EUR
    /// a year); guardrails 20% above and 20% below the first retirement
    /// year's withdrawal rate", or "off".
    static func describe(_ spending: PlanSpending, currency: CurrencyCode) -> String {
        guard let rule = spending.flexible else { return "off (spending is fixed in real terms)" }
        let floor = Format.amount(rule.effectiveFloor * spending.retired, places: 0)
        let settings = "cuts of \(Format.percent(rule.effectiveCut, places: 0)) of the plan's spending, never below "
            + "\(Format.percent(rule.effectiveFloor, places: 0)) (\(floor) \(currency) a year); guardrails "
            + "\(Format.percent(rule.effectiveUpperGuardrail, places: 0)) above and "
            + "\(Format.percent(rule.effectiveLowerGuardrail, places: 0)) below the first retirement year's withdrawal "
            + "rate"
        return rule.isEnabled ? "on: " + settings : "off (kept: \(settings))"
    }

    /// The rule in `retire plan show --json`.
    struct JSON: Encodable {
        var enabled: Bool
        var cut: String
        var floor: String
        var upperGuardrail: String
        var lowerGuardrail: String

        init?(_ spending: PlanSpending) {
            guard let rule = spending.flexible else { return nil }
            enabled = rule.isEnabled
            cut = rule.effectiveCut.fileString
            floor = rule.effectiveFloor.fileString
            upperGuardrail = rule.effectiveUpperGuardrail.fileString
            lowerGuardrail = rule.effectiveLowerGuardrail.fileString
        }
    }

    // MARK: What it did (`retire plan`)

    /// What flexible spending did at the focus age, for `retire plan`.
    struct Report {
        var summary: FlexibleSpendingSummary
        /// The spending paid each year, across runs.
        var years: [(year: Int, age: Int, spending: SpendingPercentiles)]

        init(_ summary: FlexibleSpendingSummary, fan: [FanYear]) {
            self.summary = summary
            years = fan.compactMap { year in year.spending.map { (year.year, year.age, $0) } }
        }

        /// "Flexible spending, retiring at 55 (cuts of 10% down to 80% of 36,000 EUR): …", the sentences, and
        /// the spending paid every 5 years of retirement.
        func lines(currency: CurrencyCode, startYear: Int) -> [String] {
            let s = summary
            let plan = PlanReport.whole(s.planSpending)
            var lines = ["Flexible spending, retiring at \(s.age) (cuts of \(PlanReport.percent(s.cut)) down to "
                + "\(PlanReport.percent(s.floor)) of \(plan) \(currency) a year)"]
            lines.append("  " + Self.badCase(s, currency: currency))
            var length = "  The median future spends \(s.medianYearsBelow) of \(s.retirementYears) retirement years below "
                + "100%, a bad case (1 in 10) \(s.p90YearsBelow) or more"
            if let median = s.medianLowestSpending, median < s.planSpending - 0.5 {
                length += "; in the median future spending goes as low as \(PlanReport.whole(median)) \(currency) a year"
            }
            lines.append(length + ".")
            let shown = years.filter { $0.age % 5 == 0 || $0.age == s.age }.filter { $0.age >= s.age }
            if !shown.isEmpty {
                var table = TextTable([.right("Age"), .right("Year"), .right("p10"), .right("Median"), .right("p90")])
                for row in shown {
                    table.add(["\(row.age)", "\(row.year)", PlanReport.whole(row.spending.p10),
                               PlanReport.whole(row.spending.p50), PlanReport.whole(row.spending.p90)])
                }
                lines.append("  Spending paid (\(currency), today's money; a run that has failed pays 0"
                    + (shown.first?.year == startYear ? "; the first year is the part after the check-in" : "")
                    + ")")
                lines += table.lines().map { "  " + $0 }
            }
            return lines
        }

        /// "In a bad case (1 in 10) you'd spend as little as 28,800 EUR a
        /// year for a while; 54% of futures never cut." The money runs out
        /// in a bad case when the 10th-percentile run fails.
        static func badCase(_ s: FlexibleSpendingSummary, currency: CurrencyCode) -> String {
            let tail = neverCut(1 - s.shareWithCut)
            guard let lowest = s.p10LowestSpending else {
                return "In a bad case (1 in 10) the money runs out even at the floor; \(tail)."
            }
            if lowest >= s.planSpending - 0.5 {
                return "Even in a bad case (1 in 10) spending is never cut; \(tail)."
            }
            return "In a bad case (1 in 10) you'd spend as little as \(PlanReport.whole(lowest)) \(currency) a year "
                + "for a while; \(tail)."
        }

        /// "half of all futures never cut", "72% of futures never cut".
        static func neverCut(_ share: Double) -> String {
            if share >= 0.995 { return "no future cuts spending" }
            if share < 0.005 { return "every future cuts spending at some point" }
            if abs(share - 0.5) < 0.05 { return "half of all futures never cut" }
            return "\(PlanReport.percent(share)) of futures never cut"
        }

        var json: JSONReport {
            let s = summary
            return JSONReport(
                age: s.age, cut: s.cut, floor: s.floor, upperGuardrail: s.upperGuardrail,
                lowerGuardrail: s.lowerGuardrail, planSpending: PlanReport.rounded(s.planSpending),
                shareWithCut: s.shareWithCut, failureRate: s.failureRate, medianLowestLevel: s.medianLowestLevel,
                p10LowestLevel: s.p10LowestLevel, medianLowestSpending: s.medianLowestSpending.map(PlanReport.rounded),
                p10LowestSpending: s.p10LowestSpending.map(PlanReport.rounded), medianShareBelow: s.medianShareBelow,
                medianYearsBelow: s.medianYearsBelow, p90YearsBelow: s.p90YearsBelow,
                retirementYears: s.retirementYears,
                spending: years.map {
                    JSONReport.Year(year: $0.year, age: $0.age, p10: PlanReport.rounded($0.spending.p10),
                                    p50: PlanReport.rounded($0.spending.p50), p90: PlanReport.rounded($0.spending.p90))
                })
        }
    }

    /// What flexible spending did, in `retire plan --json`; whole amounts as strings.
    struct JSONReport: Encodable {
        struct Year: Encodable {
            var year: Int
            var age: Int
            var p10: String
            var p50: String
            var p90: String
        }

        var age: Int
        var cut: Double
        var floor: Double
        var upperGuardrail: Double
        var lowerGuardrail: Double
        var planSpending: String
        var shareWithCut: Double
        var failureRate: Double
        /// `nil` when that run fails.
        var medianLowestLevel: Double?
        var p10LowestLevel: Double?
        var medianLowestSpending: String?
        var p10LowestSpending: String?
        var medianShareBelow: Double
        var medianYearsBelow: Int
        var p90YearsBelow: Int
        var retirementYears: Int
        /// The spending paid each year: percentiles across runs.
        var spending: [Year]
    }
}
