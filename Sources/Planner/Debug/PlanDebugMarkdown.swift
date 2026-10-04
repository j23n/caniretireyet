import Foundation
import Model

extension PlanDebugReport {
    /// The report as Markdown, for reading or sharing: each section starts
    /// with a short explanation of what it shows and how to read it, and
    /// long yearly tables show the first ten years, the years around
    /// retirement, pension starts and failures, then every fifth age. The
    /// JSON (``json()``) holds every year and every detail.
    public func markdown() -> String {
        var writer = PlanDebugMarkdown(report: self)
        writer.write()
        return writer.lines.joined(separator: "\n") + "\n"
    }
}

/// Writes a ``PlanDebugReport`` as Markdown.
struct PlanDebugMarkdown {
    let report: PlanDebugReport
    private(set) var lines: [String] = []
    private typealias F = PlanDebugFormat

    init(report: PlanDebugReport) {
        self.report = report
    }

    private var currency: String { report.header.currency }
    private var age: Int { report.header.retirementAge }

    private mutating func line(_ text: String = "") { lines.append(text) }

    private mutating func paragraph(_ text: String) {
        line(text)
        line()
    }

    private mutating func table(_ table: MarkdownTable) {
        lines += table.lines
        line()
    }

    private static func json(_ options: [String: JSONValue]) -> String {
        guard !options.isEmpty else { return "" }
        return options.keys.sorted().map { "\($0): \(text(options[$0]!))" }.joined(separator: ", ")
    }

    private static func text(_ value: JSONValue) -> String {
        switch value {
        case .null: "null"
        case .bool(let value): String(value)
        case .number(let value): value.description
        case .string(let value): value
        case .array(let values): "[" + values.map(text).joined(separator: ", ") + "]"
        case .object(let object): "{" + json(object) + "}"
        }
    }

    private static func mix(_ shares: [String: Double]) -> String {
        shares.filter { $0.value > 0 }.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .map { "\($0.key) \(F.percent($0.value, places: 0))" }.joined(separator: ", ")
    }

    mutating func write() {
        writeHeader()
        writeDiagnosis()
        writeRun()
        writePlan()
        writeAssumptions()
        writeStart()
        writeSchedule()
        writeSimulation()
        writePercentiles()
        writePaths()
        writeIssues()
    }

    // MARK: Header and diagnosis

    private mutating func writeHeader() {
        let header = report.header
        line("# Plan debugger: \(header.planName)")
        line()
        let why = switch header.retirementAgeChoice {
        case "today": "today's age, the \"retire today\" scenario"
        case "target": "the plan's target age"
        default: "the age asked for"
        }
        paragraph("Every calculation behind the plan's answer, with the details for retiring at \(age) (\(why)). "
            + "Amounts are yearly, in today's money (real terms), in \(currency); returns are real, after inflation. "
            + "The JSON version of this report holds every year and every detail; the tables here skip some years "
            + "of long plans.")
        if isScaled {
            line("> **Scaled.** The percentiles, failures and traced runs (sections 6 and 7, and the failures in 5) "
                + "start from \(startText). The rest of the report is about today's plan assets.")
            line()
        }
        if let anonymization = header.anonymization {
            line("> **Anonymized.** " + anonymization.notes.joined(separator: " "))
            line()
        }
    }

    private var isScaled: Bool { abs(report.header.startScale - 1) > 1e-9 }

    /// "2,057,069 EUR, 13.8 times today's plan assets (what retiring today needs)".
    private var startText: String {
        let header = report.header
        guard isScaled else { return "today's plan assets, \(F.money(header.startAssets)) \(currency)" }
        let why = switch header.startScaleChoice {
        case "assetsNeeded": report.simulation.assetsNeeded?.outcome == "moreThanMaximum"
            ? " (the most the search for the assets retiring today needs tries; it still falls short)"
            : " (what retiring today needs)"
        default: ""
        }
        return "\(F.money(header.startAssets)) \(currency), \(F.number((header.startScale * 100).rounded() / 100)) "
            + "times today's plan assets\(why)"
    }

    private mutating func writeDiagnosis() {
        line("## Diagnosis")
        line()
        paragraph("What weighs most on the result, worked out from the figures in the sections below. These are "
            + "facts about the plan as entered, not advice.")
        for finding in report.diagnosis { line("- \(finding.text)") }
        line()
    }

