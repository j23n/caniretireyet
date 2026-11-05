import Foundation
import Model
import Planner
import Tracker

/// Every number the app shows for a library, at each check-in, worked out
/// by the same package functions the screens call (`retire audit --json`):
/// to compare with a golden file, or with another version of the code.
///
/// Amounts are decimals written exactly, as the library writes them
/// (``AuditNumber/exact(_:)``); the planner's estimates are rounded to 4
/// significant figures (``AuditNumber/significant(_:)``). Keys are sorted
/// and lists are in date or ID order, so the output diffs cleanly.
struct Audit: Encodable {
    /// The base currency of every amount.
    var currency: String
    /// The check-ins audited are those on or before this date.
    var through: String
    /// The plan Progress and the milestones are for; absent without one.
    var plan: String?
    var checkIns: [CheckIn]
    /// *Where your money came from* by year, through the latest check-in of plan assets.
    var moneySources: Sources
    /// Progress and Trends' years, and the milestones reached; absent without a plan.
    var progress: Progress?
    /// The plan's answer, run with few runs; absent unless a plan was asked for.
    var planRun: PlanNumbers?

    /// How many runs ``planRun`` uses: few, so it's quick, with the plan's
    /// own seed, so it's the same every time.
    static let planRuns = 50

    /// The audit of `library` through `through`, with Progress for `plan`
    /// and the plan's answer when `run` is given.
    init(library: Library, through: CalendarDate, plan: PlanID?, run: PlanResult?) {
        let valuator = Valuator(library: library)
        let inflation = InflationIndex(library: library)
        currency = library.settings.baseCurrency.rawValue
        self.through = through.description
        self.plan = plan?.rawValue

        // The Months screen's months: each check-in of the accounts with months, from the one before.
        var monthStarts: [CalendarDate: CalendarDate] = [:]
        for month in library.moneyMonths() where month.isCheckedIn {
            if let from = month.from { monthStarts[month.through] = from }
        }
        let dates = valuator.checkInDates(through: through)
        checkIns = dates.enumerated().map { index, date in
            CheckIn(date: date, previous: index > 0 ? dates[index - 1] : nil, monthFrom: monthStarts[date],
                    valuator: valuator, inflation: inflation)
        }

        let end = valuator.latestCheckIn(onOrBefore: through, in: .planAssets) ?? through
        moneySources = Sources(valuator.moneySources(.years, through: end))
        progress = plan.map { id in
            Progress(PlanProgress(plan: id, document: library.plans[id], library: library, valuator: valuator,
                                  asOf: through))
        }
        planRun = run.map(PlanNumbers.init)
    }

    // MARK: - Check-ins

    /// One check-in: net worth, and what changed since the check-in before.
    struct CheckIn: Encodable {
        var date: String
        /// The check-in before, a date with a value of any account.
        var previous: String?
        var netWorth: Total
        var planAssets: Total
        /// Each account in net worth since the check-in before, by ID.
        var accounts: [AccountChange]?
        /// Today's *What moved it* and *Your pay*.
        var whatMoved: Moved?
        /// The check-in's bars: net worth's change with saved as *What moved it* counts it.
        var savedSplit: Change?
        var savingsRate: Rates
        /// Today's *This year*, as on the day of the check-in.
        var changeThisYear: ThisYear?
        /// The saving pace as of the check-in; absent with too little history.
        var savingPace: Pace?

