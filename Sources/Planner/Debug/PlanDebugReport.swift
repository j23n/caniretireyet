import Foundation
import Model

/// Everything one run of a plan computed, laid out so a person can follow
/// the reasoning without reading code (PLANNER.md, "Plan debugger"): how
/// the plan and the library were read, the assumptions, the year-by-year
/// schedule, the searches, percentiles, a few paths traced step by step,
/// and a short diagnosis of what weighs on the result.
///
/// Made by ``Planner/debugReport(for:library:registry:options:)``;
/// ``anonymized(_:)`` removes names and IDs for sharing; ``json()`` and
/// ``markdown()`` render it. Amounts are yearly, in today's money in the
/// plan's currency (``Header/currency``); returns, shares and rates are
/// fractions (0.045 is 4.5%).
public struct PlanDebugReport: Codable, Hashable, Sendable {
    public var header: Header
    /// The biggest drags on the result, in plain words, derived from the
    /// rest of the report (``PlanDebugDiagnosis``).
    public var diagnosis: [Finding]
    public var person: Person
    public var plan: PlanReading
    public var assumptions: Assumptions
    public var start: StartingPortfolio
    public var schedule: Schedule
    public var simulation: Simulation
    /// Per year at the chosen retirement age, across every run.
    public var percentiles: [PercentileYear]
    public var paths: [TracedPath]
    /// Warnings from the plan, the tax systems and the years assessed.
    public var issues: [Issue]
}

extension PlanDebugReport {
    // MARK: Header

    /// What was run, and how.
    public struct Header: Codable, Hashable, Sendable {
        /// ``Planner/engineVersion``.
        public var engine: String
        /// The day the report was made.
        public var runDate: CalendarDate
        public var planID: String
        public var planName: String
        public var currency: String
        /// The check-in the plan starts from.
        public var startDate: CalendarDate
        public var runs: Int
        /// Whether the run used fewer runs than the plan asks for.
        public var fast: Bool
        public var seed: UInt64
        public var confidence: Double
        public var endAge: Int
        /// The newest tax-parameter year used per tax system.
        public var taxParameters: [String: Int]
        /// The retirement age the schedule, percentiles and paths are for.
        public var retirementAge: Int
        /// How it was chosen: `today`, `target` or `age`.
        public var retirementAgeChoice: String
        /// The plan assets the percentiles, failures and traced paths start
        /// from, as a multiple of today's (1: today's).
        public var startScale: Double
        /// How it was chosen: `actual`, `assetsNeeded` (today's portfolio
        /// with ``startExtra`` in the accessible buckets) or `factor` (every
        /// holding multiplied by ``startScale``).
        public var startScaleChoice: String
        /// The plan assets they start from: today's times ``startScale``.
        public var startAssets: Double
        /// What was anonymized; `nil` when nothing was.
        public var anonymization: AnonymizationNote?
        /// For `assetsNeeded`: the extra money in the buckets that can be
        /// drawn at any age (negative: taken out of them), as the search
        /// for the assets needed adds it. `nil` otherwise.
        public var startExtra: Double? = nil
    }

    /// What ``PlanDebugReport/anonymized(_:)`` changed.
    public struct AnonymizationNote: Codable, Hashable, Sendable {
        /// ``PlanDebugAnonymization/Rounding`` raw value.
        public var rounding: String
        public var notes: [String]
    }

    /// One line of the diagnosis.
    public struct Finding: Codable, Hashable, Sendable {
        /// Stable, e.g. `mix.drag`, `pension.gap`, `horizon`.
        public var code: String
        public var text: String
    }

    // MARK: The person and the plan as read

    public struct Person: Codable, Hashable, Sendable {
        /// `nil` when anonymized (ages and calendar years stay).
        public var birthDate: CalendarDate?
        public var ageToday: Int
        public var citizenships: [String]
        public var taxResidence: String?
        /// The plan's `retirement.age` as written: an age or `earliest`.
        public var retirementSetting: String
        /// The plan's age, or the earliest age found.
        public var targetAge: Int?
        /// The earliest age reaching the confidence level, if any does.
        public var earliestAge: Int?
        /// The age the details are for (``Header/retirementAge``).
        public var chosenAge: Int
        /// The day work stops at that age.
        public var retirementDate: CalendarDate
        public var endAge: Int
        public var firstYear: Int
        public var lastYear: Int
    }

