import Foundation
import Model
@testable import Planner
import TaxGeneric
import TaxItaly
import TaxKit
import Testing
import TestSupport

/// The plan debugger (PLANNER.md, "Plan debugger"): a run's every
/// calculation laid out, traced paths that reproduce the main run,
/// anonymization and the diagnosis.
struct PlanDebugTests {
    /// Born 1980-01-01, 45 on the start date: an equity brokerage account
    /// and a pension fund locked until 60, on the flat system with gains,
    /// wealth and income taxes.
    static let library = Sample.library(birth: "1980-01-01", on: "2025-12-31", [
        SampleAccount(id: "broker", balance: 400_000),
        SampleAccount(id: "fund", kind: .pensionFund, wrapper: "flat.pension", mix: [.equity: 0.6, .bonds: 0.4],
                      balance: 50_000),
    ])

    static let system: FlatTaxSystem = {
        var system = FlatTaxSystem()
        system.incomeRate = 0.25
        system.gainsRate = 0.26
        system.wealthRate = 0.002
        system.payoutRate = 0.15
        return system
    }()

    /// Work to 50, then 30,000 a year to 85, a pension from 67, a windfall and an expense.
    static func plan(runs: Int = 120) -> PlanDocument {
        Sample.plan(
            retire: .age(50), endAge: 85, working: "35000", retired: "30000", volatility: "0.17",
            work: [Sample.employee(from: "2026-01-01", gross: "70000")],
            pensions: [PlanPension(scheme: .fixed, name: "Statement pension", fromAge: 67, perYear: d("9000"))],
            events: [PlanEvent(name: "Gift from aunt", timing: .year(2040), amount: d("40000")),
                     PlanEvent(name: "Roof", timing: .age(58), amount: d("-15000"))],
            unrealizedGainShare: "0.3", runs: runs)
    }

    static let planner = PlannerOptions(maxRetirementAge: 55)

    func report(_ options: PlanDebugOptions, plan: PlanDocument = plan()) async throws -> PlanDebugReport {
        try await Planner.debugReport(for: plan, library: Self.library, registry: Sample.registry(Self.system),
                                      options: options)
    }

    // MARK: Traced paths

    @Test func tracedPathsReproduceTheMainRun() async throws {
        let report = try await report(PlanDebugOptions(planner: Self.planner, retirementAge: .target,
                                                       paths: .runs([0, 7, 42, 119, 500]), runDate: "2026-01-02"))
        #expect(report.header.retirementAge == 50)
        #expect(report.header.startScale == 1)
        // The deterministic run, then the runs asked for that exist.
        #expect(report.paths.map(\.kind) == ["expected", "chosen", "chosen", "chosen", "chosen"])
        #expect(report.paths.compactMap(\.run) == [0, 7, 42, 119])
        for path in report.paths {
            #expect(path.matchesMainRun, "\(path.label)")
            #expect(!path.years.isEmpty)
        }
        #expect(report.simulation.allRunsReproduced == true)
        #expect(!report.diagnosis.contains { $0.code.hasPrefix("check") })

        // Against an ordinary run at the same age: the same deterministic
        // path, the same fan, the same median run.
        let result = try await Planner.run(plan: Self.plan(), library: Self.library,
                                           registry: Sample.registry(Self.system), options: Self.planner)
        #expect(result.focusAge == 50)
        let expected = try #require(report.paths.first { $0.kind == "expected" })
        #expect(expected.years.count == result.expectedPath.years.count)
        for (traced, detail) in zip(expected.years, result.expectedPath.years) {
            #expect(abs(traced.endAssets - detail.endAssets) < 0.006, "\(traced.year)")
            #expect(traced.year == detail.year && traced.age == detail.age)
        }
        for (row, fan) in zip(report.percentiles, result.fan) {
            #expect(row.year == fan.year)
            #expect(abs(row.value.p10 - fan.p10) < 0.006 && abs(row.value.p50 - fan.p50) < 0.006
                && abs(row.value.p90 - fan.p90) < 0.006, "\(fan.year)")
            #expect(abs(row.expected - fan.expected) < 0.006)
        }
        #expect(report.simulation.successAtChosenAge == result.success(atAge: 50))
        #expect(report.simulation.successAtStartScale == result.success(atAge: 50))
        #expect(report.simulation.failures.failed == result.failures.failed)

