import Foundation
import Model

/// What first launch asks (UI.md, "Empty states and first launch"): round
/// amounts of what you have today, what you take home and spend a month,
/// a state pension, the age to retire at and the tax on investments. All
/// optional; amounts are in the base currency, after tax.
public struct StarterAnswers: Hashable, Sendable {
    /// Cash and savings.
    public var cash: Decimal?
    /// Investments: funds, shares and the like.
    public var investments: Decimal?
    /// A pension pot you can't draw on before ``pensionFromAge``.
    public var pension: Decimal?
    /// The age the pension pot can be drawn from.
    public var pensionFromAge: Int?
    /// What your home is worth, less what you still owe on it.
    public var home: Decimal?
    public var payPerMonth: Decimal?
    public var spendingPerMonth: Decimal?
    /// A state pension a month, after tax, in today's money.
    public var statePensionPerMonth: Decimal?
    public var statePensionFromAge: Int?
    /// The age to retire at; `nil` is as early as possible.
    public var retirementAge: Int?
    /// The tax on investment gains and income, as a fraction (`0.26`).
    public var investmentTax: Decimal?

    public init(cash: Decimal? = nil, investments: Decimal? = nil, pension: Decimal? = nil,
                pensionFromAge: Int? = nil, home: Decimal? = nil, payPerMonth: Decimal? = nil,
                spendingPerMonth: Decimal? = nil, statePensionPerMonth: Decimal? = nil,
                statePensionFromAge: Int? = nil, retirementAge: Int? = nil, investmentTax: Decimal? = nil) {
        self.cash = cash
        self.investments = investments
        self.pension = pension
        self.pensionFromAge = pensionFromAge
        self.home = home
        self.payPerMonth = payPerMonth
        self.spendingPerMonth = spendingPerMonth
        self.statePensionPerMonth = statePensionPerMonth
        self.statePensionFromAge = statePensionFromAge
        self.retirementAge = retirementAge
        self.investmentTax = investmentTax
    }

    /// Whether any amount is negative: first launch waits until it's fixed.
    public var hasNegativeAmount: Bool {
        [cash, investments, pension, home, payPerMonth, spendingPerMonth, statePensionPerMonth, investmentTax]
            .contains { ($0 ?? 0) < 0 }
    }

    /// Whether anything you have today was entered (above 0).
    public var hasStartingAmounts: Bool {
        [cash, investments, pension, home].contains { ($0 ?? 0) > 0 }
    }

    /// What you save a month (pay less spending) and its share of pay;
    /// `nil` without pay above 0 and spending.
    public var saving: (perMonth: Decimal, share: Double)? {
        guard let pay = payPerMonth, pay > 0, let spending = spendingPerMonth, spending >= 0 else { return nil }
        let perMonth = pay - spending
        return (perMonth, (perMonth / pay).doubleValue)
    }
}

/// Turns ``StarterAnswers`` into a library's first records and its first
/// plan (UI.md, "Empty states and first launch").
///
/// - **Starting estimates.** Each amount you have today becomes an account
///   of its own, tagged ``estimateTag`` and named "(estimate)", with one
///   value on the day: cash and savings as a savings account, investments
///   as equity, the pension pot as a pension fund available from its age,
///   the home as property that plans leave out. They are what the first
///   answer stands on until imported files replace them; closing an
///   estimate with the real account as its successor retires it.
/// - **The plan.** Pay and spending a month (`setMonthly`), the age to
///   retire at, the state pension and the tax rate.
public enum StarterSetup {
    /// The tag that marks an account as a starting estimate.
    public static let estimateTag = "estimate"

    /// The state pension's name in a plan, and on the plan's cards.
    public static let statePensionName = "State pension"

    /// A pension pot's mix: balanced, as most default funds are.
    static let pensionMix: AssetMix = [.equity: Decimal(string: "0.6") ?? 0, .bonds: Decimal(string: "0.4") ?? 0]