    /// The plan's sections as the engine read them.
    public struct PlanReading: Codable, Hashable, Sendable {
        public var residence: [Residence]
        public var overlays: [Overlay]
        public var indexThresholds: Bool
        public var overrides: [String: JSONValue]
        public var work: [Work]
        public var spending: Spending
        public var pensions: [Pension]
        public var contributions: [Contribution]
        public var events: [Event]
        public var withdrawals: Withdrawals
        /// How fees enter the plan.
        public var fees: String
        /// The mix the ordinary (taxable) accounts are rebalanced to, as the
        /// plan chooses it; `nil` when it doesn't (each keeps its mix at the start).
        public var targetMix: TargetMixPlan? = nil
    }

    /// The plan's target mix (`portfolio.targetMix`) and its changes with
    /// age (`portfolio.targetMixByAge`), as the engine read them.
    public struct TargetMixPlan: Codable, Hashable, Sendable {
        /// `targetMix`, scaled to sum to 1: the mix from the start until a
        /// step starts. `nil`: until then each ordinary account keeps its mix.
        public var mix: [String: Double]?
        /// That mix rebalanced every year; `nil` without one.
        public var growth: Growth?
        /// The changes with age, in the plan's order.
        public var steps: [TargetMixStepReading]
    }

    /// One change of the target mix with age.
    public struct TargetMixStepReading: Codable, Hashable, Sendable {
        /// `fromAge` as written: an age or `retirement`.
        public var fromAge: String
        /// The age it starts at when retiring at the chosen age.
        public var startAge: Int?
        /// Whether it's in force in some year at the chosen age: a step that
        /// a later one overtakes, or that starts after the plan's end, never is.
        public var applies: Bool
        /// Scaled to sum to 1.
        public var mix: [String: Double]
        /// The mix rebalanced every year.
        public var growth: Growth
    }

    public struct Residence: Codable, Hashable, Sendable {
        public var from: Int
        public var system: String
        public var systemName: String
        /// The currency the system computes in, when it has its own.
        public var systemCurrency: String?
        /// Units of that currency per unit of the plan's (1 without one).
        public var currencyRate: Double
        public var options: [String: JSONValue]
    }

    public struct Overlay: Codable, Hashable, Sendable {
        public var regime: String
        public var name: String
        public var options: [String: JSONValue]
    }

    public struct Work: Codable, Hashable, Sendable {
        /// `work-<index>`.
        public var id: String
        public var label: String
        /// `employee`, `selfEmployed` or `net`.
        public var kind: String
        /// The regime as written (`nil`: the system's default).
        public var regime: String?
        public var from: CalendarDate
        /// The last working day at the chosen retirement age.
        public var lastDay: CalendarDate
        /// `until` as written: a date or `retirement`.
        public var until: String
        /// Gross salary or revenue a year, in the first year it's stated for.
        public var gross: Double
        public var costs: Double
        public var net: Double?
        public var realGrowth: Double
        public var options: [String: JSONValue]
    }

    public struct Spending: Codable, Hashable, Sendable {
        public var working: Double
        public var retired: Double
        public var phases: [SpendingPhase]
    }

    public struct SpendingPhase: Codable, Hashable, Sendable {
        public var fromAge: Int
        public var factor: Double
    }

    public struct Pension: Codable, Hashable, Sendable {
        /// `pension-<index>`.
        public var id: String
        public var name: String
        public var scheme: String
        public var schemeName: String
        /// `earliest` or an age.
        public var claim: String
        public var claimRoute: String?
        /// `residence` or `source`.
        public var taxedIn: String
        public var kind: String?
        public var sourceCountry: String?
        /// The plan's options for the pension, as written.
        public var options: [String: JSONValue]
        /// The starting balance the scheme took from accounts that hold its record.
        public var startingBalanceFromAccounts: Double?
        /// The claim at the chosen retirement age; `nil` if never claimed.
        public var claimed: Claim?
        /// The options the scheme listed in the year it was claimed (or the
        /// last year it was asked).
        public var offered: [ClaimChoice]
    }

    public struct Claim: Codable, Hashable, Sendable {
        public var year: Int
        public var age: Int
        /// The year payments started (earlier for a pension already paid at the start).
        public var startYear: Int
        public var route: String
        public var label: String
        /// The gross amount of a whole year at the rate payments start at.
        public var yearlyAmount: Double
        public var lumpSum: Double?
        public var lumpSumWrapper: String?
        public var realGrowthPerYear: Double?
    }