    private mutating func writeRun() {
        let header = report.header
        line("## 1. What was run")
        line()
        paragraph("The engine, the plan and the simulation settings behind every number in this report.")
        var table = MarkdownTable(["Setting", "Value"])
        table.add(["Plan", "\(header.planName) (`\(header.planID)`)"])
        table.add(["Engine", header.engine])
        table.add(["Report made on", header.runDate.description])
        table.add(["Starts from the check-in of", header.startDate.description])
        table.add(["Currency", currency])
        table.add(["Runs", "\(header.runs)" + (header.fast ? " (fast: fewer than the plan asks for)" : "")])
        table.add(["Random seed", "\(header.seed)"])
        table.add(["Confidence asked for", F.percent(header.confidence, places: 0)])
        table.add(["End age", "\(header.endAge)"])
        table.add(["Tax parameters", header.taxParameters.keys.sorted()
            .map { "\($0) \(header.taxParameters[$0]!)" }.joined(separator: ", ")])
        table.add(["Details for retiring at", "\(age) (\(header.retirementAgeChoice))"])
        table.add(["Percentiles and traced runs start from", startText])
        self.table(table)
    }

    // MARK: The person and the plan

    private mutating func writePlan() {
        let person = report.person
        let plan = report.plan
        line("## 2. The person and the plan as read")
        line()
        paragraph("How the engine read the plan file and the library: the inputs every calculation starts from. "
            + "Options are passed to the tax systems as written.")

        line("### Person")
        line()
        var facts = ["Age today: \(person.ageToday)" + (person.birthDate.map { " (born \($0))" } ?? "")]
        facts.append("Retirement age in the plan: \(person.retirementSetting)"
            + (person.targetAge.map { "; target \($0)" } ?? "")
            + "; earliest reaching the confidence level: " + (person.earliestAge.map(String.init) ?? "none"))
        facts.append("Details for retiring at \(person.chosenAge): work stops on \(person.retirementDate)")
        facts.append("The plan runs from \(person.firstYear) to \(person.lastYear) (age \(person.endAge))")
        if !person.citizenships.isEmpty { facts.append("Citizenships: \(person.citizenships.joined(separator: ", "))") }
        if let residence = person.taxResidence { facts.append("Tax residence in the library: \(residence)") }
        for fact in facts { line("- \(fact)") }
        line()

        line("### Taxes")
        line()
        var residence = MarkdownTable(["From", "System", "Currency rate", "Options"])
        for entry in plan.residence {
            residence.add(["\(entry.from)", "\(entry.systemName) (`\(entry.system)`)",
                           entry.systemCurrency.map { "\(F.number(entry.currencyRate)) \($0) per \(currency)" } ?? "–",
                           Self.json(entry.options)])
        }
        table(residence)
        for overlay in plan.overlays {
            line("- Special regime: \(overlay.name) (`\(overlay.regime)`)"
                + (overlay.options.isEmpty ? "" : ": \(Self.json(overlay.options))"))
        }
        line("- Thresholds follow inflation after the last known tax year: \(plan.indexThresholds ? "yes" : "no")")
        if !plan.overrides.isEmpty { line("- Parameter overrides: \(Self.json(plan.overrides))") }
        line()

        line("### Work")
        line()
        if plan.work.isEmpty {
            paragraph("No work phases.")
        } else {
            var work = MarkdownTable(["Phase", "Kind", "Regime", "From", "Last day", "Gross", "Costs", "Net",
                                      "Real growth", "Options"], right: [5, 6, 7, 8])
            for phase in plan.work {
                work.add(["\(phase.label) (`\(phase.id)`)", phase.kind, phase.regime ?? "default", phase.from.description,
                          "\(phase.lastDay) (until \(phase.until))", F.money(phase.gross), F.money(phase.costs),
                          phase.net.map(F.money) ?? "–", F.percent(phase.realGrowth), Self.json(phase.options)])
            }
            table(work)
        }

        line("### Spending")
        line()
        line("- While working: \(F.money(plan.spending.working)) a year")
        line("- In retirement: \(F.money(plan.spending.retired)) a year"
            + (plan.spending.phases.isEmpty ? "" : ", times "
                + plan.spending.phases.map { "\(F.number($0.factor)) from \($0.fromAge)" }.joined(separator: ", ")))
        line()

        line("### Pensions")
        line()
        if plan.pensions.isEmpty { paragraph("No pensions.") }
        for pension in plan.pensions {
            var facts = ["scheme `\(pension.scheme)` (\(pension.schemeName))", "claim \(pension.claim)"]
            if let route = pension.claimRoute { facts.append("route `\(route)`") }
            facts.append("taxed in the \(pension.taxedIn) country")
            if let kind = pension.kind { facts.append("kind \(kind)") }
            if let country = pension.sourceCountry { facts.append("paid from \(country)") }
            line("**\(pension.name)** (`\(pension.id)`): " + facts.joined(separator: ", ") + ".")
            if !pension.options.isEmpty { line("Options: \(Self.json(pension.options)).") }
            if let seed = pension.startingBalanceFromAccounts {
                line("Starting balance from the accounts that hold its record: \(F.money(seed)).")
            }
            if let claim = pension.claimed {
                var text = "Claimed in \(claim.year) at \(claim.age): \(claim.label) (`\(claim.route)`), "
                    + "\(F.money(claim.yearlyAmount)) a year gross"
                if let lumpSum = claim.lumpSum, lumpSum > 0 {
                    text += ", and a lump sum of \(F.money(lumpSum))"
                        + (claim.lumpSumWrapper.map { " moved into `\($0)`" } ?? "")
                }
                if let growth = claim.realGrowthPerYear, growth != 0 {
                    text += ", changing by \(F.signedPercent(growth)) a year in real terms"
                }
                line(text + ".")
            } else {
                line("Not claimed before the plan ends at this retirement age.")
            }
            line()
            if !pension.offered.isEmpty {
                var options = MarkdownTable(["Route", "Label", "Age", "Yearly (gross)", "Lump sum", "Real growth",
                                             "Changes", "Taken"], right: [2, 3, 4, 5])
                for option in pension.offered {
                    options.add([
                        "`\(option.route)`", option.label, "\(option.age)",
                        F.money(option.fullYearAmount ?? option.annualAmount),
                        option.lumpSum.map(F.money) ?? "–", option.realGrowthPerYear.map(F.signedPercent) ?? "–",
                        option.changes.map { "\(F.money($0.amount)) from \($0.age)" }.joined(separator: ", "),
                        option.chosen ? "yes" : "",
                    ])
                }
                table(options)
            }
        }

        line("### Contributions")
        line()
        if plan.contributions.isEmpty {
            paragraph("No planned contributions.")
        } else {
            var contributions = MarkdownTable(["Into", "Wrapper", "Per year", "Until", "Once"], right: [2])
            for entry in plan.contributions {
                contributions.add([entry.account ?? entry.pensionScheme ?? "", "`\(entry.wrapper)`",
                                   F.money(entry.perYear), entry.until,
                                   entry.year.map { "\(F.money(entry.amount ?? 0)) in \($0)" } ?? ""])
            }
            table(contributions)
        }

        line("### One-off events")
        line()
        if plan.events.isEmpty {
            paragraph("No events.")
        } else {
            var events = MarkdownTable(["Event", "Kind", "Year", "Age", "Amount", "Probability", "In the deterministic run"],
                                       right: [2, 3, 4, 5])
            for event in plan.events {
                events.add([event.name, event.kind, "\(event.year)", "\(event.age)", F.money(event.amount),
                            F.percent(event.probability, places: 0), event.inDeterministicRun ? "yes" : "no"])
            }
            table(events)
        }

        line("### Withdrawals, rebalancing and fees")
        line()
        line("- Strategy: \(plan.withdrawals.strategy) (spend what the plan says; the portfolio absorbs the markets). "
            + "Cash buffer: \(F.money(plan.withdrawals.cashBuffer)).")
        for (index, step) in plan.withdrawals.order.enumerated() { line("- Drawn \(index + 1): \(step)") }
        line("- Rebalancing: \(plan.withdrawals.rebalancing)")
        line("- Fees: \(plan.fees)")
        line()
    }