        let automatic = try await self.report(PlanDebugOptions(planner: Self.planner, retirementAge: .target,
                                                               startScale: .actual))
        let median = try #require(automatic.paths.first { $0.kind == "median" })
        #expect(median.years.map(\.year) == result.medianPath.years.map(\.year))
        for (traced, detail) in zip(median.years, result.medianPath.years) {
            #expect(abs(traced.endAssets - detail.endAssets) < 0.006, "\(traced.year)")
            #expect(abs(traced.spendingTarget - (detail.spending + detail.expenses)) < 0.006)
            let taxes = traced.taxes.reduce(0) { $0 + $1.fixed + $1.market }
            #expect(abs(taxes - (detail.totalTax + detail.totalContributions)) < 0.05, "\(traced.year)")
        }
        #expect(median.failed == (result.medianPath.failure != nil))
        #expect(automatic.paths.allSatisfy { $0.matchesMainRun })
    }

    @Test func automaticPathsAreChosenByOutcome() async throws {
        let report = try await report(PlanDebugOptions(planner: Self.planner, retirementAge: .age(46),
                                                       startScale: .actual, paths: .automatic(count: 6)))
        #expect(report.header.retirementAge == 46)
        let kinds = report.paths.map(\.kind)
        #expect(kinds.first == "expected")
        #expect(Array(kinds.dropFirst().prefix(2)) == ["median", "p10"])
        let runs = report.paths.compactMap(\.run)
        #expect(Set(runs).count == runs.count)
        // Ranked from worst to best: the 10th percentile is worse than the median.
        let median = try #require(report.paths.first { $0.kind == "median" }?.rank)
        let p10 = try #require(report.paths.first { $0.kind == "p10" }?.rank)
        #expect(p10 < median)
        if report.simulation.failures.failed > 0 {
            #expect(kinds.contains("firstFailure"))
            let first = try #require(report.paths.first { $0.kind == "firstFailure" })
            #expect(first.failed && first.failureYear != nil && first.failureReason != nil)
        }
        // Each traced year adds up: start, money in and out, rebalancing tax and growth give the end.
        for path in report.paths {
            for year in path.years where !year.failed {
                for bucket in year.buckets {
                    let end = bucket.start + bucket.moneyIn - bucket.requiredPayouts - bucket.withdrawn
                        - bucket.rebalancingTax + bucket.growth
                    #expect(abs(end - bucket.end) < 0.05, "\(path.kind) \(year.year)")
                }
            }
        }
    }

    // MARK: Sections

    @Test func everySectionIsThere() async throws {
        let report = try await report(PlanDebugOptions(planner: Self.planner, runDate: "2026-01-02"))
        // Retiring today, at 45.
        #expect(report.header.retirementAge == 45 && report.header.retirementAgeChoice == "today")
        #expect(report.header.engine == Planner.engineVersion && report.header.runDate == "2026-01-02")
        #expect(report.header.runs == 120 && report.header.seed == 7 && report.header.endAge == 85)
        #expect(report.person.ageToday == 45 && report.person.birthDate == "1980-01-01")
        #expect(report.plan.work.count == 1 && report.plan.pensions.count == 1 && report.plan.events.count == 2)
        let pension = try #require(report.plan.pensions.first)
        #expect(pension.claimed?.age == 67 && pension.claimed?.yearlyAmount == 9000)
        #expect(pension.offered.contains { $0.chosen })
        #expect(report.start.accounts.map(\.id) == ["broker", "fund"])
        #expect(report.start.buckets.map(\.wrapper) == ["flat.ordinary", "flat.pension"])
        #expect(report.start.planAssets == 450_000)
        #expect(report.start.buckets.first { $0.wrapper == "flat.pension" }?.accessibleFromAge == 60)
        #expect(report.assumptions.classes.contains { $0.assetClass == "equity" && $0.expectedReturn == 0.05 })
        #expect(report.schedule.years.count == 2065 - 2026 + 1)
        #expect(report.simulation.successByAge.first?.age == 45)
        #expect(!(report.simulation.assetsNeeded?.steps.isEmpty ?? true))
        #expect(!(report.simulation.sustainableSpending?.steps.isEmpty ?? true))
        #expect(report.percentiles.count == report.schedule.years.count)
        #expect(report.paths.count == 1 + PlanDebugOptions.defaultPathCount
            || report.simulation.failures.failed == 0)
        #expect(!report.diagnosis.isEmpty)

        let markdown = report.markdown()
        for heading in ["# Plan debugger: Test plan", "## Diagnosis", "## 1. What was run",
                        "## 2. The person and the plan as read", "### Pensions", "### Assumptions",
                        "## 3. Starting portfolio", "## 4. Year-by-year schedule", "## 5. Simulation summary",
                        "### Sustainable spending", "### Assets needed to retire today", "## 6. Percentiles by year",
                        "## 7. Traced paths", "## 8. Issues"] {
            #expect(markdown.contains(heading + (heading.hasPrefix("# ") ? "" : "")), "\(heading)")
        }
        let json = try JSONSerialization.jsonObject(with: Data(report.json().utf8)) as? [String: Any]
        #expect(Set(json?.keys.map { $0 } ?? []) == ["header", "diagnosis", "person", "plan", "assumptions", "start",
                                                      "schedule", "simulation", "percentiles", "paths", "issues"])
    }

    @Test func longPlansKeepTheMarkdownShort() async throws {
        var plan = Self.plan(runs: 40)
        plan.endAge = 100
        let report = try await report(PlanDebugOptions(planner: Self.planner, retirementAge: .target,
                                                       paths: .automatic(count: 1)), plan: plan)
        #expect(report.schedule.years.count == 2080 - 2026 + 1)
        // Every year is in the JSON; the Markdown's schedule skips some.
        let markdown = report.markdown()
        let schedule = markdown.components(separatedBy: "## 4.")[1].components(separatedBy: "## 5.")[0]
        let rows = schedule.split(separator: "\n").filter { $0.hasPrefix("| 20") }
        #expect(rows.count < 40 && rows.count > 15)
        #expect(schedule.contains("| … |"))
        // The years around retirement (2030) are all there.
        for year in 2029...2031 { #expect(schedule.contains("| \(year) |")) }
    }

    @Test func theScheduleMatchesTheResultsYears() async throws {
        let report = try await report(PlanDebugOptions(planner: Self.planner, retirementAge: .target))
        let result = try await Planner.run(plan: Self.plan(), library: Self.library,
                                           registry: Sample.registry(Self.system), options: Self.planner)
        // The schedule has every year; the deterministic run (median returns) stops when its money runs out.
        let years = result.expectedPath.years
        #expect(!years.isEmpty && report.schedule.years.count >= years.count)
        for (row, detail) in zip(report.schedule.years, years) {
            #expect(row.year == detail.year && row.age == detail.age)
            let work = detail.income.filter { $0.kind == .work }.reduce(0) { $0 + $1.amount }
            let pensions = detail.income.filter { $0.kind == .pension }.reduce(0) { $0 + $1.amount }
            let windfalls = detail.income.filter { $0.kind == .windfall }.reduce(0) { $0 + $1.amount }
            #expect(abs(row.work - work) < 0.006, "\(row.year)")
            #expect(abs(row.pensions.reduce(0) { $0 + $1.amount } - pensions) < 0.006, "\(row.year)")
            #expect(abs(row.windfalls.reduce(0) { $0 + $1.amount } - windfalls) < 0.006, "\(row.year)")
            #expect(abs(row.spending - detail.spending) < 0.006, "\(row.year)")
            #expect(abs(row.expenses - detail.expenses) < 0.006, "\(row.year)")
            // The fixed taxes are the year's taxes less what the markets add.
            let fixed = (row.taxes + row.socialContributions).reduce(0) { $0 + $1.amount }
            #expect(fixed <= detail.totalTax + detail.totalContributions + 0.01, "\(row.year)")
        }
        // Work stops at 50 (2030), the windfall is in 2040, the roof at 58, the pension from 67.
        #expect(report.schedule.years.first { $0.year == 2031 }?.work == 0)
        #expect(report.schedule.years.first { $0.year == 2029 }.map { $0.work > 0 } == true)
        #expect(report.schedule.years.first { $0.year == 2040 }?.windfalls.first?.amount == 40_000)
        #expect(report.schedule.years.first { $0.age == 58 }?.expenses == 15_000)
        #expect(report.schedule.years.first { $0.age == 67 }?.pensions.first?.amount == 9000)
    }

    @Test func aScaledStartTracesTheRunsFromMoreMoney() async throws {
        let report = try await report(PlanDebugOptions(planner: Self.planner, startScale: .factor(2)))
        #expect(report.header.startScale == 2 && report.header.startScaleChoice == "factor")
        #expect(report.header.startAssets == 900_000)
        #expect(report.simulation.allRunsReproduced == nil)
        for path in report.paths {
            #expect(path.matchesMainRun, "\(path.label)")
            #expect(path.years.first.map { abs($0.startAssets - 900_000) < 0.01 } == true)
        }
        #expect(report.diagnosis.contains { $0.code == "scale" })
        // Today's portfolio is still today's.
        #expect(report.start.planAssets == 450_000)
    }

    @Test func retiringTodayStartsFromWhatItNeeds() async throws {
        let report = try await report(PlanDebugOptions(planner: Self.planner))
        let needed = try #require(report.simulation.assetsNeeded)
        #expect(needed.outcome == "found")
        let scale = try #require(needed.scale)
        #expect(scale > 1)
        #expect(report.header.startScaleChoice == "assetsNeeded")
        #expect(abs(report.header.startScale - scale) < 1e-6)
        // The search counted the same success at that scale as simulating every run gives.
        #expect(report.simulation.searchSuccessAtStartScale == report.simulation.successAtStartScale)
        #expect(report.simulation.successAtStartScale >= report.header.confidence)

        // The runs start from today's portfolio with the extra money in the
        // broker account, the one that can be drawn now; the pension fund
        // keeps its 50,000.
        let extra = try #require(needed.extra)
        #expect(report.header.startExtra == extra && extra > 0)
        #expect(needed.accessible == 400_000)
        #expect(abs(report.header.startAssets - (450_000 + extra)) < 0.01)
        #expect(needed.steps.first?.extra == 0 && needed.steps.allSatisfy { $0.extra != nil })
        for path in report.paths {
            #expect(path.matchesMainRun, "\(path.label)")
            let first = try #require(path.years.first)
            #expect(abs(first.startAssets - (450_000 + extra)) < 0.01)
            let fund = try #require(path.buckets.firstIndex { $0.wrapper == "flat.pension" })
            #expect(abs(first.buckets[fund].start - 50_000) < 0.01)
        }
        let markdown = report.markdown()
        #expect(markdown.contains("| Step | Extra | Plan assets | Times today's | Success |"))
        #expect(report.diagnosis.contains { $0.code == "assets.needed"
            && $0.text.contains("added to the accounts that can be drawn now") })
    }

    // MARK: Anonymization

    @Test func anonymizingRemovesEveryNameAndID() async throws {
        let library = try Fixtures.exampleLibrary()
        let plan = try #require(library.plans["base"])
        let options = PlanDebugOptions(
            planner: PlannerOptions(mode: .fast(runs: 24), maxRetirementAge: 45, solveSustainableSpending: false),
            paths: .automatic(count: 2))
        let registry = TaxRegistry([ItalyTaxSystem(), GenericTaxSystem()])
        let report = try await Planner.debugReport(for: plan, library: library, registry: registry, options: options)
        let anonymized = report.anonymized()

        // Every name and ID of the example library's accounts, instruments,
        // plans, pensions and events, the person and the institutions…
        var originals: [String] = [library.settings.person?.name ?? "", "1988-04-12"]
        for account in library.accounts.values {
            originals += [account.id.rawValue, account.name] + [account.institution].compactMap { $0 }
        }
        for instrument in library.instruments.values {
            originals += [instrument.id.rawValue, instrument.name] + [instrument.isin, instrument.ticker].compactMap { $0 }
        }
        for plan in library.plans.values {
            originals += [plan.id.rawValue, plan.name] + plan.pensions.compactMap(\.name) + plan.events.map(\.name)
        }
        // …except those that are also a tax system's or the planner's own
        // words: the TFR account is named like the `it.tfr` wrapper and has
        // the kind `tfr`, the gold instrument's ID is an asset class, and the
        // inheritance an event kind.
        let vocabulary: Set<String> = ["tfr", "gold", "inheritance"]
        let checked = Set(originals.filter { !$0.isEmpty && !vocabulary.contains($0.lowercased()) })
        #expect(checked.count > 25)

        let json = try anonymized.json()
        let markdown = anonymized.markdown()
        for original in checked.sorted() {
            #expect(!PlanDebugAnonymizer.containsWord(original, in: json), "\(original) in the JSON")
            #expect(!PlanDebugAnonymizer.containsWord(original, in: markdown), "\(original) in the Markdown")
        }
        // The plain report has them, so the search above finds what it looks for.
        let plain = try report.json() + report.markdown()
        #expect(PlanDebugAnonymizer.containsWord("ledger-wallet", in: plain))
        #expect(PlanDebugAnonymizer.containsWord("Base case", in: plain))
        #expect(PlanDebugAnonymizer.containsWord("Vanguard FTSE All-World UCITS ETF (Acc)", in: plain))

        // Labels instead, the birth date gone, money rounded, the note in the header.
        #expect(anonymized.header.planID == "plan" && anonymized.header.planName == "Plan")
        #expect(anonymized.person.birthDate == nil && anonymized.person.ageToday == 38)
        #expect(anonymized.start.accounts.allSatisfy { $0.id.hasPrefix("account-") && $0.name.hasPrefix("Account ") })
        #expect(anonymized.start.accounts.contains { $0.name.hasPrefix("Account") && $0.name.contains("(ordinary, ") })
        #expect(anonymized.start.instruments.contains { $0.name.contains("(ETF, equity fund)") })
        #expect(anonymized.plan.pensions.map(\.name) == ["Pension 1 (statutory)", "Pension 2 (fixed)"])
        #expect(anonymized.plan.events.map(\.name) == ["Event 1 (inheritance)", "Event 2 (expense)"])
        #expect(anonymized.issues.contains { $0.message.hasPrefix("Account 10 (tfr, cash) has no asset mix") })
        #expect(anonymized.header.anonymization?.rounding == "3sig")
        #expect(markdown.contains("**Anonymized.**"))
        #expect(Self.significantFigures(anonymized.start.planAssets) <= 3)
        #expect(anonymized.percentiles.allSatisfy { Self.significantFigures($0.value.p50) <= 3 })
        // What the reasoning needs stays: rates, years, tax options.
        #expect(anonymized.assumptions == report.assumptions)
        #expect(anonymized.plan.residence == report.plan.residence)
        #expect(anonymized.schedule.years.map(\.year) == report.schedule.years.map(\.year))
    }

    @Test func roundingMoney() {
        let sig = PlanDebugAnonymization(rounding: .significantFigures)
        #expect(sig.round(161_505.12) == 162_000)
        #expect(sig.round(-4_826) == -4_830)
        #expect(sig.round(0.12345) == 0.123)
        #expect(sig.round(0) == 0)
        let hundreds = PlanDebugAnonymization(rounding: .hundreds)
        #expect(hundreds.round(161_549) == 161_500 && hundreds.round(49.9) == 0)
        #expect(PlanDebugAnonymization(rounding: .none).round(12.345) == 12.345)
    }

    @Test func wholeWordsOnly() {
        let table = [("tfr", "account-10"), ("Directa", "Account 3 (ordinary, equity)")]
        #expect(PlanDebugAnonymizer.replace(in: "tfr, it.tfr and TFR.", table)
            == "account-10, it.tfr and account-10.")
        #expect(PlanDebugAnonymizer.replace(in: "directa-movimenti and Directa", table)
            == "directa-movimenti and Account 3 (ordinary, equity)")
        #expect(PlanDebugAnonymizer.containsWord("tfr", in: "it.tfr") == false)
        #expect(PlanDebugAnonymizer.containsWord("base", in: "the base case") == true)
        #expect(PlanDebugAnonymizer.containsWord("base", in: "baseline") == false)
    }

    /// The significant figures of a whole amount.
    static func significantFigures(_ value: Double) -> Int {
        var digits = String(Int(abs(value).rounded()))
        while digits.hasSuffix("0"), digits.count > 1 { digits.removeLast() }
        return digits == "0" ? 0 : digits.count
    }

    // MARK: Diagnosis

    /// 60,000 in equity and 40,000 in crypto, retiring today on 4,000 a year.
    func cryptoPlan() -> (PlanDocument, Library) {
        let library = Sample.library(birth: "1980-01-01", on: "2025-12-31", [
            SampleAccount(id: "broker", balance: 60_000),
            SampleAccount(id: "wallet", kind: .crypto, mix: [.crypto: 1], balance: 40_000),
        ])
        var plan = Sample.plan(retire: .age(45), endAge: 75, retired: "4000", runs: 60)
        plan.assumptions.returns[.equity] = ReturnAssumption(real: d("0.045"), volatility: d("0.17"))
        plan.assumptions.returns[.crypto] = ReturnAssumption(real: 0, volatility: d("0.7"))
        plan.assumptions.correlations = CorrelationTable([.equity: [.crypto: d("0.4")]])
        return (plan, library)
    }

    @Test func theDiagnosisNamesALargeCryptoShare() async throws {
        let (plan, library) = cryptoPlan()
        let report = try await Planner.debugReport(
            for: plan, library: library, registry: Sample.registry(),
            options: PlanDebugOptions(planner: PlannerOptions(maxRetirementAge: 46, solveSustainableSpending: false),
                                      startScale: .actual))
        let crypto = try #require(report.assumptions.classes.first { $0.assetClass == "crypto" })
        #expect(abs(crypto.share - 0.4) < 1e-9 && abs(crypto.targetShare - 0.4) < 1e-9)
        #expect(abs(crypto.medianReturn - (1 / 1.49.squareRoot() - 1)) < 1e-9)
        let without = try #require(crypto.portfolioMedianWithout)
        #expect(without > report.assumptions.portfolio.medianReturn + 0.02)

        let drag = try #require(report.diagnosis.first { $0.code == "mix.drag" })
        #expect(drag.text.hasPrefix("Crypto is 40% of plan assets; at 0.0% expected real return and 70% volatility"))
        #expect(drag.text.contains("lowers the portfolio's median growth from \(PlanDebugFormat.percent(without)) to "
            + "\(PlanDebugFormat.percent(report.assumptions.portfolio.medianReturn)) a year"))
        #expect(report.diagnosis.contains { $0.code == "horizon" && $0.text.contains("30 years of retirement") })
        #expect(report.diagnosis.contains { $0.code == "pension.none" })
        // Only the volatile class is named, not equity.
        #expect(report.diagnosis.filter { $0.code == "mix.drag" }.count == 1)
        #expect(report.markdown().contains("- " + drag.text))
    }

    @Test func aTargetMixWithoutCryptoIsNoDrag() async throws {
        var (plan, library) = cryptoPlan()
        plan.portfolio.targetMix = [.equity: 1]
        let report = try await Planner.debugReport(
            for: plan, library: library, registry: Sample.registry(),
            options: PlanDebugOptions(planner: PlannerOptions(maxRetirementAge: 46, solveSustainableSpending: false),
                                      startScale: .actual))
        #expect(!report.diagnosis.contains { $0.code == "mix.drag" })
        let sold = try #require(report.diagnosis.first { $0.code == "mix.sold" })
        #expect(sold.text.hasPrefix("Crypto is 40% of plan assets today, but 0% of the mix the buckets are rebalanced to"))
    }

    // MARK: JSON

    @Test func theJSONRoundTrips() async throws {
        let report = try await report(PlanDebugOptions(planner: Self.planner, paths: .automatic(count: 2)))
        let json = try report.json()
        let decoded = try PlanDebugReport.decode(json: json)
        #expect(decoded == report)
        #expect(try decoded.json() == json)
        let anonymized = report.anonymized(PlanDebugAnonymization(rounding: .hundreds))
        #expect(try PlanDebugReport.decode(json: anonymized.json()) == anonymized)
        // Keys are sorted, so the same report always reads the same.
        #expect(json.range(of: "\"assumptions\"")!.lowerBound < json.range(of: "\"diagnosis\"")!.lowerBound)
    }
}