        init(date: CalendarDate, previous: CalendarDate?, monthFrom: CalendarDate?, valuator: Valuator,
             inflation: InflationIndex?) {
            self.date = date.description
            self.previous = previous?.description
            netWorth = Total(valuator.netWorth(on: date))
            planAssets = Total(valuator.total(on: date, in: .planAssets))
            if let previous {
                let report = valuator.change(from: previous, to: date)
                accounts = report.accounts.map(AccountChange.init)
                whatMoved = Moved(valuator.whatMoved(report))
                savedSplit = Change(valuator.savedSplit(of: report))
            }
            savingsRate = Rates(
                month: monthFrom.flatMap { valuator.savingsRate(from: $0.adding(days: 1), through: date) }.map(Rate.init),
                twelveMonths: valuator.savingsRate(overYearEndingOn: date).map(Rate.init),
                yearSoFar: valuator.savingsRate(from: .firstDay(ofYear: date.year), through: date).map(Rate.init))
            changeThisYear = valuator.changeThisYear(asOf: date).map { report in
                ThisYear(from: report.from.description, change: Change(report.total),
                         split: Change(valuator.savedSplit(of: report)))
            }
            savingPace = valuator.savingPace(asOf: date, inflation: inflation).map(Pace.init)
        }
    }

    /// A total of accounts on a day.
    struct Total: Encodable {
        var total: String
        /// Whether every price and rate was known.
        var priced: Bool

        init(_ total: NetWorth) {
            self.total = AuditNumber.exact(total.total)
            priced = total.isPriced
        }
    }

    /// A change split for the waterfall: `start + market + saved + other + lost == end`.
    struct Change: Encodable {
        var start: String
        var market: String
        var saved: String
        var other: String
        var lost: String
        var end: String

        init(_ change: ValueChange) {
            start = AuditNumber.exact(change.start)
            market = AuditNumber.exact(change.market)
            saved = AuditNumber.exact(change.saved)
            other = AuditNumber.exact(change.other)
            lost = AuditNumber.exact(change.lost)
            end = AuditNumber.exact(change.end)
        }
    }

    /// How one account changed.
    struct AccountChange: Encodable {
        var account: String
        var change: Change
        /// Whether what its values saved is known.
        var savedKnown: Bool
        /// Missing values, prices and rates.
        var problems: [String]?

        init(_ change: Tracker.AccountChange) {
            account = change.account.rawValue
            self.change = Change(change.change)
            savedKnown = change.isSavedKnown
            problems = change.problems.isEmpty ? nil : change.problems.map(\.description)
        }
    }

    /// ``WhatMoved``: every part of net worth's change, and the pay.
    struct Moved: Encodable {
        var start: String
        var change: String
        var saved: String
        var markets: String
        var oneOffs: String
        var startedWith: String
        var lost: String
        var unexplained: String
        var other: String
        var priced: Bool
        var pay: Pay?

        init(_ moved: WhatMoved) {
            start = AuditNumber.exact(moved.start)
            change = AuditNumber.exact(moved.change)
            saved = AuditNumber.exact(moved.saved)
            markets = AuditNumber.exact(moved.markets)
            oneOffs = AuditNumber.exact(moved.oneOffs)
            startedWith = AuditNumber.exact(moved.startedWith)
            lost = AuditNumber.exact(moved.lost)
            unexplained = AuditNumber.exact(moved.unexplained)
            other = AuditNumber.exact(moved.other)
            priced = moved.isPriced
            pay = moved.pay.map(Pay.init)
        }
    }

    /// ``WhatMoved/Pay``: what came in, the tax, what was spent and saved.
    struct Pay: Encodable {
        var moneyIn: String
        var pension: String
        var tax: String
        var cameIn: String
        var afterTax: String
        var saved: String
        var spent: String
        var savedShare: String?

        init(_ pay: WhatMoved.Pay) {
            moneyIn = AuditNumber.exact(pay.moneyIn)
            pension = AuditNumber.exact(pay.pension)
            tax = AuditNumber.exact(pay.tax)
            cameIn = AuditNumber.exact(pay.cameIn)
            afterTax = AuditNumber.exact(pay.afterTax)
            saved = AuditNumber.exact(pay.saved)
            spent = AuditNumber.exact(pay.spent)
            savedShare = pay.savedShare.map(AuditNumber.exact)
        }
    }

    /// The savings rate over the check-in's month (as the Months screen
    /// counts it, from the check-in before of the accounts with months),
    /// the 12 months to it and the year so far.
    struct Rates: Encodable {
        var month: Rate?
        var twelveMonths: Rate?
        var yearSoFar: Rate?
    }

