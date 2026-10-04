import Foundation
import Model

/// A transformation of a report's values by what they are: money amounts,
/// identifiers and names of the person's things, and free text. The
/// builder rounds money to cents with it; ``PlanDebugReport/anonymized(_:)``
/// replaces names and IDs and rounds money.
///
/// Every report type maps each of its fields explicitly, so a field added
/// later is either mapped or visibly left alone.
struct DebugMapper {
    /// A money amount.
    var money: (Double) -> Double = { $0 }
    /// An account's ID, and its name.
    var accountID: (String) -> String = { $0 }
    var accountName: (_ id: String, _ name: String) -> String = { $1 }
    /// An instrument's ID, and its name.
    var instrumentID: (String) -> String = { $0 }
    var instrumentName: (_ id: String, _ name: String) -> String = { $1 }
    var planID: (String) -> String = { $0 }
    var planName: (String) -> String = { $0 }
    var pensionName: (String) -> String = { $0 }
    var eventName: (String) -> String = { $0 }
    /// Free text that may mention names: messages, notes and labels.
    var text: (String) -> String = { $0 }
    /// A message about one account: its name and ID always replaced.
    var accountText: (String, String) -> String = { text, _ in text }
    /// The birth date (`nil` removes it).
    var birthDate: (CalendarDate?) -> CalendarDate? = { $0 }

    /// Money rounded to cents, everything else as it is.
    static var cents: DebugMapper {
        DebugMapper(money: { value in
            guard value.isFinite else { return 0 }
            return (value * 100).rounded() / 100
        })
    }

    func money(_ value: Double?) -> Double? { value.map(money) }
    func money(_ values: [Double]) -> [Double] { values.map(money) }
}

protocol DebugMappable {
    func mapped(_ m: DebugMapper) -> Self
}

extension Array where Element: DebugMappable {
    func mapped(_ m: DebugMapper) -> [Element] { map { $0.mapped(m) } }
}

extension PlanDebugReport: DebugMappable {
    func mapped(_ m: DebugMapper) -> PlanDebugReport {
        var r = self
        r.header = header.mapped(m)
        r.diagnosis = diagnosis.map { PlanDebugReport.Finding(code: $0.code, text: m.text($0.text)) }
        r.person.birthDate = m.birthDate(person.birthDate)
        r.plan = plan.mapped(m)
        r.start = start.mapped(m)
        r.schedule.years = schedule.years.mapped(m)
        r.simulation = simulation.mapped(m)
        r.percentiles = percentiles.mapped(m)
        r.paths = paths.mapped(m)
        r.issues = issues.mapped(m)
        return r
    }
}

extension PlanDebugReport.Header: DebugMappable {
    func mapped(_ m: DebugMapper) -> Self {
        var h = self
        h.planID = m.planID(planID)
        h.planName = m.planName(planName)
        h.startAssets = m.money(startAssets)
        h.startExtra = m.money(startExtra)
        return h
    }
}

extension PlanDebugReport.PlanReading: DebugMappable {
    func mapped(_ m: DebugMapper) -> Self {
        var p = self
        p.work = work.map { work in
            var w = work
            w.gross = m.money(work.gross)
            w.costs = m.money(work.costs)
            w.net = m.money(work.net)
            return w
        }
        p.spending.working = m.money(spending.working)
        p.spending.retired = m.money(spending.retired)
        p.pensions = pensions.map { pension in
            var x = pension
            x.name = m.pensionName(pension.name)
            x.startingBalanceFromAccounts = m.money(pension.startingBalanceFromAccounts)
            x.claimed = pension.claimed.map { claim in
                var c = claim
                c.label = m.text(claim.label)
                c.yearlyAmount = m.money(claim.yearlyAmount)
                c.lumpSum = m.money(claim.lumpSum)
                return c
            }
            x.offered = pension.offered.map { option in
                var o = option
                o.label = m.text(option.label)
                o.annualAmount = m.money(option.annualAmount)
                o.fullYearAmount = m.money(option.fullYearAmount)
                o.changes = option.changes.map { PlanDebugReport.AgeAmount(age: $0.age, amount: m.money($0.amount)) }
                o.lumpSum = m.money(option.lumpSum)
                o.note = option.note.map(m.text)
                return o
            }
            return x
        }
        p.contributions = contributions.map { contribution in
            var c = contribution
            c.account = contribution.account.map(m.accountID)
            c.perYear = m.money(contribution.perYear)
            c.amount = m.money(contribution.amount)
            return c
        }
        p.events = events.map { event in
            var e = event
            e.name = m.eventName(event.name)
            e.amount = m.money(event.amount)
            return e
        }
        p.withdrawals.cashBuffer = m.money(withdrawals.cashBuffer)
        return p
    }
}

