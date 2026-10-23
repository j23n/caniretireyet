import Foundation
import Model
@testable import Planner
import Tracker

extension PlanResults {
    /// Made-up results of the example library's main plan, starting on
    /// `start`, without charts; `portfolio` and `years` when a test needs them,
    /// and the latest check-in the run saw.
    static func made(start: CalendarDate, value: Decimal = 100_000, currency: CurrencyCode = .eur,
                     answer: RetirementAnswer = RetirementAnswer(confidence: 0.9),
                     portfolio: [FanPoint] = [], years: [BaselineYear] = [],
                     computedAt: Date = Date(timeIntervalSince1970: 0),
                     latestCheckIn: CalendarDate? = nil) -> PlanResults {
        PlanResults(
            plan: "base", computedAt: computedAt, mode: .full, runs: 1, engine: "test",
            headline: answer, successByAge: [], portfolio: portfolio, markers: [], income: [], taxes: [],
            spending: [], start: BaselineStart(date: start, value: value), accounts: [], years: years,
            details: PlanResultDetails(
                planHash: "x", currentAge: 38, endAge: 95, sustainableSpendingAge: nil, issues: [],
                focus: PlanFocusDetails(age: 55, retirementDate: nil, success: nil, medianAtRetirement: nil,
                                        medianAtEnd: nil, lifetimeTaxes: 0, monthlySaving: nil, bridges: []),
                headline: Headline(date: start, engine: "test", planHash: "x")),
            currency: currency, latestCheckIn: latestCheckIn)
    }
}