    /// ``SavingsRate``.
    struct Rate: Encodable {
        /// The days the pay covers: after `from` through `through`.
        var from: String
        var through: String
        var moneyIn: String
        var moneyOut: String
        var moneyOutPerYear: String?
        var oneOffs: String
        /// The tax recorded with the values, less refunds.
        var taxes: String
        var taxSetAside: String
        var tax: String
        var pensionContributions: String
        /// What came in after tax: ``SavingsRate/income``.
        var cameIn: String
        var saved: String
        var spent: String
        var spentPerYear: String
        var rate: String?
        var noRate: String?
        var priced: Bool
        var months: [String]
        var savedByAccount: [String: String]

        init(_ rate: SavingsRate) {
            from = rate.from.description
            through = rate.through.description
            moneyIn = AuditNumber.exact(rate.moneyInOut.moneyIn)
            moneyOut = AuditNumber.exact(rate.moneyInOut.moneyOut)
            moneyOutPerYear = rate.moneyInOut.moneyOutPerYear.map(AuditNumber.exact)
            oneOffs = AuditNumber.exact(rate.oneOffs)
            taxes = AuditNumber.exact(rate.moneyInOut.taxes)
            taxSetAside = AuditNumber.exact(rate.taxSetAside)
            tax = AuditNumber.exact(rate.tax)
            pensionContributions = AuditNumber.exact(rate.pensionContributions)
            cameIn = AuditNumber.exact(rate.income)
            saved = AuditNumber.exact(rate.saved)
            spent = AuditNumber.exact(rate.spent)
            spentPerYear = AuditNumber.exact(rate.spentPerYear)
            self.rate = rate.rate.map(AuditNumber.exact)
            noRate = rate.noRate.map { reason in
                switch reason {
                case .nothingCameIn: "nothingCameIn"
                case .lessThanNothingCameIn: "lessThanNothingCameIn"
                case .moreTaxThanCameIn: "moreTaxThanCameIn"
                }
            }
            priced = rate.isPriced
            months = rate.moneyInOut.months.map(\.description)
            savedByAccount = Dictionary(uniqueKeysWithValues: rate.savedByAccount.map {
                ($0.key.rawValue, AuditNumber.exact($0.value))
            })
        }
    }

    /// Net worth since 31 December, and its split with saved as the bars count it.
    struct ThisYear: Encodable {
        var from: String
        var change: Change
        var split: Change
    }

    /// ``SavingPace``.
    struct Pace: Encodable {
        struct Month: Encodable {
            var end: String
            var saved: String
            var unusual: Bool
        }

        var asOf: String
        var months: [Month]
        var usualMonth: String
        var perYear: String
        var range: [String]?
        var byAccount: [String: String]
        var byAccountInPace: [String: String]
        var carriedForward: [String]
        var inTodaysMoney: Bool
        var complete: Bool

        init(_ pace: SavingPace) {
            asOf = pace.asOf.description
            months = pace.months.map {
                Month(end: $0.end.description, saved: AuditNumber.exact($0.saved), unusual: $0.isUnusual)
            }
            usualMonth = AuditNumber.exact(pace.usualMonth)
            perYear = AuditNumber.exact(pace.perYear)
            range = pace.range.map { [AuditNumber.exact($0.lowerBound), AuditNumber.exact($0.upperBound)] }
            byAccount = AuditNumber.exact(pace.byAccount)
            byAccountInPace = AuditNumber.exact(pace.byAccountInPace)
            carriedForward = pace.carriedForward.map(\.rawValue)
            inTodaysMoney = pace.isInTodaysMoney
            complete = pace.isComplete
        }
    }

    // MARK: - Trends and Progress

    /// ``MoneySources`` by year.
    struct Sources: Encodable {
        struct Point: Encodable {
            var date: String
            var total: String
            var startedWith: String
            var saved: String
            var markets: String
            var priced: Bool
        }