    public struct ClaimChoice: Codable, Hashable, Sendable {
        public var route: String
        public var label: String
        public var age: Int
        /// The gross amount paid in the calendar year payments start.
        public var annualAmount: Double
        /// A whole year at the starting rate, when the first year is partial.
        public var fullYearAmount: Double?
        public var changes: [AgeAmount]
        public var lumpSum: Double?
        public var lumpSumWrapper: String?
        public var realGrowthPerYear: Double?
        public var note: String?
        /// Whether the plan took this one.
        public var chosen: Bool
    }

    public struct AgeAmount: Codable, Hashable, Sendable {
        public var age: Int
        public var amount: Double
    }

    public struct Contribution: Codable, Hashable, Sendable {
        public var index: Int
        /// The account paid into, or `nil` for a pension scheme.
        public var account: String?
        /// The pension scheme paid into (a buy-in), or `nil`.
        public var pensionScheme: String?
        /// The bucket's wrapper, or the scheme's ID.
        public var wrapper: String
        public var perYear: Double
        /// `retirement` or a date.
        public var until: String
        /// A one-off payment's year and amount.
        public var year: Int?
        public var amount: Double?
    }

    public struct Event: Codable, Hashable, Sendable {
        public var index: Int
        public var name: String
        public var year: Int
        public var age: Int
        /// Positive for a windfall, negative for an expense.
        public var amount: Double
        public var probability: Double
        public var kind: String
        /// Whether the deterministic run includes it (probability at least 50%).
        public var inDeterministicRun: Bool
    }

    public struct Withdrawals: Codable, Hashable, Sendable {
        public var strategy: String
        public var cashBuffer: Double
        /// The order money is drawn in.
        public var order: [String]
        /// How the buckets are rebalanced.
        public var rebalancing: String
    }

    // MARK: Assumptions

    public struct Assumptions: Codable, Hashable, Sendable {
        public var inflation: Double
        /// Each asset class the portfolio holds or can buy.
        public var classes: [ClassAssumption]
        /// The classes of ``correlations``' rows and columns.
        public var correlationClasses: [String]
        public var correlations: [[Double]]
        /// The whole portfolio, rebalanced to the target mix every year.
        public var portfolio: Growth
    }

    public struct ClassAssumption: Codable, Hashable, Sendable {
        public var assetClass: String
        /// The expected (arithmetic mean) yearly real return.
        public var expectedReturn: Double
        public var volatility: Double
        /// The median (typical, geometric) yearly real return implied by the
        /// two: (1 + expected) / √(1 + volatility² / (1 + expected)²) − 1.
        public var medianReturn: Double
        public var incomeYield: Double
        /// Its share of plan assets at the start.
        public var share: Double
        /// Its share of the mix the buckets are rebalanced to every year:
        /// each bucket's target mix, weighted by the bucket's value at the start.
        public var targetShare: Double
        /// The portfolio's median growth with this class left out of the
        /// target mix and the rest in their proportions; `nil` when the
        /// target mix doesn't hold it.
        public var portfolioMedianWithout: Double?
    }

    /// A mix's yearly real return, as a log-normal approximation from the
    /// classes' expected returns, volatilities and correlations.
    public struct Growth: Codable, Hashable, Sendable {
        public var expectedReturn: Double
        public var volatility: Double
        public var medianReturn: Double
    }

    // MARK: Starting portfolio

    public struct StartingPortfolio: Codable, Hashable, Sendable {
        public var date: CalendarDate
        /// The accounts the plan counts, as the tracker values them.
        public var planAssets: Double
        public var accounts: [Account]
        /// The instruments the accounts hold.
        public var instruments: [Instrument]
        /// The exchange rates the values were converted at.
        public var fxRates: [FXRate]
        public var buckets: [Bucket]
        public var schemeSeeds: [Seed]
        /// Debts in the plan, paid off from liquid money at the start.
        public var debtPaidOff: Double
        /// The plan's estimate of unrealised gain where no purchase cost was recorded.
        public var unrealizedGainShare: Double?
        /// Plan assets by asset class, as shares.
        public var classShares: [String: Double]
    }

