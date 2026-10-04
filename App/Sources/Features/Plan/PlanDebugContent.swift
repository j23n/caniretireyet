import Foundation
import Model
import Planner

/// What the plan debugger's screen shows of a `PlanDebugReport` (UI.md,
/// "Calculations (plan debugger)"), laid out once per report: the
/// diagnosis, each section's blocks and tables, the charts' points, the
/// traced runs and the issues. A year of the schedule or of a traced run
/// is laid out in detail when it's chosen (``scheduleDetail(_:)``,
/// ``pathDetail(_:year:)``).
///
/// Every year is here: unlike the Markdown, nothing is skipped. Money stays
/// a number until a view shows it, in ``currency``.
struct PlanDebugContent: Sendable {
    let report: PlanDebugReport
    /// The report's currency.
    let currency: CurrencyCode
    /// What the app adds on what was run (the what-if), first in *What was run*.
    let notes: [String]
    /// The diagnosis, a sentence each.
    let diagnosis: [String]
    /// The success curve: chance of success by retirement age.
    let successPoints: [SuccessPoint]
    /// The percentiles as a fan: the start, then each year-end.
    let fan: [FanPoint]
    /// Retirement and pension starts on the fan.
    let fanMarkers: [ChartMarker]
    let paths: [PlanDebugPath]
    let issues: [PlanDebugIssue]
    private let sectionBlocks: [PlanDebugSection: [PlanDebugBlock]]