        struct Year: Encodable {
            var year: Int
            var saved: String
            var markets: String
            var soFar: Bool
        }

        var points: [Point]
        var years: [Year]
        var firstYearMarketsAddedMore: Int?

        init(_ sources: MoneySources) {
            points = sources.points.map { point in
                Point(date: point.date.description, total: AuditNumber.exact(point.total),
                      startedWith: AuditNumber.exact(point.startedWith), saved: AuditNumber.exact(point.saved),
                      markets: AuditNumber.exact(point.markets), priced: point.isPriced)
            }
            years = sources.years.map { year in
                Year(year: year.year, saved: AuditNumber.exact(year.saved), markets: AuditNumber.exact(year.markets),
                     soFar: year.isSoFar)
            }
            firstYearMarketsAddedMore = sources.firstYearMarketsAddedMore
        }
    }

    /// ``PlanProgress``: its years and the milestones reached.
    struct Progress: Encodable {
        var years: [Year]
        var milestones: [Milestone]

        init(_ progress: PlanProgress) {
            years = progress.years.map(Year.init)
            milestones = progress.reached.map(Milestone.init)
        }
    }

    /// ``PlanProgressYear``: So far's year and Trends' *Year by year*.
    struct Year: Encodable {
        var year: Int
        var from: String
        var to: String
        var checkIns: Int
        var lastCheckIn: String?
        var latest: Bool
        var soFar: Bool
        var change: Change
        var complete: Bool
        var saved: String
        var plannedSaving: String?
        var savedGrade: String?
        /// What markets did, as context: `strong`, `average` or `hard`.
        var marketYear: String?
        var spentPerYear: String?
        var plannedSpending: String?
        var spentGrade: String?
        var baseline: String?
        var position: Position?
        var answerFrom: Int?
        var answerTo: Int?

        init(_ year: PlanProgressYear) {
            self.year = year.year
            from = year.from.description
            to = year.to.description
            checkIns = year.checkIns
            lastCheckIn = year.lastCheckIn?.description
            latest = year.isLatest
            soFar = year.isSoFar
            change = Change(year.change)
            complete = year.isComplete
            saved = AuditNumber.exact(year.saved)
            plannedSaving = year.plannedSaving.map(AuditNumber.exact)
            savedGrade = year.savedGrade.map(Self.grade)
            marketYear = year.marketYear.map { "\($0)" }
            spentPerYear = year.spentPerYear.map(AuditNumber.exact)
            plannedSpending = year.plannedSpending.map(AuditNumber.exact)
            spentGrade = year.spent.map(Self.grade)
            baseline = year.baseline?.id.rawValue
            position = year.position.map(Position.init)
            answerFrom = year.answerFrom?.earliestAge
            answerTo = year.answerTo?.earliestAge
        }

        static func grade(_ comparison: PlanComparison) -> String {
            switch comparison {
            case .less: "less"
            case .asPlanned: "asPlanned"
            case .more: "more"
            }
        }
    }

    /// ``PlanBaselineComparison/Position``: where a year's end stands against its baseline.
    struct Position: Encodable {
        var date: String
        var actual: String
        var median: String
        var gap: String
        var percentile: String?
        var standing: String

        init(_ position: PlanBaselineComparison.Position) {
            date = position.date.description
            actual = AuditNumber.exact(position.actual)
            median = AuditNumber.exact(position.median)
            gap = AuditNumber.exact(position.gap)
            percentile = position.percentile.map { AuditNumber.significant($0) }
            standing = switch position.standing {
            case .ahead: "ahead"
            case .onPlan: "onPlan"
            case .behind: "behind"
            }
        }
    }

    /// ``ReachedMilestone``.
    struct Milestone: Encodable {
        var id: String
        var date: String
        var amount: String

        init(_ reached: ReachedMilestone) {
            id = reached.milestone.id
            date = reached.date.description
            amount = AuditNumber.exact(reached.milestone.amount)
        }
    }

    // MARK: - The plan