    private mutating func writeAssumptions() {
        let assumptions = report.assumptions
        line("### Assumptions")
        line()
        paragraph("Each class's expected real return is the average of a log-normal yearly return with the given "
            + "volatility; its median is what a typical year gives, lower the more volatile the class is. A "
            + "portfolio rebalanced every year compounds at about its median. \"Target share\" is the class's share "
            + "of the mix the buckets are rebalanced to (each bucket's target mix, weighted by its value), and "
            + "\"Portfolio median without\" that mix's median growth with the class left out and the rest in their "
            + "proportions. Inflation: \(F.percent(assumptions.inflation)) a year.")
        var classes = MarkdownTable(["Class", "Share today", "Target share", "Expected real return", "Volatility",
                                     "Median", "Income yield", "Portfolio median without"], right: Set(1...7))
        for asset in assumptions.classes {
            classes.add([F.className(asset.assetClass), F.percent(asset.share), F.percent(asset.targetShare),
                         F.percent(asset.expectedReturn), F.percent(asset.volatility, places: 0),
                         F.percent(asset.medianReturn), F.percent(asset.incomeYield),
                         asset.portfolioMedianWithout.map { F.percent($0) } ?? "–"])
        }
        table(classes)
        let portfolio = assumptions.portfolio
        paragraph("The target mix, rebalanced every year: expected \(F.percent(portfolio.expectedReturn)), "
            + "volatility \(F.percent(portfolio.volatility)), median \(F.percent(portfolio.medianReturn)) a year "
            + "(a log-normal approximation from the table and the correlations below).")
        if assumptions.correlationClasses.count > 1 {
            line("Correlations between the yearly (log) returns, as the simulation uses them:")
            line()
            let names = assumptions.correlationClasses.map(F.className)
            var correlations = MarkdownTable([""] + names, right: Set(1...names.count))
            for (index, row) in assumptions.correlations.enumerated() {
                correlations.add([names[index]] + row.map { String(format: "%.2f", $0) })
            }
            table(correlations)
        }
    }