    public struct Account: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var kind: String
        public var currency: String
        public var wrapper: String?
        /// `included`, `schemeSeed` or `leftOut`.
        public var outcome: String
        /// Why it's left out, or which scheme it starts.
        public var reason: String?
        /// The bucket it went into (its wrapper).
        public var bucket: String?
        /// In the plan's currency.
        public var value: Double?
        /// The purchase cost known or estimated for its holdings.
        public var costBasis: Double?
        public var holdings: [Holding]
    }

    public struct Holding: Codable, Hashable, Sendable {
        /// The instrument of a position; `nil` for cash or a balance.
        public var instrument: String?
        public var assetClass: String
        public var category: String
        public var value: Double
        public var costBasis: Double?
        /// `value`, `recorded`, `estimated` or `unknown`.
        public var basisSource: String
        /// The exchange rate its value was converted at, if any.
        public var fxRate: Double?
    }

    public struct Instrument: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var kind: String
        public var fundType: String?
        public var currency: String
        public var assetClasses: [String: Double]
    }

    public struct FXRate: Codable, Hashable, Sendable {
        public var from: String
        public var to: String
        public var rate: Double
        public var date: CalendarDate?
    }

    public struct Bucket: Codable, Hashable, Sendable {
        public var wrapper: String
        public var name: String
        /// `taxable`, `taxDeferred`, `taxFree`, …
        public var category: String
        public var liquid: Bool
        public var receivesSavings: Bool
        public var value: Double
        public var costBasis: Double
        public var targetMix: [String: Double]
        public var accounts: [String]
        /// The first age it can be drawn from at the chosen retirement age.
        public var accessibleFromAge: Int?
        /// Why it's locked at the start, as its rule says.
        public var lockedReason: String?
        /// Paid out in full when the job ends (severance pay such as TFR).
        public var paidWhenJobEnds: Bool
        public var growthTaxRate: Double?
        /// A revaluation set by law, instead of the markets.
        public var revaluation: String?
    }

    public struct Seed: Codable, Hashable, Sendable {
        public var scheme: String
        public var name: String
        public var wrapper: String
        public var accounts: [String]
        public var value: Double
        public var used: Bool
    }

    // MARK: Schedule

    /// What doesn't depend on the markets, year by year, at the chosen age:
    /// the deterministic run's prepared years.
    public struct Schedule: Codable, Hashable, Sendable {
        public var retirementAge: Int
        public var retirementDate: CalendarDate
        public var years: [ScheduleYear]
    }

    public struct ScheduleYear: Codable, Hashable, Sendable {
        public var year: Int
        public var age: Int
        /// The share of the year simulated.
        public var fraction: Double
        /// The share of the simulated part spent working.
        public var workingShare: Double
        public var work: Double
        /// Each pension paid (and lump sums), gross.
        public var pensions: [Amount]
        public var windfalls: [Amount]
        public var expenses: Double
        /// Planned contributions into accounts and schemes.
        public var contributions: Double
        /// Money credited into wrappers by the tax system (e.g. TFR) or moved
        /// there by a pension claim.
        public var credits: [Amount]
        /// The spending target.
        public var spending: Double
        /// Taxes and contributions on work, pensions and windfalls (the
        /// part of the year simulated).
        public var taxes: [Amount]
        public var socialContributions: [Amount]
        /// Work, pensions and windfalls after those taxes.
        public var netIncome: Double
        /// What the portfolio must provide: spending, expenses and
        /// contributions less net income. Negative is saved. Payouts the
        /// rules require and taxes on sales come on top, in each path.
        public var toDraw: Double
        /// Buckets paid out whether or not the money is needed.
        public var requiredPayouts: [String]
        /// The buckets that can be drawn from.
        public var accessible: [String]
        /// The mix the ordinary (taxable) accounts are rebalanced to this
        /// year, when the plan's target mix changes with age; `nil` otherwise.
        public var targetMix: [String: Double]? = nil
    }

    /// An amount by ID and label.
    public struct Amount: Codable, Hashable, Sendable {
        public var id: String
        public var label: String
        public var amount: Double
    }

    // MARK: Simulation summary

    public struct Simulation: Codable, Hashable, Sendable {
        public var successByAge: [AgeSuccess]
        public var successToday: Double
        public var earliestAge: Int?
        public var targetAge: Int?
        public var successAtTarget: Double?
        public var chosenAge: Int
        /// The main run's success at the chosen age, from today's assets.
        public var successAtChosenAge: Double?
        /// The share of runs that succeed at the chosen age from the start
        /// scale's assets (``Header/startScale``).
        public var successAtStartScale: Double
        /// The success the search for the assets needed counted at the same
        /// scale, when it tried it: it takes a run that succeeded with less
        /// money to succeed with more, which ``successAtStartScale`` checks.
        public var searchSuccessAtStartScale: Double?
        public var sustainableSpending: SpendingSearch?
        public var assetsNeeded: AssetsSearch?
        /// Why failing runs fail, at the chosen age and start scale.
        public var failures: Failures
        /// The deterministic run at the chosen age and start scale.
        public var expectedPath: PathOutcome
        /// The median run at the chosen age and start scale, with its
        /// retirement-years totals.
        public var medianPath: PathOutcome
        /// Whether re-simulating every run for the percentiles reproduced the
        /// main run's outcome for each; `nil` at another start scale than 1,
        /// where the runs aren't the main run's.
        public var allRunsReproduced: Bool?
    }

    public struct AgeSuccess: Codable, Hashable, Sendable {
        public var age: Int
        public var year: Int
        public var success: Double
    }

    public struct SpendingSearch: Codable, Hashable, Sendable {
        public var age: Int
        /// `nil` when even no spending reaches the confidence level.
        public var perYear: Double?
        public var success: Double?
        public var planSpending: Double
        /// Every spending tried, in order.
        public var steps: [SpendingStep]
    }

    public struct SpendingStep: Codable, Hashable, Sendable {
        public var spending: Double
        public var success: Double
    }

    /// The search for the plan assets retiring today needs: extra money in
    /// the buckets that can be drawn at today's age (``accessible``), or
    /// money taken out of them.
    public struct AssetsSearch: Codable, Hashable, Sendable {
        public var age: Int
        /// `found`, `atMost`, `moreThanMaximum` or `noPlanAssets`.
        public var outcome: String
        /// ``amount`` as a multiple of ``planAssets``.
        public var scale: Double?
        public var amount: Double?
        public var success: Double?
        public var readiness: Double?
        public var planAssets: Double
        public var maximumScale: Double
        /// Every amount tried, in order.
        public var steps: [ScaleStep]
        /// The extra money in the accessible buckets (`amount − planAssets`;
        /// negative when money could be taken out), as in
        /// ``AssetsNeeded/extra``.
        public var extra: Double? = nil
        /// Today's value of the accessible buckets, which the search adds to
        /// or takes from; the rest of ``planAssets`` is locked away today.
        public var accessible: Double? = nil
    }

    /// One amount the search for the assets needed tried.
    public struct ScaleStep: Codable, Hashable, Sendable {
        /// ``amount`` as a multiple of today's plan assets.
        public var scale: Double
        /// The plan assets with ``extra``.
        public var amount: Double
        public var success: Double
        /// The extra money in the accessible buckets (negative: taken out).
        public var extra: Double? = nil
    }

    public struct Failures: Codable, Hashable, Sendable {
        public var runs: Int
        public var failed: Int
        public var failureRate: Double
        public var medianFailureAge: Int?
        /// Runs whose money ran out entirely.
        public var depleted: Int
        /// Runs that ran out while money was locked that would have bridged the gap.
        public var bridging: Int
        public var byAge: [AgeCount]
        public var bridges: [Bridge]
    }

    public struct AgeCount: Codable, Hashable, Sendable {
        public var age: Int
        public var count: Int
    }

    public struct Bridge: Codable, Hashable, Sendable {
        public var wrapper: String
        public var name: String
        public var accessibleFromAge: Int?
        public var count: Int
    }

    public struct PathOutcome: Codable, Hashable, Sendable {
        public var run: Int?
        public var failed: Bool
        public var failureYear: Int?
        public var failureAge: Int?
        /// Plan assets at the end (0 after a failure).
        public var finalValue: Double
        /// In the years fully retired, until the end or the failure: gross
        /// income (pensions, windfalls, withdrawals and payouts) and all
        /// taxes and contributions. `nil` for the deterministic run.
        public var retiredGrossIncome: Double?
        public var retiredTaxes: Double?
        /// Of which taxes on sales, payouts, interest and wealth.
        public var retiredMarketTaxes: Double?
        public var retiredWithdrawals: Double?
    }

    // MARK: Percentiles

    public struct PercentileYear: Codable, Hashable, Sendable {
        public var year: Int
        public var age: Int
        /// Plan assets at the year-end.
        public var value: Percentiles
        /// The deterministic run's year-end value.
        public var expected: Double
        /// Gross sales and payouts, among the runs still going.
        public var withdrawals: Percentiles
        /// Taxes and contributions, among the runs still going.
        public var taxes: Percentiles
        /// The share of runs that still meet their spending at the year-end.
        public var going: Double
    }

    public struct Percentiles: Codable, Hashable, Sendable {
        public var p10: Double
        public var p25: Double
        public var p50: Double
        public var p75: Double
        public var p90: Double
    }

    // MARK: Traced paths

    public struct TracedPath: Codable, Hashable, Sendable {
        /// `expected`, `median`, `p10`, `p25`, `p75`, `p90`, `firstFailure` or `chosen`.
        public var kind: String
        public var label: String
        /// The run index; `nil` for the deterministic run.
        public var run: Int?
        /// Its place when runs are ranked from worst to best (1 is the worst).
        public var rank: Int?
        /// Whether its outcome is exactly the main run's for the same run.
        public var matchesMainRun: Bool
        /// The buckets, in the order of ``TracedYear/buckets``.
        public var buckets: [BucketRef]
        /// The asset classes, in the order of returns and class values.
        public var classes: [String]
        public var failed: Bool
        public var failureYear: Int?
        public var failureAge: Int?
        public var failureReason: String?
        public var finalValue: Double
        public var years: [TracedYear]
    }

    public struct BucketRef: Codable, Hashable, Sendable {
        public var wrapper: String
        public var name: String
    }

    public struct TracedYear: Codable, Hashable, Sendable {
        public var year: Int
        public var age: Int
        public var fraction: Double
        /// The real return drawn for each class (``TracedPath/classes``).
        public var returns: [Double]
        public var startAssets: Double
        /// Year-end plan assets, less taxes still to pay.
        public var endAssets: Double
        /// Work, pensions and windfalls after their taxes.
        public var netIncome: Double
        /// Severance pay and required payouts, after their tax.
        public var payoutsNet: Double
        public var contributions: Double
        public var spending: Double
        public var expenses: Double
        /// Market-dependent taxes of the year before, paid now.
        public var lastYearsTaxes: Double
        /// The cash flow before withdrawals: positive is invested, negative drawn.
        public var cashFlow: Double
        /// What couldn't be raised (the run fails above 1).
        public var shortfall: Double
        public var spendingTarget: Double
        public var spendingMet: Double
        public var buckets: [TracedBucket]
        public var sales: [Sale]
        public var payouts: [Payout]
        public var withheldOnPayouts: Double
        public var withheldOnWithdrawals: Double
        public var withheldOnRebalancing: Double
        /// Every tax and contribution line of the year.
        public var taxes: [TaxLine]
        public var carriedToNextYear: Double
        public var failed: Bool
        /// What the tax system carries along the path into the next year,
        /// such as losses carried forward; `nil` when it carries nothing.
        public var carriedForward: [CarriedAmount]? = nil
        /// The mix the ordinary (taxable) accounts are rebalanced to this
        /// year, when the plan's target mix changes with age; `nil` otherwise.
        public var targetMix: [String: Double]? = nil
    }

    /// An amount the tax system carries along a path into the next year,
    /// e.g. the losses of one year it lets later years offset.
    public struct CarriedAmount: Codable, Hashable, Sendable {
        public var id: String
        public var label: String
        /// In today's money, as the year it's carried out of counts it.
        public var amount: Double
    }

    public struct TracedBucket: Codable, Hashable, Sendable {
        public var start: Double
        /// Contributions, credits and savings in.
        public var moneyIn: Double
        /// Payouts the rules require, gross.
        public var requiredPayouts: Double
        /// Sold or paid out for the year's need, gross.
        public var withdrawn: Double
        /// Tax paid from the bucket on rebalancing sales.
        public var rebalancingTax: Double
        /// Per class, bought (+) or sold (−) to rebalance.
        public var rebalancing: [Double]
        /// The year's market growth.
        public var growth: Double
        public var end: Double
        public var endCostBasis: Double
        /// Per class at the year-end.
        public var endClasses: [Double]
    }

    public struct Sale: Codable, Hashable, Sendable {
        public var wrapper: String
        public var category: String
        public var proceeds: Double
        public var costBasis: Double?
        public var gain: Double?
        /// `withdrawal` or `rebalancing`.
        public var purpose: String
    }

    public struct Payout: Codable, Hashable, Sendable {
        public var wrapper: String
        public var amount: Double
        public var costBasis: Double?
        public var form: String
        /// `required` or `withdrawal`.
        public var purpose: String
    }

    public struct TaxLine: Codable, Hashable, Sendable {
        public var id: String
        public var label: String
        /// `tax` or `contribution`.
        public var kind: String
        /// On work, pensions and windfalls (the part of the year simulated).
        public var fixed: Double
        /// On sales, payouts, interest and balances.
        public var market: Double
    }

    // MARK: Issues

    public struct Issue: Codable, Hashable, Sendable {
        /// `error` or `warning`.
        public var severity: String
        public var code: String
        public var message: String
        public var section: String
        public var year: Int?
        public var account: String?
    }
}