    init(report: PlanDebugReport, notes: [String] = []) {
        self.report = report
        currency = CurrencyCode(rawValue: report.header.currency)
        self.notes = notes
        diagnosis = report.diagnosis.map(\.text)
        successPoints = report.simulation.successByAge.map { SuccessPoint(age: $0.age, success: $0.success) }
        fan = Self.fan(report)
        fanMarkers = Self.markers(report)
        paths = report.paths.indices.map { Self.path(report, $0) }
        issues = report.issues.enumerated().map { index, issue in
            let place = [issue.code, issue.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
            return PlanDebugIssue(id: index, isError: issue.severity == "error",
                                  title: (issue.severity == "error" ? "Error" : "Warning") + " · " + place,
                                  message: issue.message)
        }
        sectionBlocks = [
            .run: Self.run(report, notes: notes),
            .plan: Self.plan(report),
            .start: Self.start(report),
            .schedule: Self.schedule(report),
            .simulation: Self.simulation(report),
            .percentiles: Self.percentiles(report),
        ]
    }

    /// The sections, in order.
    var sections: [PlanDebugSection] { PlanDebugSection.allCases }

    /// A section's blocks (the traced runs and issues have their own views).
    func blocks(_ section: PlanDebugSection) -> [PlanDebugBlock] {
        sectionBlocks[section] ?? []
    }

    /// Whether the percentiles, failures and traced runs start from a
    /// multiple of today's plan assets.
    var isScaled: Bool { abs(report.header.startScale - 1) > 1e-9 }

    /// The year's index of the schedule (and of each traced run) where work stops.
    var retirementIndex: Int? {
        report.schedule.years.firstIndex { $0.workingShare < 1 }
    }

    // MARK: Charts

    private static func fan(_ report: PlanDebugReport) -> [FanPoint] {
        let start = report.header.startAssets
        var points = [FanPoint(date: report.header.startDate.dateValue, p10: start, p25: start, p50: start, p75: start,
                               p90: start)]
        for year in report.percentiles {
            guard let end = YearMonth(year: year.year, month: 12)?.lastDay, end > report.header.startDate else {
                continue
            }
            points.append(FanPoint(date: end.dateValue, p10: year.value.p10, p25: year.value.p25, p50: year.value.p50,
                                   p75: year.value.p75, p90: year.value.p90))
        }
        return points
    }

    private static func markers(_ report: PlanDebugReport) -> [ChartMarker] {
        var markers = [ChartMarker(date: report.person.retirementDate.dateValue,
                                   label: "Retire at \(report.header.retirementAge)", systemImage: "figure.walk",
                                   kind: .retirement)]
        for pension in report.plan.pensions {
            guard let claim = pension.claimed, claim.startYear > report.person.firstYear else { continue }
            let birthday = report.person.birthDate.flatMap {
                CalendarDate(year: claim.startYear, month: $0.month, day: min($0.day, 28))
            }
            let date = birthday ?? CalendarDate(year: claim.startYear, month: 7, day: 1)
            guard let date else { continue }
            markers.append(ChartMarker(date: date.dateValue, label: "\(pension.name) \(claim.age)",
                                       systemImage: "building.columns", kind: .pension))
        }
        return markers
    }

    // MARK: What was run

    private static func run(_ report: PlanDebugReport, notes: [String]) -> [PlanDebugBlock] {
        let header = report.header
        var lines = PlanDebugLines()
        lines.add("Plan", .text(header.planName))
        lines.add("Engine", .number(header.engine))
        lines.add("Report made on", .date(header.runDate))
        lines.add("Starts from the check-in of", .date(header.startDate))
        lines.add("Currency", .number(header.currency))
        lines.add("Runs", .count(header.runs), note: header.fast ? "fewer than the plan asks for" : nil)
        lines.add("Random seed", .number(String(header.seed)))
        lines.add("Confidence asked for", .percent(header.confidence, digits: 0))
        lines.add("End age", .number("\(header.endAge)"))
        lines.add("Tax parameters", .words(header.taxParameters.keys.sorted()
                .map { "\($0) \(header.taxParameters[$0]!)" }.joined(separator: ", ")))
        lines.add("Details for retiring at", .number("\(header.retirementAge)"),
                  note: header.retirementAgeChoice == "today" ? "today's age"
                      : header.retirementAgeChoice == "target" ? "the plan's target" : nil)
        lines.add("Runs start from", .money(header.startAssets),
                  note: PlanDebugText.scale(report) ?? "today's plan assets")
        return [PlanDebugBlock(id: "run", sentences: notes, lines: lines.lines)]
    }

    // MARK: The person and the plan

    private static func plan(_ report: PlanDebugReport) -> [PlanDebugBlock] {
        let person = report.person
        let plan = report.plan
        let currency = report.header.currency
        var blocks: [PlanDebugBlock] = []

        var facts = PlanDebugLines()
        facts.add("Age today", .number("\(person.ageToday)"), note: person.birthDate.map { "born \($0)" })
        facts.add("Retirement age in the plan", .text(person.retirementSetting),
                  note: person.targetAge.map { "target \($0)" })
        facts.add("Earliest age reaching the confidence level",
                  person.earliestAge.map { PlanDebugValue.number("\($0)") } ?? .text("none"))
        facts.add("Details for retiring at", .number("\(person.chosenAge)"))
        facts.add("Work stops on", .date(person.retirementDate))
        facts.add("The plan runs", .number("\(person.firstYear)–\(person.lastYear)"), note: "to age \(person.endAge)")
        if !person.citizenships.isEmpty { facts.add("Citizenships", .text(person.citizenships.joined(separator: ", "))) }
        if let residence = person.taxResidence { facts.add("Tax residence in the library", .text(residence)) }
        blocks.append(PlanDebugBlock(id: "person", title: "Person", lines: facts.lines))

        var residence = PlanDebugTableBuilder("residence", [
            .year("From"), .label("System", key: true), .text("Currency rate"), .text("Options"),
        ], titleColumns: [0])
        for entry in plan.residence {
            residence.add([
                .number("\(entry.from)"), .text("\(entry.systemName) (\(entry.system))"),
                entry.systemCurrency.map { PlanDebugValue.text("\(PlanDebugText.number(entry.currencyRate)) \($0) per \(currency)") }
                    ?? .missing,
                .words(PlanDebugText.options(entry.options)),
            ])
        }
        var taxSentences = plan.overlays.map { overlay in
            "Special regime: \(overlay.name) (\(overlay.regime))"
                + (overlay.options.isEmpty ? "." : ": \(PlanDebugText.options(overlay.options)).")
        }
        taxSentences.append("Thresholds follow inflation after the last known tax year: "
            + (plan.indexThresholds ? "yes." : "no."))
        if !plan.overrides.isEmpty {
            taxSentences.append("Parameter overrides: \(PlanDebugText.options(plan.overrides)).")
        }
        blocks.append(PlanDebugBlock(id: "taxes", title: "Taxes", sentences: taxSentences, table: residence.table))

        if plan.work.isEmpty {
            blocks.append(PlanDebugBlock(id: "work", title: "Work", sentences: ["No work phases."]))
        } else {
            var work = PlanDebugTableBuilder("work", [
                .label("Phase"), .text("Kind"), .text("Regime"), .text("From"), .text("Last day"), .text("Until"),
                .money("Gross", key: true), .money("Costs"), .money("Net"), .percent("Real growth"), .text("Options"),
            ])
            for phase in plan.work {
                work.add([
                    .text(phase.label), .text(phase.kind), .text(phase.regime ?? "default"), .date(phase.from),
                    .date(phase.lastDay), .text(phase.until), .money(phase.gross), .money(phase.costs),
                    .amount(phase.net), .percent(phase.realGrowth), .words(PlanDebugText.options(phase.options)),
                ])
            }
            blocks.append(PlanDebugBlock(id: "work", title: "Work",
                                         note: "Gross pay or revenue a year, in the first year it's stated for. The "
                                             + "last day is the one at the age the details are for.",
                                         table: work.table))
        }

        var spending = PlanDebugLines()
        spending.add("While working", .money(plan.spending.working), note: "a year")
        spending.add("In retirement", .money(plan.spending.retired), note: "a year")
        for phase in plan.spending.phases {
            spending.add("From \(phase.fromAge)", .text(PlanDebugText.times(phase.factor)), note: "of it")
        }
        blocks.append(PlanDebugBlock(id: "spending", title: "Spending", lines: spending.lines))

        if plan.pensions.isEmpty {
            blocks.append(PlanDebugBlock(id: "pensions", title: "Pensions", sentences: ["No pensions."]))
        }
        for (index, pension) in plan.pensions.enumerated() {
            blocks.append(Self.pension(pension, index: index))
        }

        if plan.contributions.isEmpty {
            blocks.append(PlanDebugBlock(id: "contributions", title: "Contributions",
                                         sentences: ["No planned contributions."]))
        } else {
            var contributions = PlanDebugTableBuilder("contributions", [
                .label("Into"), .text("Wrapper"), .money("Per year", key: true), .text("Until"), .year("Once in"),
                .money("Amount"),
            ])
            for entry in plan.contributions {
                contributions.add([
                    .text(entry.account ?? entry.pensionScheme ?? "–"), .text(entry.wrapper), .money(entry.perYear),
                    .text(entry.until), entry.year.map { PlanDebugValue.number("\($0)") } ?? .missing, .amount(entry.amount),
                ])
            }
            blocks.append(PlanDebugBlock(id: "contributions", title: "Contributions", table: contributions.table))
        }

        if plan.events.isEmpty {
            blocks.append(PlanDebugBlock(id: "events", title: "One-off events", sentences: ["No events."]))
        } else {
            var events = PlanDebugTableBuilder("events", [
                .label("Event"), .text("Kind"), .year(), .age(), .money("Amount", key: true),
                .percent("Probability", key: true), .text("In the deterministic run"),
            ])
            for event in plan.events {
                events.add([
                    .text(event.name), .text(event.kind), .number("\(event.year)"), .number("\(event.age)"),
                    .money(event.amount), .percent(event.probability, digits: 0),
                    .text(event.inDeterministicRun ? "yes" : "no"),
                ])
            }
            blocks.append(PlanDebugBlock(id: "events", title: "One-off events",
                                         note: "Positive for a windfall, negative for an expense. The deterministic "
                                             + "run includes an event with a probability of at least 50%.",
                                         table: events.table))
        }

        var withdrawals = PlanDebugLines()
        withdrawals.add("Strategy", .text(plan.withdrawals.strategy),
                        note: "spend what the plan says; the portfolio absorbs the markets")
        withdrawals.add("Cash buffer", .money(plan.withdrawals.cashBuffer))
        var order = plan.withdrawals.order.enumerated().map { "\($0.offset + 1). \($0.element)" }
        order.append("Rebalancing: \(plan.withdrawals.rebalancing)")
        order.append("Fees: \(plan.fees)")
        blocks.append(PlanDebugBlock(id: "withdrawals", title: "Withdrawals, rebalancing and fees", sentences: order,
                                     lines: withdrawals.lines))
        if let target = plan.targetMix { blocks.append(targetMix(target, age: report.header.retirementAge)) }

        blocks += assumptions(report.assumptions)
        return blocks
    }

    /// The plan's target mix and its changes with age.
    private static func targetMix(_ target: PlanDebugReport.TargetMixPlan, age: Int) -> PlanDebugBlock {
        var sentences = ["The ordinary (taxable) accounts are rebalanced to "
            + (target.mix.map { PlanDebugText.mix($0) } ?? "each one's own mix at the start")
            + (target.steps.isEmpty ? "." : ", then from each age below to its mix.")]
        sentences.append("Pension funds and other tax-advantaged accounts keep their own mix.")
        var lines = PlanDebugLines()
        if let growth = target.growth {
            lines.add("Median growth of the target", .percent(growth.medianReturn), note: "a year, rebalanced every year")
        }
        var table: PlanDebugTable?
        if !target.steps.isEmpty {
            var steps = PlanDebugTableBuilder("target-mix", [
                .label("From"), .count("Starts at"), .text("Mix", key: true), .percent("Expected"),
                .percent("Median", key: true), .text("Applies"),
            ])
            for step in target.steps {
                steps.add([.text(step.fromAge), step.startAge.map { .number("\($0)") } ?? .missing,
                           .text(PlanDebugText.mix(step.mix)), .percent(step.growth.expectedReturn),
                           .percent(step.growth.medianReturn), .text(step.applies ? "yes" : "no")])
            }
            table = steps.table
        }
        return PlanDebugBlock(id: "target-mix", title: "Target mix",
                              note: target.steps.isEmpty ? nil : "“Starts at” is for retiring at \(age). A change a "
                                  + "later one overtakes, or that starts after the plan's end, never applies.",
                              sentences: sentences, lines: lines.lines, table: table)
    }

    private static func pension(_ pension: PlanDebugReport.Pension, index: Int) -> PlanDebugBlock {
        var facts = ["Scheme \(pension.scheme) (\(pension.schemeName))", "claim \(pension.claim)"]
        if let route = pension.claimRoute { facts.append("route \(route)") }
        facts.append("taxed in the \(pension.taxedIn) country")
        if let kind = pension.kind { facts.append("kind \(kind)") }
        if let country = pension.sourceCountry { facts.append("paid from \(country)") }
        var sentences = [facts.joined(separator: ", ") + "."]
        if !pension.options.isEmpty { sentences.append("Options: \(PlanDebugText.options(pension.options)).") }
        var lines = PlanDebugLines()
        if let seed = pension.startingBalanceFromAccounts {
            lines.add("Starting balance from accounts", .money(seed), note: "the accounts that hold its record")
        }
        if let claim = pension.claimed {
            lines.add("Claimed in", .number("\(claim.year)"), note: "at \(claim.age): \(claim.label) (\(claim.route))")
            if claim.startYear != claim.year { lines.add("Paid since", .number("\(claim.startYear)")) }
            lines.add("A year, gross", .money(claim.yearlyAmount))
            if let lumpSum = claim.lumpSum, lumpSum > 0 {
                lines.add("Lump sum", .money(lumpSum), note: claim.lumpSumWrapper.map { "into \($0)" })
            }
            if let growth = claim.realGrowthPerYear, growth != 0 {
                lines.add("Change a year, in real terms", .signedPercent(growth))
            }
        } else {
            sentences.append("Not claimed before the plan ends, retiring at this age.")
        }
        var table: PlanDebugTable?
        if !pension.offered.isEmpty {
            var offered = PlanDebugTableBuilder("pension-\(index)-options", [
                .label("Way to claim"), .text("Route"), .age(), .money("A year, gross", key: true),
                .money("Lump sum"), .percent("Real growth"), .text("Changes"), .text("Taken", key: true),
            ], titleColumns: [0])
            for option in pension.offered {
                offered.add([
                    .text(option.label), .text(option.route), .number("\(option.age)"),
                    .money(option.fullYearAmount ?? option.annualAmount), .amount(option.lumpSum),
                    option.realGrowthPerYear.map { PlanDebugValue.signedPercent($0) } ?? .missing,
                    .words(option.changes.map { "\(PlanDebugText.money($0.amount)) from \($0.age)" }
                        .joined(separator: ", ")),
                    .text(option.chosen ? "yes" : ""),
                ], isMarked: option.chosen)
            }
            table = offered.table
        }
        return PlanDebugBlock(id: "pension-\(index)", title: pension.name, sentences: sentences, lines: lines.lines,
                              table: table)
    }

    private static func assumptions(_ assumptions: PlanDebugReport.Assumptions) -> [PlanDebugBlock] {
        var lines = PlanDebugLines()
        lines.add("Inflation", .percent(assumptions.inflation), note: "a year")
        lines.add("Target mix: expected return", .percent(assumptions.portfolio.expectedReturn), note: "a year, real")
        lines.add("Target mix: volatility", .percent(assumptions.portfolio.volatility))
        lines.add("Target mix: median growth", .percent(assumptions.portfolio.medianReturn), note: "a year, real")
        var classes = PlanDebugTableBuilder("classes", [
            .label("Class"), .percent("Share today", key: true), .percent("Target share"),
            .percent("Expected return", key: true), .percent("Volatility", key: true), .percent("Median"),
            .percent("Income yield"), .percent("Portfolio median without"),
        ])
        for asset in assumptions.classes {
            classes.add([
                .text(PlanDebugText.className(asset.assetClass)), .percent(asset.share), .percent(asset.targetShare),
                .percent(asset.expectedReturn), .percent(asset.volatility, digits: 0), .percent(asset.medianReturn),
                .percent(asset.incomeYield), .rate(asset.portfolioMedianWithout),
            ])
        }
        var blocks = [PlanDebugBlock(
            id: "assumptions", title: "Assumptions",
            note: "A class's expected real return is the average year; its median is what a typical year gives, "
                + "lower the more volatile the class is. A portfolio rebalanced every year compounds at about its "
                + "median. “Target share” is the class's share of the mix the buckets are rebalanced to, and "
                + "“Portfolio median without” that mix's median growth with the class left out.",
            lines: lines.lines, table: classes.table)]
        if assumptions.correlationClasses.count > 1 {
            let names = assumptions.correlationClasses.map(PlanDebugText.className)
            var columns: [PlanDebugColumn] = [.label("")]
            columns += names.map { PlanDebugColumn.count($0) }
            var correlations = PlanDebugTableBuilder("correlations", columns)
            for (index, row) in assumptions.correlations.enumerated() where names.indices.contains(index) {
                var values: [PlanDebugValue] = [.text(names[index])]
                values += row.map { PlanDebugValue.number(String(format: "%.2f", $0)) }
                correlations.add(values)
            }
            blocks.append(PlanDebugBlock(id: "correlations", title: "Correlations",
                                         note: "Between the classes' yearly returns, as the simulation uses them.",
                                         table: correlations.table))
        }
        return blocks
    }

    // MARK: Starting portfolio

    private static func start(_ report: PlanDebugReport) -> [PlanDebugBlock] {
        let start = report.start
        var blocks: [PlanDebugBlock] = []
        let names = Dictionary(start.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let instruments = Dictionary(start.instruments.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        var lines = PlanDebugLines()
        lines.add("Valued on", .date(start.date))
        lines.add("Plan assets", .money(start.planAssets))
        if start.debtPaidOff > 0 {
            lines.add("Debts paid off at the start", .money(start.debtPaidOff), note: "from liquid money")
        }
        if let share = start.unrealizedGainShare {
            lines.add("Gain assumed where no cost is recorded", .percent(share, digits: 0), note: "of the value")
        }
        var sentences = ["Plan assets by class: \(PlanDebugText.mix(start.classShares))."]
        if !start.fxRates.isEmpty {
            sentences.append("Exchange rates used: " + start.fxRates.map {
                "1 \($0.from) = \(PlanDebugText.number($0.rate)) \($0.to)" + ($0.date.map { " (\($0))" } ?? "")
            }.joined(separator: "; ") + ".")
        }
        blocks.append(PlanDebugBlock(id: "summary", sentences: sentences, lines: lines.lines))

        var accounts = PlanDebugTableBuilder("accounts", [
            .label("Account"), .text("Kind"), .text("Currency"), .text("Wrapper"), .money("Value", key: true),
            .money("Cost basis"), .text("In the plan", key: true),
        ])
        for account in start.accounts {
            let status = switch account.outcome {
            case "included": "yes, bucket \(account.bucket ?? "")"
            case "schemeSeed": "no: \(account.reason ?? "it starts a pension scheme")"
            default: "no: \(account.reason ?? "left out")"
            }
            accounts.add([
                .text(account.name), .text(account.kind), .number(account.currency), .words(account.wrapper),
                .amount(account.value), .amount(account.costBasis), .text(status),
            ], isMarked: account.outcome == "included")
        }
        blocks.append(PlanDebugBlock(id: "accounts", title: "Accounts", table: accounts.table))

        let included = start.accounts.filter { $0.outcome == "included" && !$0.holdings.isEmpty }
        if !included.isEmpty {
            var lots = PlanDebugTableBuilder("lots", [
                .label("Account"), .label("Instrument"), .text("Class"), .text("Tax category"),
                .money("Value", key: true), .money("Cost basis", key: true), .text("Cost from"), .count("FX rate"),
            ], titleColumns: [0, 1])
            for account in included {
                for holding in account.holdings {
                    lots.add([
                        .text(account.name), .words(holding.instrument.map { instruments[$0] ?? $0 }),
                        .text(holding.assetClass), .text(holding.category), .money(holding.value),
                        holding.costBasis.map { PlanDebugValue.money($0) } ?? .text("unknown"), .text(holding.basisSource),
                        holding.fxRate.map { PlanDebugValue.number(PlanDebugText.number($0)) } ?? .missing,
                    ])
                }
            }
            blocks.append(PlanDebugBlock(
                id: "lots", title: "What they hold",
                note: "The plan's lots: each holding's value and purchase cost, and where the cost came from "
                    + "(recorded, estimated, unknown, or the value itself for cash).",
                table: lots.table))
        }

        if !start.instruments.isEmpty {
            var table = PlanDebugTableBuilder("instruments", [
                .label("Instrument"), .text("Kind"), .text("Fund type"), .text("Currency"),
                .text("Asset classes", key: true),
            ])
            for instrument in start.instruments {
                table.add([
                    .text(instrument.name), .text(instrument.kind), .words(instrument.fundType),
                    .number(instrument.currency), .text(PlanDebugText.mix(instrument.assetClasses)),
                ])
            }
            blocks.append(PlanDebugBlock(id: "instruments", title: "Instruments", table: table.table))
        }

        var buckets = PlanDebugTableBuilder("buckets", [
            .label("Bucket"), .text("Wrapper"), .text("Kind"), .money("Value", key: true), .money("Cost basis"),
            .text("Target mix"), .text("Can be drawn", key: true), .text("Accounts"),
        ])
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
            if let rate = bucket.growthTaxRate, rate > 0 {
                access += "; growth taxed at \(PlanDebugText.number((rate * 1000).rounded() / 10))%"
            }
            if let revaluation = bucket.revaluation { access += "; grows by \(revaluation), by law" }
            buckets.add([
                .text(bucket.name + (bucket.receivesSavings ? " (gets savings)" : "")), .text(bucket.wrapper),
                .text(bucket.liquid ? "liquid" : bucket.category), .money(bucket.value), .money(bucket.costBasis),
                .words(PlanDebugText.mix(bucket.targetMix)), .text(access),
                .words(bucket.accounts.map { names[$0] ?? $0 }.joined(separator: ", ")),
            ])
        }
        var seeds = PlanDebugLines()
        for seed in start.schemeSeeds {
            seeds.add("\(seed.name) (\(seed.scheme))", .money(seed.value),
                      note: (seed.accounts.map { names[$0] ?? $0 }.joined(separator: ", "))
                          + (seed.used ? ": its starting balance, not money the plan draws on"
                              : ": not used, the plan sets the starting balance itself"))
        }
        blocks.append(PlanDebugBlock(
            id: "buckets", title: "Buckets",
            note: "What the simulation draws from: liquid buckets any time, the others as their rules allow.",
            lines: seeds.lines, table: buckets.table))
        return blocks
    }

    // MARK: Schedule

    private static func schedule(_ report: PlanDebugReport) -> [PlanDebugBlock] {
        let years = report.schedule.years
        let retired = years.firstIndex { $0.workingShare < 1 }
        // The mix the ordinary accounts are rebalanced to, when it changes with age.
        let mixes = years.contains { $0.targetMix != nil }
        var table = PlanDebugTableBuilder("schedule", [
            .year(), .age(), .money("Work"), .money("Pensions"), .money("Windfalls"), .money("Contributions"),
            .money("Spending", key: true), .money("Expenses"), .money("Taxes"), .money("Net income"),
            .money("To draw", key: true),
        ] + (mixes ? [.text("Target mix")] : []) + [.text("Notes")], titleColumns: [0, 1], isSelectable: true)
        let buckets = bucketNames(report)
        for (index, year) in years.enumerated() {
            var notes: [String] = []
            if year.workingShare > 0, year.workingShare < 1 { notes.append("retires during the year") }
            if index == 0, year.fraction < 1 { notes.append("from the check-in") }
            notes += year.requiredPayouts.map { "pays out \(buckets[$0] ?? $0)" }
            notes += year.credits.map { "into \($0.label)" }
            let taxes: Double = (year.taxes + year.socialContributions).reduce(0) { $0 + $1.amount }
            let pensions: Double = year.pensions.reduce(0) { $0 + $1.amount }
            let windfalls: Double = year.windfalls.reduce(0) { $0 + $1.amount }
            let row: [PlanDebugValue] = [
                .number("\(year.year)"), .number("\(year.age)"), .money(year.work), .money(pensions), .money(windfalls),
                .money(year.contributions), .money(year.spending), .money(year.expenses), .money(taxes),
                .money(year.netIncome), .money(year.toDraw),
            ] + (mixes ? [year.targetMix.map { .text(PlanDebugText.mix($0)) } ?? .missing] : [])
                + [.text(notes.joined(separator: "; "))]
            table.add(row, isMarked: index == retired)
        }
        return [PlanDebugBlock(id: "schedule", table: table.table)]
    }

    /// The schedule's year at `index`, line by line.
    func scheduleDetail(_ index: Int) -> [PlanDebugBlock] {
        let years = report.schedule.years
        guard years.indices.contains(index) else { return [] }
        let year = years[index]
        let buckets = Self.bucketNames(report)
        var lines = PlanDebugLines()
        if year.fraction < 1 { lines.add("Share of the year simulated", .percent(year.fraction, digits: 0)) }
        lines.add("Share of it working", .percent(year.workingShare, digits: 0))
        lines.add("Work", .money(year.work), note: "gross")
        for pension in year.pensions { lines.add(pension.label, .money(pension.amount), note: "gross") }
        for windfall in year.windfalls { lines.add(windfall.label, .money(windfall.amount), note: "windfall") }
        if year.expenses != 0 { lines.add("Expenses", .money(year.expenses)) }
        lines.add("Contributions", .money(year.contributions), note: "into accounts and schemes")
        for credit in year.credits { lines.add("Into \(credit.label)", .money(credit.amount), note: "credited") }
        lines.add("Spending target", .money(year.spending))
        if let mix = year.targetMix {
            lines.add("Target mix", .text(PlanDebugText.mix(mix)), note: "the ordinary accounts are rebalanced to")
        }
        var taxes = PlanDebugLines()
        for tax in year.taxes { taxes.add(tax.label, .money(tax.amount), note: "tax") }
        for contribution in year.socialContributions {
            taxes.add(contribution.label, .money(contribution.amount), note: "contribution")
        }
        taxes.add("Net income", .money(year.netIncome), note: "work, pensions and windfalls after these")
        taxes.add("To draw", .money(year.toDraw), note: year.toDraw < 0 ? "saved" : "from the portfolio")
        var sentences: [String] = []
        if !year.requiredPayouts.isEmpty {
            sentences.append("Pays out, needed or not: "
                + PlanDebugText.list(year.requiredPayouts.map { buckets[$0] ?? $0 }) + ".")
        }
        if !year.accessible.isEmpty {
            sentences.append("Can be drawn from: " + PlanDebugText.list(year.accessible.map { buckets[$0] ?? $0 }) + ".")
        }
        return [
            PlanDebugBlock(id: "schedule-\(index)", title: "\(year.year) · age \(year.age)", lines: lines.lines),
            PlanDebugBlock(id: "schedule-\(index)-taxes", title: "Taxes and contributions on income",
                           note: "On work, pensions and windfalls, for the part of the year simulated. Taxes on "
                               + "sales, payouts and balances depend on each run: see the traced runs.",
                           sentences: sentences, lines: taxes.lines),
        ]
    }

    // MARK: Simulation summary

    private static func simulation(_ report: PlanDebugReport) -> [PlanDebugBlock] {
        let simulation = report.simulation
        let header = report.header
        let age = header.retirementAge
        var blocks: [PlanDebugBlock] = []

        var success = PlanDebugLines()
        success.add("Retiring today", .percent(simulation.successToday, digits: 0), note: "of futures succeed")
        success.add("Earliest age reaching \(Int(wholeNumber: header.confidence * 100))%",
                    simulation.earliestAge.map { PlanDebugValue.number("\($0)") } ?? .text("none before the plan ends"))
        if let target = simulation.targetAge {
            success.add("At the target age, \(target)", .rate(simulation.successAtTarget), note: "of futures succeed")
        }
        if let chosen = simulation.successAtChosenAge {
            success.add("Retiring at \(simulation.chosenAge), the age shown", .percent(chosen, digits: 1),
                        note: "of futures succeed")
        }
        var ages = PlanDebugTableBuilder("success", [.age(), .year(), .percent("Success", key: true)],
                                         titleColumns: [0])
        for point in simulation.successByAge {
            ages.add([.number("\(point.age)"), .number("\(point.year)"), .percent(point.success, digits: 0)],
                     id: point.age, isMarked: point.age == age)
        }
        blocks.append(PlanDebugBlock(id: "success", title: "Chance of success by retirement age",
                                     note: "Each age uses the same \(header.runs) random futures.",
                                     lines: success.lines, table: ages.table))

        if let search = simulation.sustainableSpending {
            var lines = PlanDebugLines()
            lines.add("The plan spends", .money(search.planSpending), note: "a year in retirement")
            if let perYear = search.perYear {
                lines.add("Highest that reaches the confidence level", .money(perYear), note: "a year")
                lines.add("Succeeding in", .rate(search.success), note: "of futures")
            } else {
                lines.add("Highest that reaches the confidence level", .text("none, not even no spending"))
            }
            var steps = PlanDebugTableBuilder("spending-steps", [
                .count("Step"), .money("Spending", key: true), .percent("Success", key: true),
            ])
            for (index, step) in search.steps.enumerated() {
                steps.add([.count(index + 1), .money(step.spending), .percent(step.success)])
            }
            blocks.append(PlanDebugBlock(
                id: "spending-search", title: "Sustainable spending, retiring at \(search.age)",
                note: "The highest yearly spending in retirement (before the plan's phases) that reaches the "
                    + "confidence level, found by halving the gap: each level tried, in order.",
                lines: lines.lines, table: steps.table))
        }

        if let search = simulation.assetsNeeded {
            var lines = PlanDebugLines()
            lines.add("Today's plan assets", .money(search.planAssets))
            if let accessible = search.accessible {
                lines.add("In accounts you can draw now", .money(accessible), note: "what the search adds to")
            }
            switch search.outcome {
            case "found":
                lines.add("Retiring today needs", .amount(search.amount),
                          note: search.scale.map { "\(PlanDebugText.times(($0 * 10).rounded() / 10)) today's" })
                if let extra = search.extra {
                    lines.add(extra >= 0 ? "Extra in accounts you can draw now" : "Could come out of them",
                              .money(abs(extra)))
                }
                lines.add("Succeeding in", .rate(search.success), note: "of futures")
                lines.add("Readiness", .rate(search.readiness, digits: 0), note: "of what's needed")
            case "moreThanMaximum":
                lines.add("Retiring today needs",
                          .text("more than \(PlanDebugText.number(search.maximumScale)) times today's"),
                          note: "the most the search tries")
            case "atMost":
                let lockedOnly = search.extra.flatMap { extra in search.accessible.map { extra <= -$0 * (1 - 1e-9) } }
                    ?? false
                lines.add("Retiring today needs at most", .amount(search.amount),
                          note: lockedOnly ? "what's locked away" : nil)
                lines.add("Readiness", .rate(search.readiness, digits: 0), note: "at least")
            default:
                lines.add("Retiring today needs", .text("nothing to compare: the plan counts no assets"))
            }
            var steps = PlanDebugTableBuilder("assets-steps", [
                .count("Step"), .money("Extra", key: true), .money("Plan assets", key: true), .count("Times today's"),
                .percent("Success", key: true),
            ])
            for (index, step) in search.steps.enumerated() {
                steps.add([.count(index + 1), .money(step.extra ?? (step.amount - search.planAssets)),
                           .money(step.amount), .number(PlanDebugText.times((step.scale * 1000).rounded() / 1000)),
                           .percent(step.success)])
            }
            blocks.append(PlanDebugBlock(
                id: "assets-search", title: "Assets needed to retire at \(search.age)",
                note: "Extra money goes only into the accounts you can draw now, at their target mix and with no "
                    + "unrealised gain; money locked in pension funds and the like stays as it is. When today's "
                    + "assets are more than enough, money comes out of those accounts instead. Doubling or halving "
                    + "from today's, then narrowing to within 1%, up to \(PlanDebugText.number(search.maximumScale)) "
                    + "times today's plan assets.",
                lines: lines.lines, table: steps.table))
        }

        let failures = simulation.failures
        var failureLines = PlanDebugLines()
        if abs(header.startScale - 1) > 1e-9 {
            failureLines.add("The runs start from", .money(header.startAssets), note: PlanDebugText.scale(report))
            failureLines.add("Success from there", .percent(simulation.successAtStartScale), note: "of runs")
        }
        var failureSentences: [String] = []
        var byAge: PlanDebugTable?
        if failures.failed == 0 {
            failureSentences.append("No run fails.")
        } else {
            failureLines.add("Runs that fail", .count(failures.failed), note: "of \(failures.runs)")
            failureLines.add("Failure rate", .percent(failures.failureRate, digits: 0))
            if let median = failures.medianFailureAge { failureLines.add("Median age they fail at", .number("\(median)")) }
            failureLines.add("Run out of money entirely", .count(failures.depleted))
            failureLines.add("Run out while money was locked", .count(failures.bridging),
                             note: "in a wrapper that would have bridged the gap")
            failureSentences += failures.bridges.map { bridge in
                "\(bridge.count) before \(bridge.name) (\(bridge.wrapper)) opens"
                    + (bridge.accessibleFromAge.map { " at \($0)" } ?? "") + "."
            }
            var table = PlanDebugTableBuilder("failures", [.age(), .count("Runs failing", key: true)])
            for point in failures.byAge {
                table.add([.number("\(point.age)"), .count(point.count)], id: point.age)
            }
            byAge = table.table
        }
        blocks.append(PlanDebugBlock(id: "failures", title: "Why runs fail, retiring at \(age)",
                                     sentences: failureSentences, lines: failureLines.lines, table: byAge))

        var outcomes = PlanDebugLines()
        let expected = simulation.expectedPath
        outcomes.add("Deterministic run", .text(outcome(expected, endAge: header.endAge)),
                     note: "median returns every year")
        outcomes.add("Left at the end", .money(expected.finalValue))
        let median = simulation.medianPath
        outcomes.add("Median run", .text(outcome(median, endAge: header.endAge)),
                     note: median.run.map { "run \($0)" })
        outcomes.add("Left at the end", .money(median.finalValue))
        if let gross = median.retiredGrossIncome {
            outcomes.add("Gross income in retirement", .money(gross), note: "pensions, windfalls, withdrawals, payouts")
        }
        if let taxes = median.retiredTaxes { outcomes.add("Taxes and contributions", .money(taxes)) }
        if let market = median.retiredMarketTaxes {
            outcomes.add("Of which on markets", .money(market), note: "sales, payouts, interest and wealth")
        }
        if let withdrawals = median.retiredWithdrawals { outcomes.add("Withdrawals and payouts", .money(withdrawals)) }
        blocks.append(PlanDebugBlock(id: "outcomes", title: "Two runs in brief",
                                     note: "The median run's totals are over the years fully retired.",
                                     lines: outcomes.lines))

        var checks: [String] = []
        if let reproduced = simulation.allRunsReproduced {
            checks.append(reproduced
                ? "Simulating every run again for the percentiles reproduced the main run's outcome for each."
                : "Simulating every run again did not reproduce every outcome of the main run: worth reporting.")
        }
        if let searched = simulation.searchSuccessAtStartScale {
            let same = abs(searched - simulation.successAtStartScale) <= 1e-9
            checks.append(same
                ? "At this scale, the search for the assets needed counted the same success as simulating every run."
                : "At this scale, the search for the assets needed counted a different success than simulating "
                    + "every run: it takes a run that succeeds with less money to succeed with more.")
        }
        let mismatched = report.paths.filter { !$0.matchesMainRun }.map(\.label)
        checks.append(mismatched.isEmpty
            ? "Every traced run ends exactly as the same run did untraced."
            : "These traced runs don't end as they did untraced: \(PlanDebugText.list(mismatched)). Worth reporting.")
        blocks.append(PlanDebugBlock(id: "checks", title: "Checks", sentences: checks))
        return blocks
    }

    /// "lasts to 95" or "runs out at 76 (2064)".
    private static func outcome(_ path: PlanDebugReport.PathOutcome, endAge: Int) -> String {
        guard path.failed else { return "lasts to \(endAge)" }
        return "runs out at \(path.failureAge.map(String.init) ?? "?")"
            + (path.failureYear.map { " (\($0))" } ?? "")
    }

    // MARK: Percentiles

    private static func percentiles(_ report: PlanDebugReport) -> [PlanDebugBlock] {
        let retirementYear = report.schedule.retirementDate.year
        var table = PlanDebugTableBuilder("percentiles", [
            .year(), .age(), .money("p10", key: true), .money("p25"), .money("Median", key: true), .money("p75"),
            .money("p90", key: true), .money("Deterministic"), .money("Withdrawals p10"),
            .money("Withdrawals median"), .money("Withdrawals p90"), .money("Taxes p10"), .money("Taxes median"),
            .money("Taxes p90"), .percent("Going"),
        ], titleColumns: [0, 1])
        for year in report.percentiles {
            table.add([
                .number("\(year.year)"), .number("\(year.age)"), .money(year.value.p10), .money(year.value.p25),
                .money(year.value.p50), .money(year.value.p75), .money(year.value.p90), .money(year.expected),
                .money(year.withdrawals.p10), .money(year.withdrawals.p50), .money(year.withdrawals.p90),
                .money(year.taxes.p10), .money(year.taxes.p50), .money(year.taxes.p90),
                .percent(year.going, digits: 0),
            ], isMarked: year.year == retirementYear)
        }
        var note = "Across all \(report.header.runs) runs"
        if let scale = PlanDebugText.scale(report) { note += ", starting from \(scale)" }
        note += ". “Deterministic” is the run with the median (typical) return every year; withdrawals (gross sales and "
            + "payouts) and taxes are among the runs still going, and “Going” is the share still meeting their "
            + "spending."
        return [PlanDebugBlock(id: "percentiles", note: note, table: table.table)]
    }

    // MARK: Traced runs

    private static func path(_ report: PlanDebugReport, _ index: Int) -> PlanDebugPath {
        let path = report.paths[index]
        let schedule = report.schedule.years
        let retired = schedule.firstIndex { $0.workingShare < 1 }
        var lines = PlanDebugLines()
        if let run = path.run {
            lines.add("Run", .number("\(run)"),
                      note: path.rank.map { "ranked \($0) of \(report.header.runs), from worst to best" })
        } else {
            lines.add("Run", .text("deterministic"), note: "the median return every year")
        }
        if path.failed {
            lines.add("Fails in", .number(path.failureYear.map(String.init) ?? "?"),
                      note: path.failureAge.map { "at \($0)" })
        } else {
            lines.add("Lasts to the end", .number("\(report.header.endAge)"))
        }
        lines.add("Left at the end", .money(path.finalValue))
        lines.add("Ends as the main run did", .text(path.matchesMainRun ? "yes" : "no"))

        let classes = path.classes.map(PlanDebugText.className)
        let failureIndex = path.failed ? path.years.indices.last : nil
        var columns: [PlanDebugColumn] = [.year(), .age()]
        columns += classes.map { PlanDebugColumn.percent($0) }
        columns += path.buckets.map { PlanDebugColumn.money($0.name) }
        columns.append(.money("Plan assets", key: true))
        // The mix the ordinary accounts are rebalanced to, when it changes with age.
        let mixes = path.years.contains { $0.targetMix != nil }
        if mixes { columns.append(.text("Target mix")) }
        var balances = PlanDebugTableBuilder("path-\(index)-balances", columns, titleColumns: [0, 1],
                                             isSelectable: true)
        var flows = PlanDebugTableBuilder("path-\(index)-flows", [
            .year(), .age(), .money("Net income"), .money("Payouts"), .money("Spending"), .money("Met", key: true),
            .money("Drawn", key: true), .money("Gains"), .money("Tax on income"), .money("Tax on markets", key: true),
            .money("Rebalanced"), .money("Saved"),
        ], titleColumns: [0, 1], isSelectable: true)
        for (y, year) in path.years.enumerated() {
            let marked = y == retired || y == failureIndex
            var balance: [PlanDebugValue] = [.number("\(year.year)"), .number("\(year.age)")]
            balance += year.returns.map { PlanDebugValue.signedPercent($0) }
            balance += year.buckets.map { PlanDebugValue.money($0.end) }
            balance.append(.money(year.endAssets))
            if mixes { balance.append(year.targetMix.map { .text(PlanDebugText.mix($0)) } ?? .missing) }
            balances.add(balance, id: y, isMarked: marked)
            let drawn: Double = year.buckets.reduce(0) { $0 + $1.withdrawn }
            let gains: Double = year.sales.reduce(0) { $0 + ($1.gain ?? 0) }
            let fixed: Double = year.taxes.reduce(0) { $0 + $1.fixed }
            let market: Double = year.taxes.reduce(0) { $0 + $1.market }
            let rebalanced: Double = year.buckets.reduce(0) { total, bucket in
                total + bucket.rebalancing.filter { $0 < 0 }.reduce(0, -)
            }
            let flow: [PlanDebugValue] = [
                .number("\(year.year)"), .number("\(year.age)"), .money(year.netIncome), .money(year.payoutsNet),
                .money(year.spendingTarget), .money(year.spendingMet), .money(drawn), .money(gains), .money(fixed),
                .money(market), .money(rebalanced), .money(max(0, year.cashFlow)),
            ]
            flows.add(flow, id: y, isMarked: marked)
        }
        let firstRetired = path.years.indices.first { schedule.indices.contains($0) && schedule[$0].workingShare == 0 }
        return PlanDebugPath(id: index, label: path.label, summary: lines.lines, failureReason: path.failureReason,
                             balances: balances.table, flows: flows.table,
                             defaultYear: firstRetired ?? path.years.indices.last)
    }

    /// The traced run `path`'s year at `index`, step by step: the returns
    /// drawn, the cash flow, each bucket, the sales, payouts, taxes and the
    /// failure.
    func pathDetail(_ path: Int, year index: Int) -> [PlanDebugBlock] {
        guard report.paths.indices.contains(path), report.paths[path].years.indices.contains(index) else { return [] }
        let traced = report.paths[path]
        let year = traced.years[index]
        let names = Self.bucketNames(report)
        let classes = traced.classes.map(PlanDebugText.className)
        let id = "path-\(path)-\(index)"
        var blocks: [PlanDebugBlock] = []

        var overview = PlanDebugLines()
        overview.add("Plan assets at the start", .money(year.startAssets))
        overview.add("At the end", .money(year.endAssets), note: "less taxes still to pay")
        for (name, value) in zip(classes, year.returns) {
            overview.add("Return on \(name.lowercased())", .signedPercent(value), note: "real")
        }
        if let mix = year.targetMix {
            overview.add("Target mix", .text(PlanDebugText.mix(mix)), note: "the ordinary accounts are rebalanced to")
        }
        var notes: [String] = []
        if year.fraction < 1 { notes.append("\(Int(wholeNumber: year.fraction * 100))% of the year simulated") }
        if year.failed { notes.append("the year the money runs out") }
        blocks.append(PlanDebugBlock(id: id, title: "\(year.year) · age \(year.age)",
                                     note: notes.isEmpty ? nil : notes.joined(separator: "; ").capitalizedFirst,
                                     lines: overview.lines))

        var flow = PlanDebugLines()
        flow.add("Net income", .money(year.netIncome), note: "work, pensions and windfalls after their taxes")
        flow.add("+ Payouts", .money(year.payoutsNet), note: "severance pay and required payouts, after their tax")
        flow.add("− Contributions", .money(year.contributions))
        flow.add("− Spending", .money(year.spending))
        flow.add("− Expenses", .money(year.expenses))
        flow.add("− Last year's taxes", .money(year.lastYearsTaxes), note: "on markets, paid now")
        flow.add("= Cash flow", .money(year.cashFlow), note: year.cashFlow < 0 ? "to draw" : "to invest")
        if year.shortfall > 0.005 { flow.add("Couldn't be raised", .money(year.shortfall)) }
        flow.add("Spending target", .money(year.spendingTarget))
        flow.add("Spending met", .money(year.spendingMet))
        blocks.append(PlanDebugBlock(id: id + "-flow", title: "Cash flow", lines: flow.lines))

        var buckets = PlanDebugTableBuilder(id + "-buckets", [
            .label("Bucket"), .money("Start"), .money("In"), .money("Required payouts"), .money("Withdrawn", key: true),
            .money("Rebalancing tax"), .money("Growth", key: true), .money("End", key: true), .money("Cost basis"),
        ])
        var moveColumns: [PlanDebugColumn] = [.label("Bucket")]
        moveColumns += classes.map { PlanDebugColumn.money($0) }
        var moves = PlanDebugTableBuilder(id + "-rebalancing", moveColumns)
        for (b, bucket) in year.buckets.enumerated() where bucket.start > 0.005 || bucket.end > 0.005 {
            let name = traced.buckets.indices.contains(b) ? traced.buckets[b].name : "Bucket \(b + 1)"
            buckets.add([
                .text(name), .money(bucket.start), .money(bucket.moneyIn), .money(bucket.requiredPayouts),
                .money(bucket.withdrawn), .money(bucket.rebalancingTax), .money(bucket.growth), .money(bucket.end),
                .money(bucket.endCostBasis),
            ], id: b)
            if bucket.rebalancing.contains(where: { abs($0) > 0.5 }) {
                var values: [PlanDebugValue] = [.text(name)]
                values += bucket.rebalancing.map { PlanDebugValue.money($0) }
                moves.add(values, id: b)
            }
        }
        blocks.append(PlanDebugBlock(id: id + "-buckets", title: "Buckets",
                                     note: "Money in is contributions, credits and savings; withdrawn is sold or paid "
                                         + "out for the year's need, gross; growth is the year's markets.",
                                     table: buckets.table))
        if !moves.table.rows.isEmpty {
            blocks.append(PlanDebugBlock(id: id + "-moves", title: "Rebalancing",
                                         note: "What each bucket bought (+) or sold (−) of each class to get back to "
                                             + "its target mix.",
                                         table: moves.table))
        }

        if !year.sales.isEmpty {
            var sales = PlanDebugTableBuilder(id + "-sales", [
                .label("From"), .text("Tax category"), .text("Purpose"), .money("Proceeds", key: true),
                .money("Cost basis"), .money("Gain", key: true),
            ])
            for sale in year.sales {
                sales.add([
                    .text(names[sale.wrapper] ?? sale.wrapper), .text(sale.category), .text(sale.purpose),
                    .money(sale.proceeds), sale.costBasis.map { PlanDebugValue.money($0) } ?? .text("unknown"), .amount(sale.gain),
                ])
            }
            blocks.append(PlanDebugBlock(id: id + "-sales", title: "Sales and gains",
                                         note: "A sale with an unknown cost leaves its gain to the tax system, which "
                                             + "may tax its whole value.",
                                         table: sales.table))
        }

        if !year.payouts.isEmpty {
            var payouts = PlanDebugTableBuilder(id + "-payouts", [
                .label("From"), .text("Purpose"), .text("Form"), .money("Amount", key: true), .money("Paid in"),
            ])
            for payout in year.payouts {
                payouts.add([
                    .text(names[payout.wrapper] ?? payout.wrapper), .text(payout.purpose), .text(payout.form),
                    .money(payout.amount), .amount(payout.costBasis),
                ])
            }
            blocks.append(PlanDebugBlock(id: id + "-payouts", title: "Payouts", table: payouts.table))
        }

        var withheld = PlanDebugLines()
        if year.withheldOnPayouts + year.withheldOnWithdrawals + year.withheldOnRebalancing > 0.005 {
            withheld.add("Withheld on required payouts", .money(year.withheldOnPayouts))
            withheld.add("Withheld on withdrawals", .money(year.withheldOnWithdrawals))
            withheld.add("Withheld on rebalancing", .money(year.withheldOnRebalancing))
        }
        withheld.add("Paid next year", .money(year.carriedToNextYear), note: "taxes on markets not withheld")
        var taxes = PlanDebugTableBuilder(id + "-taxes", [
            .label("Line"), .text("Kind"), .money("On income"), .money("On markets"), .money("Total", key: true),
        ])
        for tax in year.taxes {
            taxes.add([.text(tax.label), .text(tax.kind), .money(tax.fixed), .money(tax.market),
                       .money(tax.fixed + tax.market)])
        }
        blocks.append(PlanDebugBlock(
            id: id + "-taxes", title: "Taxes and contributions",
            note: "Every line, split into the part on work, pensions and windfalls (fixed by the schedule) and the "
                + "part on sales, payouts, interest and balances (which depends on the markets).",
            lines: withheld.lines, table: taxes.table.rows.isEmpty ? nil : taxes.table))

        if year.failed {
            blocks.append(PlanDebugBlock(id: id + "-failure", title: "The run fails",
                                         sentences: [traced.failureReason ?? "The money ran out."]))
        }
        return blocks
    }

    /// Bucket names by wrapper.
    private static func bucketNames(_ report: PlanDebugReport) -> [String: String] {
        Dictionary(report.start.buckets.map { ($0.wrapper, $0.name) }, uniquingKeysWith: { first, _ in first })
    }
}

/// A traced run, laid out: what it is, how it ends, and its years in two
/// tables (returns and balances; money in and out).
struct PlanDebugPath: Hashable, Sendable, Identifiable {
    var id: Int
    var label: String
    var summary: [PlanDebugLine]
    var failureReason: String?
    var balances: PlanDebugTable
    var flows: PlanDebugTable
    /// The year shown in detail at first: the first fully retired, else the last.
    var defaultYear: Int?
}

/// Which of a traced run's tables shows.
enum PlanDebugPathTable: String, CaseIterable, Hashable, Identifiable, Sendable {
    case balances
    case flows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balances: "Returns and balances"
        case .flows: "Money in and out"
        }
    }
}

/// A warning or an error of the run.
struct PlanDebugIssue: Hashable, Sendable, Identifiable {
    var id: Int
    var isError: Bool
    /// "Warning · it.tfr · 2031".
    var title: String
    var message: String
}

private extension String {
    /// The text with its first letter in upper case.
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