    // MARK: Starting portfolio

    private mutating func writeStart() {
        let start = report.start
        line("## 3. Starting portfolio")
        line()
        paragraph("Each library account on \(start.date), valued in \(currency), and the bucket (tax wrapper) it went "
            + "into. The simulation draws from buckets: liquid ones at any time, tax-advantaged ones by their "
            + "rules. Plan assets: \(F.money(start.planAssets)).")
        var accounts = MarkdownTable(["Account", "Kind", "Currency", "Wrapper", "Value", "Cost basis", "In the plan"],
                                     right: [4, 5])
        for account in start.accounts {
            let status = switch account.outcome {
            case "included": "yes, bucket `\(account.bucket ?? "")`"
            case "schemeSeed": "no: \(account.reason ?? "")"
            default: "no: \(account.reason ?? "left out")"
            }
            accounts.add(["\(account.name) (`\(account.id)`)", account.kind, account.currency,
                          account.wrapper.map { "`\($0)`" } ?? "–", account.value.map(F.money) ?? "–",
                          account.costBasis.map(F.money) ?? "–", status])
        }
        table(accounts)

        let holdings = start.accounts.filter { $0.outcome == "included" && !$0.holdings.isEmpty }
        if !holdings.isEmpty {
            line("What the included accounts hold, as the plan's lots:")
            line()
            var lots = MarkdownTable(["Account", "Instrument", "Class", "Tax category", "Value", "Cost basis",
                                      "Cost from", "FX rate"], right: [4, 5, 7])
            for account in holdings {
                for holding in account.holdings {
                    lots.add([account.name, holding.instrument.map { "`\($0)`" } ?? "–", holding.assetClass,
                              holding.category, F.money(holding.value), holding.costBasis.map(F.money) ?? "unknown",
                              holding.basisSource, holding.fxRate.map { F.number($0) } ?? "–"])
                }
            }
            table(lots)
        }
        if !start.instruments.isEmpty {
            var instruments = MarkdownTable(["Instrument", "Kind", "Fund type", "Currency", "Asset classes"])
            for instrument in start.instruments {
                instruments.add(["\(instrument.name) (`\(instrument.id)`)", instrument.kind, instrument.fundType ?? "–",
                                 instrument.currency, Self.mix(instrument.assetClasses)])
            }
            table(instruments)
        }
        if !start.fxRates.isEmpty {
            line("Exchange rates used: " + start.fxRates.map {
                "1 \($0.from) = \(F.number($0.rate)) \($0.to)" + ($0.date.map { " (\($0))" } ?? "")
            }.joined(separator: "; ") + ".")
            line()
        }

        line("The buckets the simulation draws from:")
        line()
        var buckets = MarkdownTable(["Bucket", "Wrapper", "Kind", "Value", "Cost basis", "Target mix", "Can be drawn",
                                     "Accounts"], right: [3, 4])
        for bucket in start.buckets {
            var access: String
            if bucket.liquid {
                access = "any time"
            } else if bucket.paidWhenJobEnds {
                access = "paid out when work stops"
            } else if let opens = bucket.accessibleFromAge {
                access = "from \(opens)"
            } else {
                access = "not within the plan"
            }
            if let reason = bucket.lockedReason, !bucket.liquid { access += " (now: \(reason))" }
            if let rate = bucket.growthTaxRate, rate > 0 { access += "; growth taxed at \(F.percent(rate))" }
            if let revaluation = bucket.revaluation { access += "; grows by \(revaluation), by law" }
            buckets.add([bucket.name + (bucket.receivesSavings ? " (gets savings)" : ""), "`\(bucket.wrapper)`",
                         bucket.liquid ? "liquid" : bucket.category, F.money(bucket.value), F.money(bucket.costBasis),
                         Self.mix(bucket.targetMix), access, bucket.accounts.joined(separator: ", ")])
        }
        table(buckets)
        for seed in start.schemeSeeds {
            line("- \(seed.accounts.joined(separator: ", ")) (\(F.money(seed.value))) hold the record of \(seed.name) "
                + "(`\(seed.scheme)`): " + (seed.used ? "their value is its starting balance, not money the plan draws on."
                    : "the plan sets the starting balance itself, so their value isn't used."))
        }
        if start.debtPaidOff > 0 { line("- Debts of \(F.money(start.debtPaidOff)) are paid off from liquid money at the start.") }
        if let share = start.unrealizedGainShare {
            line("- Where no purchase cost was recorded, the plan assumes \(F.percent(share, places: 0)) of the value is "
                + "unrealised gain.")
        }
        line("- Plan assets by class: \(Self.mix(start.classShares)).")
        line()
    }

