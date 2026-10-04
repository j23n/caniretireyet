import Foundation

/// The short diagnosis at the top of a ``PlanDebugReport``: the biggest
/// drags on the result, in plain words, computed from the report's own
/// figures (so an anonymized report's matches its rounded numbers). Facts
/// only, no advice.
public enum PlanDebugDiagnosis {
    /// The findings, roughly from the biggest drag down.
    public static func findings(for report: PlanDebugReport) -> [PlanDebugReport.Finding] {
        var findings: [PlanDebugReport.Finding] = []
        func add(_ code: String, _ text: String) {
            findings.append(PlanDebugReport.Finding(code: code, text: text))
        }
        let f = PlanDebugFormat.self
        let currency = report.header.currency
        let assumptions = report.assumptions
        let portfolio = assumptions.portfolio
        let age = report.header.retirementAge
        let confidence = f.percent(report.header.confidence, places: 0)

        // The mix: classes that pull the portfolio's median growth down by
        // their volatility, or that lose value in a typical year. (A steady
        // class with a low return, such as bonds, lowers the median too, but
        // narrows the spread of outcomes; it isn't named here.)
        let drags = assumptions.classes.compactMap { asset -> (PlanDebugReport.ClassAssumption, Double)? in
            guard asset.targetShare >= 0.02, let without = asset.portfolioMedianWithout,
                  without - portfolio.medianReturn >= 0.0025,
                  asset.volatility >= portfolio.volatility || asset.medianReturn < 0 else { return nil }
            return (asset, without)
        }.sorted { $0.1 > $1.1 }
        for (asset, without) in drags {
            let share = abs(asset.targetShare - asset.share) < 0.005
                ? "\(f.percent(asset.share, places: 0)) of plan assets"
                : "\(f.percent(asset.targetShare, places: 0)) of the mix the buckets are rebalanced to "
                    + "(\(f.percent(asset.share, places: 0)) of plan assets today)"
            add("mix.drag", "\(f.className(asset.assetClass)) is \(share); at \(f.percent(asset.expectedReturn)) expected "
                + "real return and \(f.percent(asset.volatility, places: 0)) volatility (a median of "
                + "\(f.percent(asset.medianReturn)) a year on its own), rebalancing into it each year lowers the "
                + "portfolio's median growth from \(f.percent(without)) to \(f.percent(portfolio.medianReturn)) a year.")
        }
        // Classes the target mix sells off.
        for asset in assumptions.classes where asset.share >= 0.05 && asset.targetShare < asset.share / 2 {
            add("mix.sold", "\(f.className(asset.assetClass)) is \(f.percent(asset.share, places: 0)) of plan assets "
                + "today, but \(f.percent(asset.targetShare, places: 0)) of the mix the buckets are rebalanced to: the "
                + "first year's rebalancing sells the difference"
                + (asset.assetClass == "cash" ? "." : ", and a taxable bucket pays tax on its gain."))
        }
        add("portfolio.growth", "The mix the buckets are rebalanced to every year averages "
            + "\(f.percent(portfolio.expectedReturn)) a year in real terms, but at "
            + "\(f.percent(portfolio.volatility, places: 0)) volatility its median (typical) growth is "
            + "\(f.percent(portfolio.medianReturn)) a year.")
        // A target mix that changes with age.
        if let target = report.plan.targetMix, target.steps.contains(where: \.applies) {
            func mix(_ shares: [String: Double]) -> String {
                shares.filter { $0.value > 0 }.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
                    .map { "\(f.className($0.key).lowercased()) \(f.percent($0.value, places: 0))" }
                    .joined(separator: ", ")
            }
            var parts = [target.mix.map { shares in
                "\(mix(shares))" + (target.growth.map { " (a median growth of \(f.percent($0.medianReturn)) a year)" } ?? "")
            } ?? "each ordinary account's own mix"]
            for step in target.steps where step.applies {
                let from = step.fromAge == "retirement" ? "from retirement at \(step.startAge.map(String.init) ?? "?")"
                    : "from \(step.fromAge)"
                parts.append("\(from), \(mix(step.mix)) (\(f.percent(step.growth.medianReturn)))")
            }
            add("mix.steps", "The target mix changes with age, retiring at \(age): \(parts.joined(separator: "; ")). "
                + "The year each one starts, rebalancing the ordinary accounts sells what it no longer wants, a "
                + "sale taxed on its gain; pension funds keep their own mix.")
        }

        // What the percentiles and paths start from.
        let scale = report.header.startScale
        let scaled = abs(scale - 1) > 1e-9
        let simulation = report.simulation
        if scaled {
            var why = ""
            if report.header.startScaleChoice == "assetsNeeded" {
                why = report.simulation.assetsNeeded?.outcome == "moreThanMaximum"
                    ? ", the most the search for the assets retiring today needs tries"
                    : ": the plan assets retiring today needs"
                if let extra = report.header.startExtra {
                    why += extra >= 0
                        ? " (today's with \(f.money(extra)) \(currency) more in the accounts that can be drawn now)"
                        : " (today's with \(f.money(-extra)) \(currency) less in the accounts that can be drawn now)"
                }
            } else if report.header.startScaleChoice == "factor" {
                why = ", every holding multiplied alike"
            }
            add("scale", "The percentiles, failures and traced runs below start from \(f.money(report.header.startAssets)) "
                + "\(currency), \(f.number((scale * 100).rounded() / 100)) times today's plan assets\(why). Retiring at "
                + "\(age) with it succeeds in \(f.percent(simulation.successAtStartScale)) of runs.")
        }

        // The deterministic run against the median one.
        let expected = report.simulation.expectedPath
        let median = report.simulation.medianPath
        var paths = expected.failed
            ? "Even with the median (typical) return every year (no ups and downs), the money runs out at "
                + "\(expected.failureAge.map(String.init) ?? "?") (\(expected.failureYear.map(String.init) ?? "?"))"
            : "With the median (typical) return every year (no ups and downs), the money lasts to \(report.header.endAge), with "
                + "\(f.money(expected.finalValue)) \(currency) left"
        paths += median.failed
            ? "; the median simulated run runs out at \(median.failureAge.map(String.init) ?? "?")."
            : "; the median simulated run ends with \(f.money(median.finalValue)) \(currency)."
        add("paths", paths)

        // What retiring today would need.
        let spending = report.plan.spending.retired
        if let needed = report.simulation.assetsNeeded {
            let today = "\(f.money(needed.planAssets)) \(currency)"
            switch needed.outcome {
            case "found":
                if let amount = needed.amount, amount > 0 {
                    let extra = needed.extra ?? (amount - needed.planAssets)
                    let how = extra >= 0
                        ? "today's \(today) plus \(f.money(extra)) added to the accounts that can be drawn now"
                        : "today's \(today) less \(f.money(-extra)) taken from the accounts that can be drawn now"
                    add("assets.needed", "Retiring today would need \(f.money(amount)) \(currency) in plan assets for "
                        + "\(confidence) of futures (\(how)), "
                        + "\(f.times(needed.scale ?? amount / max(1, needed.planAssets))) today's: the retirement "
                        + "spending of \(f.money(spending)) is \(f.percent(spending / amount)) of it.")
                }
            case "moreThanMaximum":
                add("assets.needed", "Even \(f.number(needed.maximumScale)) times today's plan assets "
                    + "(\(f.money(needed.maximumScale * needed.planAssets)) \(currency), the extra in the accounts that "
                    + "can be drawn now) don't make retiring today reach \(confidence): the extra money is invested in "
                    + "the target mix, whose median growth is \(f.percent(portfolio.medianReturn)) a year.")
            case "atMost":
                let lockedOnly = needed.extra.flatMap { extra in needed.accessible.map { extra <= -$0 * (1 - 1e-9) } }
                    ?? false
                add("assets.needed", "Retiring today reaches \(confidence) with at most \(f.money(needed.amount ?? 0)) "
                    + "\(currency) in plan assets, "
                    + (lockedOnly ? "what's locked away, with nothing in the accounts that can be drawn now; today "
                        + "there's \(today)." : "a twentieth of today's \(today)."))
            default:
                break
            }
        }

        // Pensions.
        let pensions = report.plan.pensions
        let claimed = pensions.compactMap { pension in pension.claimed.map { (pension, $0) } }
        if pensions.isEmpty {
            add("pension.none", "The plan has no pensions: the portfolio pays for all of retirement.")
        } else if claimed.isEmpty {
            add("pension.none", "Retiring at \(age), no pension is claimed before the plan ends.")
        } else {
            let first = claimed.min { $0.1.age < $1.1.age }!
            if first.1.age > age {
                add("pension.gap", "Retiring at \(age) means \(first.1.age - age) years before the first pension "
                    + "(\(first.0.name), at \(first.1.age)), paid for by the portfolio alone.")
            }
            let last = claimed.max { $0.1.age < $1.1.age }!.1.age
            let total = claimed.reduce(0) { $0 + $1.1.yearlyAmount }
            let factor = report.plan.spending.phases.last { $0.fromAge <= last }?.factor ?? 1
            let target = spending * factor
            if target > 0 {
                add("pension.coverage", "Once every pension has started (at \(last)), they pay \(f.money(total)) "
                    + "\(currency) a year before tax: \(f.percent(total / target, places: 0)) of the retirement spending "
                    + "of \(f.money(target)).")
            }
        }

        // The horizon.
        let retirementYear = max(report.schedule.retirementDate.year, report.person.firstYear)
        let years = report.person.lastYear - retirementYear + 1
        add("horizon", "The plan funds \(years) years of retirement, from \(age) (\(retirementYear)) to age "
            + "\(report.header.endAge) (\(report.person.lastYear)).")

        // Taxes in the median run.
        let medianPath = report.paths.first { $0.kind == "median" }
        let retiredYears = Set(report.schedule.years.filter { $0.workingShare == 0 }.map(\.year))
        if let gross = median.retiredGrossIncome, gross > 0, let taxes = median.retiredTaxes {
            var text = "In the median run, taxes and contributions take \(f.percent(taxes / gross, places: 0)) of gross "
                + "income in retirement (\(f.money(taxes)) of \(f.money(gross)) \(currency))"
            if let path = medianPath {
                // The largest lines over the years retired.
                var totals: [(label: String, amount: Double)] = []
                for year in path.years where retiredYears.contains(year.year) {
                    for line in year.taxes {
                        if let index = totals.firstIndex(where: { $0.label == line.label }) {
                            totals[index].amount += line.fixed + line.market
                        } else {
                            totals.append((line.label, line.fixed + line.market))
                        }
                    }
                }
                let largest = totals.filter { $0.amount > 0.005 * taxes }.sorted { $0.amount > $1.amount }.prefix(3)
                if !largest.isEmpty {
                    text += "; the largest: " + largest.map { "\($0.label) \(f.money($0.amount))" }.joined(separator: ", ")
                }
                let rebalancing = path.years.filter { retiredYears.contains($0.year) }
                    .reduce(0) { $0 + $1.withheldOnRebalancing }
                if rebalancing > 0.05 * taxes {
                    text += ". Rebalancing sales pay \(f.money(rebalancing)) of it"
                }
            }
            add("taxes", text + ".")
        }
        if let path = medianPath {
            // A year whose taxes on markets take a large bite of the plan assets.
            func share(_ year: PlanDebugReport.TracedYear) -> Double {
                year.startAssets > 0 ? year.taxes.reduce(0) { $0 + $1.market } / year.startAssets : 0
            }
            if let year = path.years.max(by: { share($0) < share($1) }) {
                let market = year.taxes.reduce(0) { $0 + $1.market }
                if share(year) > 0.03 {
                    var parts: [String] = []
                    if year.withheldOnRebalancing > 0.005 { parts.append("\(f.money(year.withheldOnRebalancing)) on rebalancing sales") }
                    if year.withheldOnWithdrawals > 0.005 { parts.append("\(f.money(year.withheldOnWithdrawals)) on withdrawals") }
                    if year.withheldOnPayouts > 0.005 { parts.append("\(f.money(year.withheldOnPayouts)) on required payouts") }
                    add("taxes.year", "In \(year.year), the median run pays \(f.money(market)) \(currency) of tax on sales, "
                        + "payouts and balances, \(f.percent(share(year), places: 0)) of the plan assets it started the "
                        + "year with"
                        + (parts.isEmpty ? "." : ": " + f.list(parts) + "."))
                }
            }
            // Sales of holdings whose purchase cost isn't known.
            var unknown: [String: Double] = [:]
            var firstYear: Int?
            for year in path.years {
                for sale in year.sales where sale.costBasis == nil && sale.proceeds > 0.005 {
                    unknown[sale.category, default: 0] += sale.proceeds
                    firstYear = firstYear ?? year.year
                }
            }
            if let firstYear {
                let total = unknown.values.reduce(0, +)
                add("basis.unknown", "The median run sells \(f.money(total)) \(currency) of holdings with no recorded "
                    + "purchase cost (\(f.list(unknown.keys.sorted())), from \(firstYear)); the tax system decides what "
                    + "such a sale's gain is, and may tax its whole value.")
            }
        }

        // Money that can't be drawn at the start of retirement.
        let planAssets = report.start.planAssets
        let locked = report.start.buckets.filter { !$0.liquid && $0.value > 0.5 }.compactMap { bucket -> String? in
            let share = planAssets > 0 ? " (\(f.percent(bucket.value / planAssets, places: 0)) of plan assets)" : ""
            if bucket.paidWhenJobEnds { return "\(bucket.name)\(share) is paid out when work stops" }
            guard let opens = bucket.accessibleFromAge else { return "\(bucket.name)\(share) can't be drawn in the plan" }
            return opens > age ? "\(bucket.name)\(share) can't be drawn until \(opens)" : nil
        }
        if !locked.isEmpty {
            add("locked", "Retiring at \(age): " + f.list(locked) + ".")
        }

        // Why runs fail.
        let failures = report.simulation.failures
        if failures.failed > 0 {
            var text = "\(f.percent(failures.failureRate, places: 0)) of runs fail when retiring at \(age)"
                + (scaled ? " with \(f.money(report.header.startAssets)) \(currency)" : "")
            if let median = failures.medianFailureAge { text += ", at a median age of \(median)" }
            text += failures.bridging == 0
                ? "; all of them run out of money entirely, with nothing locked away."
                : "; \(failures.bridging) of \(failures.failed) while money was still locked in a wrapper."
            add("failures", text)
        }

        // Flexible spending: what it saves, and what it costs in a bad case.
        if let rule = report.plan.flexibleSpending, let flexible = simulation.flexibleSpending {
            var text = "With flexible spending (cuts of \(f.percent(rule.cut, places: 0)) down to "
                + "\(f.percent(rule.floor, places: 0)) of the plan's \(f.money(flexible.planSpending)) a year)"
            if let needed = simulation.assetsNeeded, needed.outcome == "found", let amount = needed.amount,
               let without = flexible.assetsNeededWithoutRule ?? (flexible.assetsNeededWithoutRuleOutcome
                   == "moreThanMaximum" ? .infinity : nil) {
                text += ", retiring today needs \(f.money(amount)) \(currency) in plan assets instead of "
                    + (without.isFinite ? f.money(without)
                        : "more than \(f.number(needed.maximumScale)) times today's")
            }
            text += ". Retiring at \(age)" + (scaled ? " with \(f.money(report.header.startAssets)) \(currency)" : "")
            if let lowest = flexible.p10LowestLevel {
                text += ", in a bad case (1 in 10) spending drops to \(f.percent(lowest, places: 0)) of the plan's "
                    + "(\(f.money(lowest * flexible.planSpending)) a year), and 1 in 10 futures spend "
                    + "\(flexible.p90YearsBelow) or more of \(flexible.retirementYears) years below 100%"
            } else {
                text += ", in a bad case (1 in 10) the money runs out even at the floor"
            }
            add("flexible", text + "; \(f.percent(1 - flexible.shareWithCut, places: 0)) of futures never cut.")
        }

        // The sustainable spending.
        if let search = report.simulation.sustainableSpending {
            if let perYear = search.perYear {
                add("spending", "At \(search.age), the highest retirement spending that reaches \(confidence) is "
                    + "\(f.money(perYear)) \(currency) a year, against the plan's \(f.money(search.planSpending)).")
            } else {
                add("spending", "At \(search.age), no retirement spending reaches \(confidence).")
            }
        }

        // The debugger's own checks.
        if simulation.allRunsReproduced == false || report.paths.contains(where: { !$0.matchesMainRun }) {
            add("check", "Re-simulating didn't reproduce every outcome of the main run exactly; the traces may not "
                + "match the results. This is a bug worth reporting.")
        }
        if let searched = simulation.searchSuccessAtStartScale, abs(searched - simulation.successAtStartScale) > 1e-9 {
            add("check.monotone", "With the plan assets the runs start from, the search for the assets needed counted "
                + "\(f.percent(searched)) of runs succeeding, but simulating every run gives "
                + "\(f.percent(simulation.successAtStartScale)): the search takes a run that succeeds with less money to "
                + "succeed with more, which doesn't hold for every run here"
                + (report.plan.flexibleSpending == nil ? "." : " (with flexible spending, a run with more money can cut "
                    + "later and so spend more, which now and then ends below the floor)."))
        }
        return findings
    }
}