extension PlanDebugReport.StartingPortfolio: DebugMappable {
    func mapped(_ m: DebugMapper) -> Self {
        var s = self
        s.planAssets = m.money(planAssets)
        s.accounts = accounts.map { account in
            var a = account
            a.id = m.accountID(account.id)
            a.name = m.accountName(account.id, account.name)
            a.reason = account.reason.map { m.accountText($0, account.id) }
            a.value = m.money(account.value)
            a.costBasis = m.money(account.costBasis)
            a.holdings = account.holdings.map { holding in
                var h = holding
                h.instrument = holding.instrument.map(m.instrumentID)
                h.value = m.money(holding.value)
                h.costBasis = m.money(holding.costBasis)
                return h
            }
            return a
        }
        s.instruments = instruments.map { instrument in
            var i = instrument
            i.id = m.instrumentID(instrument.id)
            i.name = m.instrumentName(instrument.id, instrument.name)
            return i
        }
        s.buckets = buckets.map { bucket in
            var b = bucket
            b.value = m.money(bucket.value)
            b.costBasis = m.money(bucket.costBasis)
            b.accounts = bucket.accounts.map(m.accountID)
            b.lockedReason = bucket.lockedReason.map(m.text)
            return b
        }
        s.schemeSeeds = schemeSeeds.map { seed in
            var x = seed
            x.accounts = seed.accounts.map(m.accountID)
            x.value = m.money(seed.value)
            return x
        }
        s.debtPaidOff = m.money(debtPaidOff)
        return s
    }
}

extension PlanDebugReport.Amount {
    /// An income item, credit or tax line: `name` maps its ID and label
    /// (e.g. a pension's or an event's name), money its amount.
    func mapped(_ m: DebugMapper, name: (String) -> String) -> Self {
        PlanDebugReport.Amount(id: name(id), label: name(label), amount: m.money(amount))
    }
}

extension PlanDebugReport.ScheduleYear: DebugMappable {
    func mapped(_ m: DebugMapper) -> Self {
        var y = self
        y.work = m.money(work)
        y.pensions = pensions.map { $0.mapped(m) { name in m.text(m.pensionName(name)) } }
        y.windfalls = windfalls.map { $0.mapped(m, name: m.eventName) }
        y.expenses = m.money(expenses)
        y.contributions = m.money(contributions)
        y.credits = credits.map { $0.mapped(m) { $0 } }
        y.spending = m.money(spending)
        y.taxes = taxes.map { $0.mapped(m, name: m.text) }
        y.socialContributions = socialContributions.map { $0.mapped(m, name: m.text) }
        y.netIncome = m.money(netIncome)
        y.toDraw = m.money(toDraw)
        y.requiredPayouts = requiredPayouts.map(m.text)
        return y
    }
}

extension PlanDebugReport.Simulation: DebugMappable {
    func mapped(_ m: DebugMapper) -> Self {
        var s = self
        s.sustainableSpending = sustainableSpending.map { search in
            var x = search
            x.perYear = m.money(search.perYear)
            x.planSpending = m.money(search.planSpending)
            x.steps = search.steps.map { PlanDebugReport.SpendingStep(spending: m.money($0.spending), success: $0.success) }
            return x
        }
        s.assetsNeeded = assetsNeeded.map { search in
            var x = search
            x.amount = m.money(search.amount)
            x.planAssets = m.money(search.planAssets)
            x.extra = m.money(search.extra)
            x.accessible = m.money(search.accessible)
            x.steps = search.steps.map {
                PlanDebugReport.ScaleStep(scale: $0.scale, amount: m.money($0.amount), success: $0.success,
                                          extra: m.money($0.extra))
            }
            return x
        }
        s.failures.bridges = failures.bridges.map { bridge in
            var b = bridge
            b.name = m.text(bridge.name)
            return b
        }
        s.expectedPath = expectedPath.mapped(m)
        s.medianPath = medianPath.mapped(m)
        return s
    }
}