    // MARK: Schedule

    private mutating func writeSchedule() {
        let schedule = report.schedule
        line("## 4. Year-by-year schedule (retiring at \(schedule.retirementAge))")
        line()
        paragraph("What doesn't depend on the markets, from the deterministic run's prepared years: income, "
            + "pensions, contributions, spending and the taxes on them. \"To draw\" is what the portfolio must "
            + "provide (spending, expenses and contributions less net income); negative means money saved. Taxes on "
            + "sales, payouts and balances come on top, and depend on each path (section 7). The first year is the "
            + "part after the check-in.")
        let years = schedule.years
        var keep = Set<Int>()
        if let retired = years.firstIndex(where: { $0.workingShare < 1 }) { keep.formUnion([retired - 1, retired, retired + 1]) }
        for (index, year) in years.enumerated() where !year.windfalls.isEmpty || year.expenses != 0
            || !year.requiredPayouts.isEmpty {
            keep.insert(index)
        }
        let claimYears = Set(report.plan.pensions.compactMap { $0.claimed?.year })
        for (index, year) in years.enumerated() where claimYears.contains(year.year) { keep.formUnion([index, index + 1]) }
        let shown = F.shownRows(ages: years.map(\.age), keep: keep)
        var table = MarkdownTable(["Year", "Age", "Work", "Pensions", "Windfalls", "Contributions", "Spending",
                                   "Expenses", "Taxes", "Net income", "To draw", "Notes"],
                                  right: Set(0...10))
        table.add(shown: shown) { index in
            let year = years[index]
            var notes: [String] = []
            if year.workingShare > 0, year.workingShare < 1 { notes.append("retires during the year") }
            for pension in year.pensions where claimYears.contains(year.year) && year.pensions.count > 0 {
                notes.append("\(pension.label) \(F.money(pension.amount))")
            }
            notes += year.requiredPayouts.map { "pays out \($0)" }
            notes += year.credits.map { "\(F.money($0.amount)) into \($0.label)" }
            let taxes = (year.taxes + year.socialContributions).reduce(0) { $0 + $1.amount }
            return ["\(year.year)", "\(year.age)", F.money(year.work),
                    F.money(year.pensions.reduce(0) { $0 + $1.amount }), F.money(year.windfalls.reduce(0) { $0 + $1.amount }),
                    F.money(year.contributions), F.money(year.spending), F.money(year.expenses), F.money(taxes),
                    F.money(year.netIncome), F.money(year.toDraw), notes.joined(separator: "; ")]
        }
        self.table(table)
    }

    // MARK: Simulation summary