    /// The plan's key numbers (``PlanAnswer``), its doubles to 4 significant figures.
    struct PlanNumbers: Encodable {
        struct AssetsNeeded: Encodable {
            var outcome: String
            var amount: String?
            var scale: String?
            var extra: String?
            var accessible: String?
            var success: String?
        }

        struct Spending: Encodable {
            var age: Int
            var perYear: String
            var success: String
        }

        struct AgeWithout: Encodable {
            /// `saving` (the coast age), `pace`, or `windfall-<index>`.
            var change: String
            var earliestAge: Int?
        }

        var plan: String
        var runs: Int
        var seed: UInt64
        var confidence: String
        var start: String
        var planAssets: String
        var trackedAssets: String
        var currentAge: Int
        var successIfRetiringNow: String
        var canRetireNow: Bool
        var earliestAge: Int?
        var earliestDate: String?
        var targetAge: Int?
        var successAtTarget: String?
        var readiness: String?
        var assetsNeeded: AssetsNeeded?
        var sustainableSpending: Spending?
        var agesWithout: [AgeWithout]
        /// The chance of success by retirement age.
        var successCurve: [String: String]
        /// The codes of the plan's warnings.
        var issues: [String]

        init(_ result: PlanResult) {
            let answer = result.answer
            plan = result.plan.id.rawValue
            runs = result.settings.runs
            seed = result.plan.simulation.effectiveSeed
            confidence = AuditNumber.significant(answer.confidence)
            start = result.start.date.description
            planAssets = AuditNumber.exact(result.start.planAssets)
            trackedAssets = AuditNumber.exact(result.start.trackedAssets)
            currentAge = answer.currentAge
            successIfRetiringNow = AuditNumber.significant(answer.successIfRetiringNow)
            canRetireNow = answer.canRetireNow
            earliestAge = answer.earliestAge
            earliestDate = answer.earliestDate?.description
            targetAge = answer.targetAge
            successAtTarget = answer.successAtTarget.map { AuditNumber.significant($0) }
            readiness = answer.readiness.map { AuditNumber.significant($0) }
            assetsNeeded = answer.assetsNeeded.map { needed in
                AssetsNeeded(outcome: "\(needed.outcome)", amount: needed.amount.map { AuditNumber.significant($0) },
                             scale: needed.scale.map { AuditNumber.significant($0) },
                             extra: needed.extra.map { AuditNumber.significant($0) },
                             accessible: needed.accessible.map { AuditNumber.significant($0) },
                             success: needed.success.map { AuditNumber.significant($0) })
            }
            sustainableSpending = answer.sustainableSpending.map { spending in
                Spending(age: spending.age, perYear: AuditNumber.significant(spending.perYear),
                         success: AuditNumber.significant(spending.success))
            }
            agesWithout = answer.agesWithout.map { without in
                let change = switch without.change {
                case .saving: "saving"
                case .pace: "pace"
                case .windfall(let index): "windfall-\(index)"
                }
                return AgeWithout(change: change, earliestAge: without.earliestAge)
            }
            successCurve = Dictionary(uniqueKeysWithValues: result.successCurve.map {
                (String($0.age), AuditNumber.significant($0.success))
            })
            issues = result.issues.map(\.code)
        }
    }
}

/// Numbers as the audit writes them.
enum AuditNumber {
    /// A decimal exactly, in its shortest form, as library files write it: `1500`, `0.1`.
    static func exact(_ value: Decimal) -> String {
        value.fileString
    }

    /// Amounts by account, each exactly.
    static func exact(_ amounts: [AccountID: Decimal]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: amounts.map { ($0.key.rawValue, exact($0.value)) })
    }

    /// A planner estimate rounded to `digits` significant figures, written as
    /// a plain decimal: `0.9234`, `1235000`.
    static func significant(_ value: Double, digits: Int = 4) -> String {
        guard value.isFinite else { return "\(value)" }
        let text = String(format: "%.\(digits)g", value)
        return Decimal(fileString: text)?.fileString ?? text
    }
}
