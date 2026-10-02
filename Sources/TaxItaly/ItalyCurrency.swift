import TaxKit

/// Italy computes in euros (`ItalyTaxSystem.currency`). Amounts arrive in the
/// plan's currency, with the rate in `FixedYear.currencyRate` (euros per unit
/// of the plan's currency): the calculator converts them on the way in and
/// every line, contribution and accrual back on the way out. For a plan in
/// euros the rate is 1 and nothing is converted, so the results are the
/// same to the last bit.
extension FixedYear {
    /// The rate to convert with: `currencyRate`, or 1 when it isn't positive.
    var euroRate: Double {
        currencyRate > 0 ? currencyRate : 1
    }

    /// This year with its amounts in euros: work, pensions (and the tax
    /// charged on them abroad), contributions, windfalls and the
    /// `otherTaxCredits` option. `currencyRate` stays, to convert the
    /// results back.
    func inEuros() -> FixedYear {
        let rate = euroRate
        guard rate != 1 else { return self }
        var year = self
        year.work = work.map { income in
            var income = income
            income.gross *= rate
            income.costs *= rate
            income.net = income.net.map { $0 * rate }
            return income
        }
        year.pensions = pensions.map { pension in
            var pension = pension
            pension.amount *= rate
            pension.sourceTax = pension.sourceTax.map { $0 * rate }
            return pension
        }
        year.wrapperContributions = wrapperContributions.map { contribution in
            var contribution = contribution
            contribution.amount *= rate
            return contribution
        }
        year.windfalls = windfalls.map { windfall in
            var windfall = windfall
            windfall.amount *= rate
            return windfall
        }
        if let credits = systemOptions.double("otherTaxCredits") {
            year.systemOptions["otherTaxCredits"] = .number(credits * rate)
        }
        return year
    }
}

extension TaxLine {
    /// The line with its amount and base divided by `rate` (euros back to
    /// the plan's currency); itself when the rate is 1.
    func fromEuros(_ rate: Double) -> TaxLine {
        guard rate != 1 else { return self }
        var line = self
        line.amount /= rate
        line.base = base.map { $0 / rate }
        return line
    }
}

extension Accrual {
    /// The accrual with its amount divided by `rate`; itself when the rate is 1.
    func fromEuros(_ rate: Double) -> Accrual {
        guard rate != 1 else { return self }
        var accrual = self
        accrual.amount /= rate
        return accrual
    }
}
