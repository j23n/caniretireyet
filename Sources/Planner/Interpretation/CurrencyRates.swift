import Foundation
import Model
import TaxKit
import Tracker

/// The exchange rates from a plan's currency to the currencies tax systems
/// compute in (``TaxKit/TaxSystem/currency``): units of the system's
/// currency per unit of the plan's, from the library's FX records on the
/// start date, held constant in real terms for the whole plan.
///
/// Without a rate on or before the start date it takes the latest one
/// recorded; without any, it uses 1, and warns either way.
struct CurrencyRates {
    let planCurrency: CurrencyCode
    let date: CalendarDate
    private let fx: FXTable
    private var rates: [String: Double] = [:]

    init(planCurrency: CurrencyCode, date: CalendarDate, library: Library) {
        self.planCurrency = planCurrency
        self.date = date
        fx = FXTable(library: library)
    }

    /// The rate for `system`: 1 when it computes in the plan's currency.
    mutating func rate(for system: any TaxSystem, issues: inout [PlanIssue]) -> Double {
        guard let code = system.currency?.uppercased(), code != planCurrency.rawValue.uppercased() else { return 1 }
        if let known = rates[code] { return known }
        let target = CurrencyCode(code)
        var rate = 1.0
        if let quote = fx.quote(from: planCurrency, to: target, on: date), quote.rate > 0 {
            rate = quote.rate.double
        } else if let quote = fx.quote(from: planCurrency, to: target, on: date.adding(years: 1000)), quote.rate > 0 {
            rate = quote.rate.double
            issues.append(.warning(
                "planner.exchangeRateAfterStart",
                "There is no \(planCurrency)–\(code) exchange rate on or before \(date); \(system.name) uses the one of "
                    + "\(quote.date?.description ?? "a later date").",
                section: .tax))
        } else {
            issues.append(.warning(
                "planner.noExchangeRate",
                "The library has no exchange rate between \(planCurrency) and \(code), which \(system.name) computes in; "
                    + "it converts at 1 to 1, so its taxes are off. Add an FX rate.",
                section: .tax))
        }
        rates[code] = rate
        return rate
    }
}