    private mutating func writeSimulation() {
        let simulation = report.simulation
        line("## 5. Simulation summary")
        line()
        paragraph("How often the plan works, by retirement age (each age uses the same \(report.header.runs) random "
            + "futures), and how the two searches found their answers.")
        line("### Chance of success by retirement age")
        line()
        var ages = MarkdownTable(["Age", "Year", "Success"], right: [0, 1, 2])
        for point in simulation.successByAge {
            ages.add(["\(point.age)" + (point.age == age ? " (shown)" : ""), "\(point.year)",
                      F.percent(point.success, places: 0)])
        }
        table(ages)
        line("Retiring today succeeds in \(F.percent(simulation.successToday, places: 0)) of futures; the earliest age "
            + "reaching \(F.percent(report.header.confidence, places: 0)) is "
            + (simulation.earliestAge.map(String.init) ?? "none before the plan ends") + ".")
        line()

        if let search = simulation.sustainableSpending {
            line("### Sustainable spending")
            line()
            paragraph("The highest yearly retirement spending (before the plan's phase factors) that reaches the "
                + "confidence level at \(search.age), found by bisection: each level tried, in order, and the share "
                + "of futures that succeed with it. The plan spends \(F.money(search.planSpending)).")
            var steps = MarkdownTable(["Step", "Spending", "Success"], right: [0, 1, 2])
            for (index, step) in search.steps.enumerated() {
                steps.add(["\(index + 1)", F.money(step.spending), F.percent(step.success)])
            }
            table(steps)
            paragraph("Result: " + (search.perYear.map { "\(F.money($0)) a year, succeeding in "
                + F.percent(search.success ?? 0) + " of futures." } ?? "no spending reaches the confidence level."))
        }
        if let search = simulation.assetsNeeded {
            line("### Assets needed to retire today")
            line()
            paragraph("The plan assets that would make retiring at \(search.age) reach the confidence level. The "
                + "search scales every holding of the starting portfolio by the same factor (so the mix, the buckets "
                + "and the unrealised gains keep their proportions), doubling or halving from 1, then bisecting until "
                + "within 1%, up to \(F.number(search.maximumScale)) times today's \(F.money(search.planAssets)).")
            var steps = MarkdownTable(["Step", "Scale", "Plan assets", "Success"], right: [0, 1, 2, 3])
            for (index, step) in search.steps.enumerated() {
                steps.add(["\(index + 1)", F.number((step.scale * 1000).rounded() / 1000), F.money(step.amount),
                           F.percent(step.success)])
            }
            table(steps)
            let result = switch search.outcome {
            case "found": "\(F.money(search.amount ?? 0)) (\(F.times(search.scale ?? 0)) today's plan assets), "
                + "succeeding in \(F.percent(search.success ?? 0)) of futures; readiness "
                + "\(F.percent(search.readiness ?? 0, places: 0))."
            case "moreThanMaximum": "more than \(F.number(search.maximumScale)) times today's plan assets."
            case "atMost": "at most \(F.money(search.amount ?? 0)); readiness at least "
                + "\(F.percent(search.readiness ?? 0, places: 0))."
            default: "the plan counts no assets to scale."
            }
            paragraph("Result: " + result)
        }

        let failures = simulation.failures
        line("### Why runs fail (retiring at \(age))")
        line()
        if isScaled {
            line("Starting from \(startText), retiring at \(age) succeeds in "
                + "\(F.percent(simulation.successAtStartScale)) of runs"
                + (simulation.searchSuccessAtStartScale.map { "; the search counted \(F.percent($0)) at this scale" } ?? "")
                + ".")
            line()
        }
        if failures.failed == 0 {
            paragraph("No run fails.")
        } else {
            line("\(failures.failed) of \(failures.runs) runs fail (\(F.percent(failures.failureRate, places: 0)))"
                + (failures.medianFailureAge.map { ", at a median age of \($0)" } ?? "") + ": \(failures.depleted) run out "
                + "of money entirely, \(failures.bridging) while money was still locked in a wrapper that would have "
                + "bridged the gap.")
            line()
            line("Failures by age: " + failures.byAge.map { "\($0.age): \($0.count)" }.joined(separator: ", ") + ".")
            line()
            for bridge in failures.bridges {
                line("- \(bridge.count) before \(bridge.name) (`\(bridge.wrapper)`) opens"
                    + (bridge.accessibleFromAge.map { " at \($0)" } ?? "") + ".")
            }
            if !failures.bridges.isEmpty { line() }
        }
        if let reproduced = simulation.allRunsReproduced {
            paragraph("Check: re-simulating every run for the percentiles below "
                + (reproduced ? "reproduced the main run's outcome for each."
                    : "did **not** reproduce every outcome of the main run."))
        }
    }

    // MARK: Percentiles

    private mutating func writePercentiles() {
        let years = report.percentiles
        line("## 6. Percentiles by year (retiring at \(age))")
        line()
        paragraph("Across all \(report.header.runs) runs, starting from \(startText): plan assets at each year-end, "
            + "from the 10th to the 90th percentile, and the deterministic run's (expected returns every year). "
            + "Withdrawals (gross sales and "
            + "payouts) and taxes are among the runs still going; \"Going\" is the share of runs still meeting their "
            + "spending at the year-end.")
        var keep = Set<Int>()
        if let retired = report.schedule.years.firstIndex(where: { $0.workingShare < 1 }) {
            keep.formUnion([retired - 1, retired, retired + 1])
        }
        let shown = F.shownRows(ages: years.map(\.age), keep: keep)
        var table = MarkdownTable(["Year", "Age", "p10", "p25", "Median", "p75", "p90", "Deterministic",
                                   "Withdrawals p10", "Withdrawals median", "Withdrawals p90", "Taxes median", "Going"],
                                  right: Set(0...12))
        table.add(shown: shown) { index in
            let year = years[index]
            return ["\(year.year)", "\(year.age)", F.money(year.value.p10), F.money(year.value.p25), F.money(year.value.p50),
                    F.money(year.value.p75), F.money(year.value.p90), F.money(year.expected),
                    F.money(year.withdrawals.p10), F.money(year.withdrawals.p50), F.money(year.withdrawals.p90),
                    F.money(year.taxes.p50), F.percent(year.going, places: 0)]
        }
        self.table(table)
    }

