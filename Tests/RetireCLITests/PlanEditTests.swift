import Foundation
import Model
import Planner
@testable import RetireCLI
import Testing
import TestSupport

/// `retire plan show`, `set`, `contribution` and `pension`: what the app's
/// plan editor changes, from the command line.
struct PlanEditTests {
    @Test func showListsThePlansInputs() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["plan", "show", "--library", library.path])
        #expect(run.status == 0, "\(run.all)")
        let lines = run.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.prefix(3) == ["Plan base: Base case", "Currency: EUR (the library's)",
                                    "Tax residence: it from 2026 (Italy)"])
        #expect(lines.contains("  1. INPS (it.inps) · claimed as early as possible"))
        #expect(lines.contains("  2. State pension from previous country (fixed) · 4,800 a year from 67"))
        #expect(lines.contains("  1. Fondo pensione (fondo-pensione) · 5,000 EUR a year until retirement"))
        // Each class's mean and median, whichever the plan gives. The base plan writes out the defaults of
        // earlier versions, which are marked, with the command that uses the current ones.
        #expect(lines.contains("  equity   4.5%    3.1%       17.0%             –  mean (previous default)"))
        #expect(lines.contains("  crypto  16.6%    0.0%       70.0%             –  median"))
        #expect(lines.contains("  The current defaults are medians of 5.0% for equity, 1.5% for bonds, 0.5% for cash, "
            + "1.0% for gold. To use them:"))
        #expect(lines.contains("  retire plan set --return equity=default --return bonds=default --return cash=default "
            + "--return gold=default"))

        let json = try parseJSON(await retire(["plan", "show", "--library", library.path, "--plan",
                                               "part-time-from-50", "--json"]).output)
        #expect(json["plan"] as? String == "part-time-from-50")
        #expect(json["currency"] as? String == "EUR")
        #expect(json["ownCurrency"] == nil)
        let returns = try #require(json["returns"] as? [String: [String: Any]])
        // The defaults, given by their median.
        #expect(returns["equity"]?["median"] as? String == "0.05" && returns["equity"]?["real"] as? String == "0.063334")
        #expect(returns["equity"]?["givenAs"] as? String == "median" && returns["equity"]?["isDefault"] as? Bool == true)
        #expect(returns["equity"]?["isPreviousDefault"] as? Bool == false)
        #expect(returns["crypto"]?["median"] as? String == "0" && returns["crypto"]?["real"] as? String == "0.16629")
        #expect(returns["crypto"]?["givenAs"] as? String == "median")
    }

    @Test func aPreviousDefaultGoesBackToTheCurrentOne() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let shown = try parseJSON(await retire(["plan", "show", "--library", library.path, "--json"]).output)
        let returns = try #require(shown["returns"] as? [String: [String: Any]])
        #expect(returns["bonds"]?["isPreviousDefault"] as? Bool == true && returns["bonds"]?["isDefault"] as? Bool == false)
        #expect(returns["crypto"]?["isPreviousDefault"] as? Bool == false)

        let run = await retire(["plan", "set", "--library", library.path, "--return", "equity=default"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasPrefix("Return of equity: median 5.0% (mean 6.3%) at 17.0% volatility, the default.\n"))
        let plan = try #require(try library.load().plans["base"])
        #expect(plan.assumptions.returns[.equity] == nil && plan.assumptions.returns[.bonds] != nil)
        let lines = await retire(["plan", "show", "--library", library.path]).output.split(separator: "\n").map(String.init)
        #expect(lines.contains("  equity   6.3%    5.0%       17.0%             –  median (default)"))
        #expect(lines.contains("  retire plan set --return bonds=default --return cash=default --return gold=default"))
    }

    @Test func setChangesAReturnByItsMeanOrItsMedian() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let plan = "part-time-from-50"
        let median = await retire(["plan", "set", "--library", library.path, "--plan", plan,
                                   "--median-return", "crypto=1%", "--volatility", "crypto=0.5"])
        #expect(median.status == 0, "\(median.all)")
        #expect(median.output.hasPrefix("Return of crypto: median 1.0% (mean 10.8%) at 50.0% volatility.\n"))
        let written = try library.text("plans/\(plan).json")
        // The median, and the mean it implies for older versions.
        #expect(written.contains(#""medianReal": "0.01""#) && written.contains(#""real": "0.108065""#), "\(written)")

        let mean = await retire(["plan", "set", "--library", library.path, "--plan", plan, "--return", "equity=5%"])
        #expect(mean.output.hasPrefix("Return of equity: mean 5.0% (median 3.7%) at 17.0% volatility.\n"))
        var assumptions = try #require(try library.load().plans[PlanID(plan)]).assumptions
        #expect(assumptions.returns[.equity] == ReturnAssumption(real: dec("0.05"), volatility: dec("0.17")))

        // Back to the defaults: nothing is left in the file.
        let back = await retire(["plan", "set", "--library", library.path, "--plan", plan,
                                 "--return", "equity=default", "--return", "crypto=default"])
        #expect(back.status == 0, "\(back.all)")
        #expect(back.output.contains("Return of crypto: median 0.0% (mean 16.6%) at 70.0% volatility, the default.\n"))
        assumptions = try #require(try library.load().plans[PlanID(plan)]).assumptions
        #expect(assumptions.returns.isEmpty)
        #expect(!(try library.text("plans/\(plan).json")).contains("assumptions"))

        let both = await retire(["plan", "set", "--library", library.path, "--return", "crypto=0.1",
                                 "--median-return", "crypto=0"])
        #expect(both.status == 64)
        #expect(both.errors.contains("not both"))
        let tooLow = await retire(["plan", "set", "--library", library.path, "--median-return", "crypto=-100%"])
        #expect(tooLow.status == 64)
    }

    @Test func setChangesTheCurrencyAndIncomeYields() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let run = await retire(["plan", "set", "--library", library.path, "--currency", "usd",
                                "--income-yield", "equity=2%", "--income-yield", "bonds=0.03"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.hasPrefix("Currency: USD.\nIncome yield of equity: 2.0%.\nIncome yield of bonds: 3.0%.\n"
            + "Wrote 1 file: plans/base.json.\n"))
        var plan = try #require(try library.load().plans["base"])
        #expect(plan.currency == .usd)
        #expect(plan.assumptions.returns[.equity]?.incomeYield == dec("0.02"))
        #expect(plan.assumptions.returns[.equity]?.real == dec("0.045"))
        #expect(plan.assumptions.returns[.bonds]?.incomeYield == dec("0.03"))
        #expect(try library.text("plans/base.json").contains(#""currency": "USD""#))
        #expect(try library.backups().count == 1)

        // Back to the library's currency, and no yield.
        let back = await retire(["plan", "set", "--library", library.path, "--currency", "library",
                                 "--income-yield", "equity=none"])
        #expect(back.status == 0, "\(back.all)")
        plan = try #require(try library.load().plans["base"])
        #expect(plan.currency == nil)
        #expect(plan.assumptions.returns[.equity]?.incomeYield == nil)

        // A currency without rates is written, with a note.
        let francs = await retire(["plan", "set", "--library", library.path, "--currency", "CHF"])
        #expect(francs.output.contains("Note: the library has no exchange rate between EUR and CHF, so the plan can't "
            + "value your accounts in CHF."))
        let validate = await retire(["validate", "--library", library.path])
        #expect(validate.output.contains("plans/base.json") && validate.output.contains("currency: the library has no "
            + "exchange rate between EUR and CHF"))

        let nothing = await retire(["plan", "set", "--library", library.path])
        #expect(nothing.status == 64)
        let badClass = await retire(["plan", "set", "--library", library.path, "--income-yield", "shares=0.02"])
        #expect(badClass.status == 64)
        #expect(badClass.errors.contains("isn't an asset class"))
        let tooMuch = await retire(["plan", "set", "--library", library.path, "--income-yield", "equity=150%"])
        #expect(tooMuch.status == 64)
    }

    @Test func setChoosesTheTargetMixAndHowItChangesWithAge() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let plan = "part-time-from-50"
        func set(_ arguments: [String]) async -> (status: Int32, output: String, errors: String, all: String) {
            let run = await retire(["plan", "set", "--library", library.path, "--plan", plan] + arguments)
            return (run.status, run.output, run.errors, run.all)
        }
        // The example plan's glide path: `show` puts today's mix next to the target and each change.
        let show = await retire(["plan", "show", "--library", library.path, "--plan", plan])
        let lines = show.output.split(separator: "\n").map(String.init)
        #expect(lines.contains("  Class   Ordinary today  All today  Target  From retirement  From 75  Median"))
        #expect(lines.contains("  equity             46%        44%     80%              60%      40%    3.1%"))
        #expect(lines.contains("  crypto             35%        28%       –                –        –    0.0%"))
        #expect(lines.contains("Today (2026-06-30): 120,058 EUR in the ordinary (taxable) accounts, 148,808 EUR in "
            + "all plan assets. Median: each class's typical real return a year."))
        #expect(lines.contains("Median growth, rebalanced every year: the target 2.9%; from retirement 2.5%; from 75 2.1%."))
        let json = try parseJSON(await retire(["plan", "show", "--library", library.path, "--plan", plan,
                                               "--json"]).output)
        let mix = try #require(json["assetMix"] as? [String: Any])
        #expect(mix["targetMix"] as? [String: String] == ["bonds": "0.2", "equity": "0.8"])
        let steps = try #require(mix["targetMixByAge"] as? [[String: Any]])
        #expect(steps.map { $0["fromAge"] as? String } == ["retirement", "75"])
        let today = try #require(mix["today"] as? [String: Any])
        #expect(today["ordinaryValue"] as? String == "120057.81" && today["allValue"] as? String == "148808.36")
        #expect((today["ordinary"] as? [String: String])?["crypto"] == "0.3468")

        // Back to today's mix: nothing about it is left in the file.
        let todays = await set(["--target-mix", "today"])
        #expect(todays.status == 0, "\(todays.all)")
        #expect(todays.output.hasPrefix("Target mix: today's. Each ordinary account is rebalanced back to its own mix "
            + "today.\nWrote 1 file: plans/part-time-from-50.json.\n"))
        #expect(!(try library.text("plans/\(plan).json")).contains("targetMix"))
        let bare = await retire(["plan", "show", "--library", library.path, "--plan", plan])
        #expect(bare.output.contains("Target: today's mix. Each year the plan rebalances every ordinary account back "
            + "to its own mix today; set a target with --target-mix."))

        // A glide path again.
        let glide = await set(["--target-mix", "equity=70%,bonds=30%",
                               "--target-mix-from", "retirement:equity=60%,bonds=40%",
                               "--target-mix-from", "80:equity=0.4,bonds=0.6"])
        #expect(glide.status == 0, "\(glide.all)")
        #expect(glide.output.hasPrefix("Target mix: equity 70%, bonds 30%.\nFrom retirement: equity 60%, bonds 40%.\n"
            + "From 80: bonds 60%, equity 40%.\nWrote 1 file: plans/part-time-from-50.json.\n"))
        var portfolio = try #require(try library.load().plans[PlanID(plan)]).portfolio
        #expect(portfolio.targetMix == [.equity: dec("0.7"), .bonds: dec("0.3")])
        #expect(portfolio.targetMixByAge == [
            TargetMixStep(fromAge: .retirement, mix: [.equity: dec("0.6"), .bonds: dec("0.4")]),
            TargetMixStep(fromAge: .age(80), mix: [.equity: dec("0.4"), .bonds: dec("0.6")]),
        ])
        #expect(try library.text("plans/\(plan).json")
            .contains(#"{ "fromAge": "retirement", "mix": { "bonds": "0.4", "equity": "0.6" } }"#))

        // The mix by repeated --target; the steps stay until they're removed.
        let repeated = await set(["--target", "equity=0.8", "--target", "bonds=0.2"])
        #expect(repeated.status == 0, "\(repeated.all)")
        portfolio = try #require(try library.load().plans[PlanID(plan)]).portfolio
        #expect(portfolio.targetMix == [.equity: dec("0.8"), .bonds: dec("0.2")] && portfolio.targetMixByAge.count == 2)
        let noSteps = await set(["--target-mix-from", "none"])
        #expect(noSteps.output.hasPrefix("Target mix by age: no changes.\n"))
        #expect(try #require(try library.load().plans[PlanID(plan)]).portfolio.targetMixByAge.isEmpty)

        // Mixes must add up to 100%, ages must go up, and classes must exist.
        let short = await set(["--target-mix", "equity=70%,bonds=20%"])
        #expect(short.status == 64)
        #expect(short.errors.contains("--target-mix: the mix adds up to 90%; it must add up to 100%."))
        let backwards = await set(["--target-mix-from", "75:bonds=1", "--target-mix-from", "60:bonds=1"])
        #expect(backwards.status == 64 && backwards.errors.contains("the ages must go up: 60 comes after 75."))
        let both = await set(["--target-mix", "equity=1", "--target", "equity=1"])
        #expect(both.status == 64 && both.errors.contains("not both"))
        let badClass = await set(["--target-mix", "shares=1"])
        #expect(badClass.status == 64 && badClass.errors.contains("isn't an asset class"))
        let badAge = await set(["--target-mix-from", "soon:bonds=1"])
        #expect(badAge.status == 64 && badAge.errors.contains("“soon” isn't an age or retirement."))
    }

    @Test func contributionsGoIntoAnAccountOrASchemeYearlyOrOnce() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let buyIn = await retire(["plan", "contribution", "add", "--library", library.path, "--pension", "it.inps",
                                  "--amount", "20000", "--year", "2030"])
        #expect(buyIn.status == 0, "\(buyIn.all)")
        #expect(buyIn.output.hasPrefix("Contribution 2: INPS (it.inps, pension scheme) · 20,000 EUR once in 2030.\n"))
        let yearly = await retire(["plan", "contribution", "add", "--library", library.path, "--account", "directa",
                                   "--per-year", "3000", "--until", "2035-12-31"])
        #expect(yearly.status == 0, "\(yearly.all)")
        #expect(yearly.output.hasPrefix("Contribution 3: Directa (directa) · 3,000 EUR a year until 2035-12-31.\n"))

        var plan = try #require(try library.load().plans["base"])
        #expect(plan.contributions.count == 3)
        #expect(plan.contributions[1] == PlanContribution(pension: "it.inps", amount: 20_000, year: 2030))
        #expect(plan.contributions[2] == PlanContribution(account: "directa", perYear: 3_000, until: .date("2035-12-31")))
        let file = try library.text("plans/base.json")
        #expect(file.contains(#"{ "amount": "20000", "pension": "it.inps", "year": 2030 }"#)
            || file.contains(#""pension": "it.inps""#))

        let removed = await retire(["plan", "contribution", "remove", "2", "--library", library.path])
        #expect(removed.status == 0, "\(removed.all)")
        #expect(removed.output.hasPrefix("Removed contribution 2: INPS (it.inps, pension scheme)"))
        plan = try #require(try library.load().plans["base"])
        #expect(plan.contributions.map(\.account) == ["fondo-pensione", "directa"])

        // Dry runs write nothing; mistakes say what's wrong.
        let before = try library.snapshot()
        let dry = await retire(["plan", "contribution", "add", "--library", library.path, "--account", "directa",
                                "--per-year", "100", "--dry-run"])
        #expect(dry.output.contains("Dry run: nothing was written (1 file would change)."))
        #expect(try library.snapshot() == before)
        let both = await retire(["plan", "contribution", "add", "--library", library.path, "--account", "directa",
                                 "--pension", "it.inps", "--per-year", "1"])
        #expect(both.status == 64)
        let noYear = await retire(["plan", "contribution", "add", "--library", library.path, "--account", "directa",
                                   "--amount", "1"])
        #expect(noYear.status == 64)
        #expect(noYear.errors.contains("A one-off --amount needs its --year."))
        let unknown = await retire(["plan", "contribution", "add", "--library", library.path, "--pension", "xx.fund",
                                    "--amount", "1", "--year", "2030"])
        #expect(unknown.status == 1)
        #expect(unknown.errors.contains("There's no pension scheme \"xx.fund\". Schemes: it.inps, ch.ahv, ch.bvg, de.drv."))
        let past = await retire(["plan", "contribution", "remove", "9", "--library", library.path])
        #expect(past.status == 1)
        #expect(past.errors.contains("There's no contribution 9: the plan has 2 contributions, numbered from 1."))
    }

    @Test func pensionsTakeAKindACountryAndAWayToClaim() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        let set = await retire(["plan", "pension", "set", "2", "--library", library.path, "--kind", "statutory",
                                "--source-country", "de"])
        #expect(set.status == 0, "\(set.all)")
        #expect(set.output.hasPrefix("Pension 2, State pension from previous country (fixed):\n"
            + "Kind: statutory (a state pension).\nPaying country: DE.\n"))
        var pension = try #require(try library.load().plans["base"]?.pensions[1])
        #expect(pension.kind == .statutory && pension.sourceCountry == "DE")

        let routes = await retire(["plan", "pension", "routes", "1", "--library", library.path])
        #expect(routes.status == 0, "\(routes.all)")
        #expect(routes.output.hasPrefix("Ways to claim pension 1, INPS (it.inps)\n"))
        #expect(routes.output.contains("it.inps."))
        let routesJSON = await retire(["plan", "pension", "routes", "1", "--library", library.path, "--json"])
        let first = try #require((try JSONSerialization.jsonObject(with: Data(routesJSON.output.utf8))
            as? [[String: Any]])?.first)
        let route = try #require(first["route"] as? String)

        let chosen = await retire(["plan", "pension", "set", "1", "--library", library.path, "--claim-route", route])
        #expect(chosen.status == 0, "\(chosen.all)")
        #expect(chosen.output.contains("Way to claim: \(route) ("))
        #expect(try library.load().plans["base"]?.pensions[0].claimRoute == route)

        // A route the scheme doesn't list is written, with a note and the planner's warning.
        let odd = await retire(["plan", "pension", "set", "1", "--library", library.path, "--claim-route",
                                "it.inps.nope"])
        #expect(odd.status == 0, "\(odd.all)")
        #expect(odd.output.contains("Note: the scheme doesn't list it with the pension's details as they are"))
        #expect(odd.output.contains("warning INPS (contributory system) never offers the claim route it.inps.nope"))
        let shown = await retire(["plan", "show", "--library", library.path])
        #expect(shown.output.contains("  1. INPS (it.inps) · claimed as early as possible · way to claim it.inps.nope"))
        #expect(shown.output.contains("kind statutory · paid from DE"))

        let cleared = await retire(["plan", "pension", "set", "1", "--library", library.path, "--claim-route",
                                    "default", "--kind", "none"])
        #expect(cleared.status == 0, "\(cleared.all)")
        pension = try #require(try library.load().plans["base"]?.pensions[0])
        #expect(pension.claimRoute == nil && pension.kind == nil)

        let badKind = await retire(["plan", "pension", "set", "1", "--library", library.path, "--kind", "public"])
        #expect(badKind.status == 64)
        #expect(badKind.errors.contains("--kind must be one of statutory, occupational, basicPension, privateAnnuity"))
    }

    @Test func aPensionTaxedWhereItsPaidSaysWhetherThePlanComputesThatTax() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        // No paying country: nothing to compute it with.
        let source = await retire(["plan", "pension", "set", "2", "--library", library.path, "--taxed-in", "source"])
        #expect(source.status == 0, "\(source.all)")
        #expect(source.output.contains(
            "Taxed where it's paid, in no country set: enter it after that tax.\n"))
        #expect(try library.load().plans["base"]?.pensions[1].taxedIn == .source)

        // A country with a registered system: its rules tax it.
        let italy = await retire(["plan", "pension", "set", "2", "--library", library.path, "--source-country", "IT"])
        #expect(italy.output.contains("Paying country: IT.\nTaxed where it's paid, by Italy's rules.\n"))
        // One without: the amount goes in after that tax, and the planner warns.
        let portugal = await retire(["plan", "pension", "set", "2", "--library", library.path, "--source-country", "PT"])
        #expect(portugal.output.contains("Taxed where it's paid, in PT, which has no tax rules yet: enter it after that tax."))
        #expect(portugal.output.contains("is taxed by the paying country, which the plan doesn't compute"))
        let shown = await retire(["plan", "show", "--library", library.path])
        #expect(shown.output.contains("4,800 a year from 67 · paid from PT · taxed where it's paid, in PT, which has no "
            + "tax rules yet"))

        // A scheme's pensions are paid from its system's country.
        let inps = await retire(["plan", "pension", "set", "1", "--library", library.path, "--taxed-in", "source"])
        #expect(inps.output.contains("Taxed where it's paid, by Italy's rules."))

        let back = await retire(["plan", "pension", "set", "2", "--library", library.path, "--taxed-in", "residence"])
        #expect(back.output.contains("Taxed where you live.\n"))
        #expect(try library.load().plans["base"]?.pensions[1].taxedIn == nil)
        let bad = await retire(["plan", "pension", "set", "2", "--library", library.path, "--taxed-in", "abroad"])
        #expect(bad.status == 64)
    }

    @Test func thePlanRunsInItsCurrencyAndSaysHowItReadTheLibrary() async throws {
        let library = try TemporaryFolder.exampleLibrary()
        _ = await retire(["plan", "set", "--library", library.path, "--currency", "USD"])
        let run = await retire(["plan", "--library", library.path, "--fast", "--years"])
        #expect(run.status == 0, "\(run.all)")
        #expect(run.output.contains("What you could spend: ") && run.output.contains(" USD a year in today's money"))
        #expect(run.output.contains("How the plan reads your library, on 2026-09-30 (USD)"))
        #expect(run.output.contains("  Ordinary account  "))
        #expect(run.output.contains("The median run, year by year (USD, today's money)"))
        #expect(run.output.contains("  Year  Age    Work  Pensions  Lump sums  Payouts"))

        let json = try parseJSON(await retire(["plan", "run", "--library", library.path, "--fast", "--json",
                                               "--years"]).output)
        #expect(json["currency"] as? String == "USD")
        let start = try #require(json["start"] as? [String: Any])
        let buckets = try #require(start["buckets"] as? [[String: Any]])
        #expect(buckets.contains { $0["wrapper"] as? String == "it.pensionFund" && $0["liquid"] as? Bool == false })
        let years = try #require(json["years"] as? [[String: Any]])
        #expect(years.first?["year"] as? Int == 2026)
        // The TFR is paid when the job ends: a payout by rule, not a withdrawal.
        #expect(years.contains { ($0["payouts"] as? String).map { $0 != "0" } == true })
    }

    @Test func yearRowsKeepLumpSumsAndRulePayoutsApart() {
        let registry = TaxSystems.registry()
        let detail = YearDetail(year: 2050, age: 62, startAssets: 0, endAssets: 100, spending: 30_000,
                                expenses: 1_000, income: [
                                    IncomeItem(kind: .pension, id: "pension-0", label: "INPS", amount: 10_000),
                                    IncomeItem(kind: .pension, id: "pension-0.lumpSum", label: "INPS (lump sum)",
                                               amount: 50_000),
                                    IncomeItem(kind: .payout, id: "it.tfr", label: "TFR", amount: 20_000),
                                    IncomeItem(kind: .payout, id: "it.pensionFund", label: "Pension fund",
                                               amount: 5_000),
                                    IncomeItem(kind: .withdrawal, id: "it.ordinary", label: "Ordinary", amount: 7_000),
                                ], taxes: [AmountItem(id: "irpef", label: "IRPEF", amount: 3_000)],
                                contributions: [AmountItem(id: "x", label: "X", amount: 500)])
        let row = PlanReport.YearRow.rows([detail], registry: registry)[0]
        #expect(row == PlanReport.YearRow(year: 2050, age: 62, work: 0, pensions: 10_000, lumpSums: 50_000,
                                          payouts: 20_000, drawn: 12_000, windfalls: 0, taxes: 3_500,
                                          spending: 31_000, endAssets: 100))
    }
}