    /// The estimate accounts for `answers`, opened on `date`, in `currency`;
    /// `id` makes each one's ID from its name. Amounts of 0 or less get none.
    public static func estimateAccounts(for answers: StarterAnswers, currency: CurrencyCode, country: CountryCode?,
                                        on date: CalendarDate, id: (String) -> AccountID) -> [(Account, Decimal)] {
        func estimate(_ name: String, _ kind: AccountKind, _ amount: Decimal?,
                      configure: (inout Account) -> Void = { _ in }) -> (Account, Decimal)? {
            guard let amount, amount > 0 else { return nil }
            let fullName = "\(name) (estimate)"
            var account = Account(id: id(fullName), name: fullName, kind: kind, currency: currency, opened: date)
            account.country = country
            account.tags = [estimateTag]
            account.notes = "A round amount from first launch. Close it once your real accounts are imported."
            configure(&account)
            return (account, amount)
        }
        return [
            estimate("Cash and savings", .savings, answers.cash),
            estimate("Investments", .other, answers.investments) { $0.assetClasses = .single(.equity) },
            estimate("Pension", .pensionFund, answers.pension) { account in
                account.assetClasses = pensionMix
                account.availableFromAge = answers.pensionFromAge
            },
            estimate("Home", .property, answers.home) { $0.includeIn = IncludeIn(plan: false) },
        ].compactMap { $0 }
    }

    /// Adds the estimate accounts for `answers` to `library`, each with its
    /// value on `date`, in the library's base currency, with IDs that aren't
    /// in the library or `taken` (account files that didn't load). Returns
    /// their IDs.
    @discardableResult
    public static func addEstimates(_ answers: StarterAnswers, to library: inout Library, on date: CalendarDate,
                                    taken: [AccountID] = []) -> [AccountID] {
        var used = Array(library.accounts.keys) + taken
        let estimates = estimateAccounts(for: answers, currency: library.settings.baseCurrency,
                                         country: library.settings.taxResidence, on: date) { name in
            let id = AccountID.make(from: name, existing: used)
            used.append(id)
            return id
        }
        for (account, amount) in estimates {
            library.accounts[account.id] = account
            library.upsert(Valuation(account: account.id, date: date, balance: amount,
                                     note: "Estimate from first launch", source: .manual))
        }
        return estimates.map(\.0.id)
    }

    /// `plan` with the answers' pay and spending a month, the age to
    /// retire at, the state pension (in place of the plan's pensions, when
    /// one above 0 is given) and the tax on investments.
    public static func complete(_ plan: inout PlanDocument, with answers: StarterAnswers, asOf: CalendarDate) {
        plan.setMonthly(payPerMonth: answers.payPerMonth, spendingPerMonth: answers.spendingPerMonth, asOf: asOf)
        plan.setRetirementAge(answers.retirementAge)
        if let perMonth = answers.statePensionPerMonth, perMonth > 0, let fromAge = answers.statePensionFromAge {
            plan.pensions = [PlanPension(name: statePensionName, fromAge: fromAge, perYear: perMonth * 12)]
        }
        if let rate = answers.investmentTax, rate >= 0 {
            plan.tax.investmentRate = rate
        }
    }

    /// The extra saving a month that the first answer's lever tries: a
    /// tenth of pay (else of spending), to two significant figures, at
    /// least 10; `nil` without either, or when spending while working
    /// couldn't fall by as much.
    public static func leverStep(for answers: StarterAnswers) -> Decimal? {
        guard let base = answers.payPerMonth.flatMap({ $0 > 0 ? $0 : nil })
                ?? answers.spendingPerMonth.flatMap({ $0 > 0 ? $0 : nil })
        else { return nil }
        let step = max(10, roundedToTwoFigures(base / 10))
        guard let spending = answers.spendingPerMonth, spending >= step else { return nil }
        return step
    }

    /// `plan` saving `perMonth` more while working: spending while working
    /// falls by as much, never below 0.
    public static func savingMore(_ plan: PlanDocument, perMonth: Decimal) -> PlanDocument {
        var plan = plan
        plan.spending.working = max(0, plan.spending.working - perMonth * 12)
        return plan
    }

    /// `amount` to two significant figures: 420 → 420, 1234 → 1200.
    static func roundedToTwoFigures(_ amount: Decimal) -> Decimal {
        let value = amount.doubleValue
        guard value >= 100, value.isFinite else { return Decimal(Int(value.rounded())) }
        let step = pow(10, (log10(value).rounded(.down) - 1))
        return Decimal(Int((value / step).rounded() * step))
    }
}

extension Account {
    /// Whether first launch made it from a round amount
    /// (``StarterSetup/estimateTag``).
    public var isStartingEstimate: Bool {
        tags.contains(StarterSetup.estimateTag)
    }
}

extension Library {
    /// The open starting estimates, by name: what the first answer stands
    /// on until imported files replace them.
    public var openStartingEstimates: [Account] {
        accounts.values.filter { $0.isStartingEstimate && !$0.isClosed }
            .sorted { $0.name < $1.name }
    }
}