    // MARK: Traced paths

    private mutating func writePaths() {
        line("## 7. Traced paths")
        line()
        paragraph("Single runs re-simulated step by step, starting from \(startText), with the same random draws "
            + "as the main run, so each ends exactly as the same run untraced. The first table shows the real return drawn for each class and each "
            + "bucket's balance at the year-end; the second the money in and out: net income (work, pensions and "
            + "windfalls after their taxes), payouts the rules require, the spending target and what was met, what "
            + "was drawn (gross, before tax), the gains those sales realised, taxes on income (work, pensions, "
            + "windfalls) and on markets (sales, payouts, interest and balances; paid the next year unless withheld "
            + "from a sale), and what rebalancing sold; when the tax system carries something along the path, such as "
            + "losses it lets later years offset, what it carries into the next year. A year in detail follows each path.")
        if report.paths.isEmpty { paragraph("No paths were traced.") }
        for path in report.paths { writePath(path) }
    }

    private mutating func writePath(_ path: PlanDebugReport.TracedPath) {
        line("### \(path.label)")
        line()
        var text = ""
        if let run = path.run {
            text += "Run \(run)" + (path.rank.map { ", ranked \($0) of \(report.header.runs) from worst to best" } ?? "")
                + ". "
        }
        text += path.failed
            ? "It fails in \(path.failureYear.map(String.init) ?? "?"), at \(path.failureAge.map(String.init) ?? "?"). "
                + (path.failureReason ?? "")
            : "It lasts to the end, with \(F.money(path.finalValue)) left."
        paragraph(text + " Same outcome as the main run: \(path.matchesMainRun ? "yes" : "**no**").")

        let years = path.years
        var keep = Set<Int>()
        if let retired = report.schedule.years.firstIndex(where: { $0.workingShare < 1 }) {
            keep.formUnion([retired - 1, retired, retired + 1])
        }
        if path.failed { keep.formUnion([years.count - 2, years.count - 1]) }
        for (index, year) in years.enumerated() where !year.payouts.filter({ $0.purpose == "required" }).isEmpty {
            keep.insert(index)
        }
        let shown = F.shownRows(ages: years.map(\.age), keep: keep)
        let classes = path.classes.map(F.className)
        var balances = MarkdownTable(["Year", "Age"] + classes + path.buckets.map(\.name) + ["Plan assets"],
                                     right: Set(0..<(3 + classes.count + path.buckets.count)))
        balances.add(shown: shown) { index in
            let year = years[index]
            return ["\(year.year)", "\(year.age)"] + year.returns.map(F.signedPercent) + year.buckets.map { F.money($0.end) }
                + [F.money(year.endAssets)]
        }
        table(balances)

        // What the tax system carries forward gets a column only on a path where it carries something.
        let carries = years.contains { !($0.carriedForward ?? []).isEmpty }
        var flows = MarkdownTable(["Year", "Age", "Net income", "Payouts", "Spending", "Met", "Drawn", "Gains",
                                   "Tax on income", "Tax on markets", "Rebalanced", "Saved"]
                                      + (carries ? ["Carried forward"] : []), right: Set(0...(carries ? 12 : 11)))
        flows.add(shown: shown) { index in
            let year = years[index]
            let drawn = year.buckets.reduce(0) { $0 + $1.withdrawn }
            let gains = year.sales.reduce(0) { $0 + ($1.gain ?? 0) }
            let fixed = year.taxes.reduce(0) { $0 + $1.fixed }
            let market = year.taxes.reduce(0) { $0 + $1.market }
            let rebalanced = year.buckets.reduce(0) { total, bucket in total + bucket.rebalancing.filter { $0 < 0 }.reduce(0, -) }
            let carried = (year.carriedForward ?? []).reduce(0) { $0 + $1.amount }
            return ["\(year.year)", "\(year.age)", F.money(year.netIncome), F.money(year.payoutsNet),
                    F.money(year.spendingTarget), F.money(year.spendingMet), F.money(drawn), F.money(gains),
                    F.money(fixed), F.money(market), F.money(rebalanced), F.money(max(0, year.cashFlow))]
                + (carries ? [F.money(carried)] : [])
        }
        table(flows)

        // One year in detail: the first year fully retired, else the last.
        let detailIndex = years.indices.first { index in
            report.schedule.years.indices.contains(index) && report.schedule.years[index].workingShare == 0
        } ?? years.indices.last
        if let detailIndex { writeYear(years[detailIndex], path: path) }
        if path.failed, let last = years.indices.last, last != detailIndex { writeYear(years[last], path: path) }
    }