extension PlanDebugReport.PathOutcome: DebugMappable {
    func mapped(_ m: DebugMapper) -> Self {
        var o = self
        o.finalValue = m.money(finalValue)
        o.retiredGrossIncome = m.money(retiredGrossIncome)
        o.retiredTaxes = m.money(retiredTaxes)
        o.retiredMarketTaxes = m.money(retiredMarketTaxes)
        o.retiredWithdrawals = m.money(retiredWithdrawals)
        return o
    }
}

extension PlanDebugReport.Percentiles {
    func mapped(_ m: DebugMapper) -> Self {
        PlanDebugReport.Percentiles(p10: m.money(p10), p25: m.money(p25), p50: m.money(p50), p75: m.money(p75),
                                    p90: m.money(p90))
    }
}

extension PlanDebugReport.PercentileYear: DebugMappable {
    func mapped(_ m: DebugMapper) -> Self {
        var y = self
        y.value = value.mapped(m)
        y.expected = m.money(expected)
        y.withdrawals = withdrawals.mapped(m)
        y.taxes = taxes.mapped(m)
        return y
    }
}

extension PlanDebugReport.TracedPath: DebugMappable {
    func mapped(_ m: DebugMapper) -> Self {
        var p = self
        p.failureReason = failureReason.map(m.text)
        p.finalValue = m.money(finalValue)
        p.years = years.mapped(m)
        return p
    }
}

extension PlanDebugReport.TracedYear: DebugMappable {
    func mapped(_ m: DebugMapper) -> Self {
        var y = self
        y.startAssets = m.money(startAssets)
        y.endAssets = m.money(endAssets)
        y.netIncome = m.money(netIncome)
        y.payoutsNet = m.money(payoutsNet)
        y.contributions = m.money(contributions)
        y.spending = m.money(spending)
        y.expenses = m.money(expenses)
        y.lastYearsTaxes = m.money(lastYearsTaxes)
        y.cashFlow = m.money(cashFlow)
        y.shortfall = m.money(shortfall)
        y.spendingTarget = m.money(spendingTarget)
        y.spendingMet = m.money(spendingMet)
        y.buckets = buckets.map { bucket in
            PlanDebugReport.TracedBucket(
                start: m.money(bucket.start), moneyIn: m.money(bucket.moneyIn),
                requiredPayouts: m.money(bucket.requiredPayouts), withdrawn: m.money(bucket.withdrawn),
                rebalancingTax: m.money(bucket.rebalancingTax), rebalancing: m.money(bucket.rebalancing),
                growth: m.money(bucket.growth), end: m.money(bucket.end), endCostBasis: m.money(bucket.endCostBasis),
                endClasses: m.money(bucket.endClasses))
        }
        y.sales = sales.map { sale in
            var s = sale
            s.proceeds = m.money(sale.proceeds)
            s.costBasis = m.money(sale.costBasis)
            s.gain = m.money(sale.gain)
            return s
        }
        y.payouts = payouts.map { payout in
            var p = payout
            p.amount = m.money(payout.amount)
            p.costBasis = m.money(payout.costBasis)
            return p
        }
        y.withheldOnPayouts = m.money(withheldOnPayouts)
        y.withheldOnWithdrawals = m.money(withheldOnWithdrawals)
        y.withheldOnRebalancing = m.money(withheldOnRebalancing)
        y.taxes = taxes.map { line in
            var l = line
            l.label = m.text(line.label)
            l.fixed = m.money(line.fixed)
            l.market = m.money(line.market)
            return l
        }
        y.carriedToNextYear = m.money(carriedToNextYear)
        y.carriedForward = carriedForward?.map { carried in
            var c = carried
            c.label = m.text(carried.label)
            c.amount = m.money(carried.amount)
            return c
        }
        return y
    }
}

extension PlanDebugReport.Issue: DebugMappable {
    func mapped(_ m: DebugMapper) -> Self {
        var i = self
        i.message = account.map { m.accountText(message, $0) } ?? m.text(message)
        i.account = account.map(m.accountID)
        return i
    }
}