    private mutating func writeYear(_ year: PlanDebugReport.TracedYear, path: PlanDebugReport.TracedPath) {
        line("**\(year.year) in detail** (age \(year.age)" + (year.fraction < 1 ? ", \(F.percent(year.fraction, places: 0)) "
            + "of the year simulated" : "") + (year.failed ? ", the year it fails" : "") + "):")
        line()
        line("- Cash flow: net income \(F.money(year.netIncome)) + payouts \(F.money(year.payoutsNet)) − contributions "
            + "\(F.money(year.contributions)) − spending \(F.money(year.spending)) − expenses \(F.money(year.expenses)) − "
            + "last year's taxes \(F.money(year.lastYearsTaxes)) = \(F.money(year.cashFlow))"
            + (year.cashFlow < 0 ? " to draw" : " to invest")
            + (year.shortfall > 0.005 ? "; \(F.money(year.shortfall)) couldn't be raised" : "") + ".")
        for sale in year.sales {
            line("- Sale (\(sale.purpose)) from `\(sale.wrapper)`, \(sale.category): \(F.money(sale.proceeds)) "
                + (sale.costBasis.map { "with a cost of \(F.money($0)), gain \(F.money(sale.proceeds - $0))" }
                    ?? "with an unknown cost") + ".")
        }
        for payout in year.payouts {
            line("- Payout (\(payout.purpose), \(payout.form)) from `\(payout.wrapper)`: \(F.money(payout.amount))"
                + (payout.costBasis.map { ", of which \(F.money($0)) paid in" } ?? "") + ".")
        }
        if year.withheldOnPayouts + year.withheldOnWithdrawals + year.withheldOnRebalancing > 0.005 {
            line("- Tax withheld: \(F.money(year.withheldOnPayouts)) on required payouts, "
                + "\(F.money(year.withheldOnWithdrawals)) on withdrawals, \(F.money(year.withheldOnRebalancing)) on "
                + "rebalancing.")
        }
        for (b, bucket) in year.buckets.enumerated() where bucket.start > 0.005 || bucket.end > 0.005 {
            let moves = zip(path.classes, bucket.rebalancing).filter { abs($0.1) > 0.5 }
                .map { "\($0.0) \($0.1 > 0 ? "+" : "")\(F.money($0.1))" }
            line("- \(path.buckets[b].name): \(F.money(bucket.start)) at the start, +\(F.money(bucket.moneyIn)) in, "
                + "−\(F.money(bucket.requiredPayouts + bucket.withdrawn)) out, "
                + (moves.isEmpty ? "" : "rebalanced \(moves.joined(separator: ", "))"
                    + (bucket.rebalancingTax > 0.005 ? " (tax \(F.money(bucket.rebalancingTax)))" : "") + ", ")
                + "growth \(F.money(bucket.growth)), \(F.money(bucket.end)) at the end (cost basis "
                + "\(F.money(bucket.endCostBasis))).")
        }
        if !year.taxes.isEmpty {
            line("- Taxes and contributions: " + year.taxes.map { tax in
                var parts: [String] = []
                if abs(tax.fixed) > 0.005 { parts.append("\(F.money(tax.fixed)) on income") }
                if abs(tax.market) > 0.005 { parts.append("\(F.money(tax.market)) on markets") }
                return "\(tax.label) \(parts.joined(separator: " + "))"
            }.joined(separator: "; ") + (year.carriedToNextYear > 0.005
                ? "; \(F.money(year.carriedToNextYear)) of it is paid next year"
                : year.carriedToNextYear < -0.005
                    ? "; \(F.money(-year.carriedToNextYear)) less than was withheld, credited next year" : "") + ".")
        }
        if let carried = year.carriedForward, !carried.isEmpty {
            line("- Carried into next year by the tax system: "
                + carried.map { "\($0.label) \(F.money($0.amount))" }.joined(separator: "; ") + ".")
        }
        line()
    }

    // MARK: Issues

    private mutating func writeIssues() {
        line("## 8. Issues")
        line()
        paragraph("Warnings from the plan, the tax systems and the years assessed, as the app shows them.")
        if report.issues.isEmpty { paragraph("None.") }
        for issue in report.issues {
            line("- **\(issue.severity)** `\(issue.code)`: \(issue.message)")
        }
        if !report.issues.isEmpty { line() }
    }
}
