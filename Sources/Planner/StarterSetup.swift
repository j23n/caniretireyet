import Foundation
import Model

/// What first launch asks (UI.md, "Empty states and first launch"): round
/// amounts of what you have today and still owe, what you take home, pay
/// into a pension and spend a month (and in retirement), a state pension,
/// the age to retire at and the tax on investments. All optional; amounts are in the base currency, after
/// tax, and none is negative (a debt is what's owed, above 0).
public struct StarterAnswers: Hashable, Sendable {
    /// Cash and savings.
    public var cash: Decimal?
    /// Investments: funds, shares and the like.
    public var investments: Decimal?
    /// A pension pot you can't draw on before ``pensionFromAge``.
    public var pension: Decimal?
    /// The age the pension pot can be drawn from.
    public var pensionFromAge: Int?
    /// What your home is worth.
    public var home: Decimal?
    /// What you still owe on the home's mortgage.
    public var mortgage: Decimal?
    /// What you owe besides a mortgage: car loans, student loans and the like.
    public var otherDebts: Decimal?
    public var payPerMonth: Decimal?
    /// What you or your employer pay into the pension pot a month, before
    /// your pay reaches you, so on top of ``payPerMonth``.
    public var pensionPerMonth: Decimal?
    public var spendingPerMonth: Decimal?
    /// Spending a month in retirement; `nil` spends ``spendingPerMonth``.
    public var retiredSpendingPerMonth: Decimal?
    /// A state pension a month, after tax, in today's money.
    public var statePensionPerMonth: Decimal?
    public var statePensionFromAge: Int?
    /// The age to retire at; `nil` is as early as possible.
    public var retirementAge: Int?
    /// The tax on investment gains and income, as a fraction (`0.26`).
    public var investmentTax: Decimal?

    public init(cash: Decimal? = nil, investments: Decimal? = nil, pension: Decimal? = nil,
                pensionFromAge: Int? = nil, home: Decimal? = nil, mortgage: Decimal? = nil,
                otherDebts: Decimal? = nil, payPerMonth: Decimal? = nil, pensionPerMonth: Decimal? = nil,
                spendingPerMonth: Decimal? = nil,
                retiredSpendingPerMonth: Decimal? = nil, statePensionPerMonth: Decimal? = nil,
                statePensionFromAge: Int? = nil, retirementAge: Int? = nil, investmentTax: Decimal? = nil) {
        self.cash = cash
        self.investments = investments
        self.pension = pension
        self.pensionFromAge = pensionFromAge
        self.home = home
        self.mortgage = mortgage
        self.otherDebts = otherDebts
        self.payPerMonth = payPerMonth
        self.pensionPerMonth = pensionPerMonth
        self.spendingPerMonth = spendingPerMonth
        self.retiredSpendingPerMonth = retiredSpendingPerMonth
        self.statePensionPerMonth = statePensionPerMonth
        self.statePensionFromAge = statePensionFromAge
        self.retirementAge = retirementAge
        self.investmentTax = investmentTax
    }

    /// Whether any amount is negative: first launch waits until it's fixed.
    public var hasNegativeAmount: Bool {
        [cash, investments, pension, home, mortgage, otherDebts, payPerMonth, pensionPerMonth, spendingPerMonth,
         retiredSpendingPerMonth, statePensionPerMonth, investmentTax]
            .contains { ($0 ?? 0) < 0 }
    }

    /// Whether the home's mortgage is asked: once the home has a value.
    /// A mortgage without one is left out.
    public var asksForMortgage: Bool {
        (home ?? 0) > 0
    }

    /// Whether the pension pot's age is asked: once it has an amount, or
    /// something is paid into it.
    public var asksForPensionAge: Bool {
        (pension ?? 0) > 0 || (pensionPerMonth ?? 0) > 0
    }

    /// Whether anything you have today was entered (above 0); a mortgage
    /// and other debts are owed, not had.
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
///   the home as property and its mortgage as a debt, both of which plans
///   leave out, so net worth counts the home's equity, and other debts as a
///   loan, which plans leave out too, since its repayments are part of the
///   spending. A pension pot with nothing in it but money paid in a month
///   is an estimate of 0, so the plan's contribution has an account to go
///   into. They are what the first
///   answer stands on until imported files replace them; closing an
///   estimate with the real account as its successor retires it.
/// - **The plan.** Pay and spending a month (`setMonthly`), the age to
///   retire at, the state pension and the tax rate; what's paid into the
///   pension a month is a yearly contribution into its estimate, on top of
///   pay (``addPensionContribution(_:to:in:)``).
public enum StarterSetup {
    /// The tag that marks an account as a starting estimate
    /// (``Model/Account/startingEstimateTag``).
    public static let estimateTag = Account.startingEstimateTag

    /// An estimate account's note.
    static let estimateNote = "A round amount from first launch. Close it once your real accounts are imported."

    /// The state pension's name in a plan, and on the plan's cards.
    public static let statePensionName = "State pension"

    /// A pension pot's mix: balanced, as most default funds are.
    static let pensionMix: AssetMix = [.equity: Decimal(string: "0.6") ?? 0, .bonds: Decimal(string: "0.4") ?? 0]

    /// The estimate accounts for `answers`, opened on `date`, in `currency`,
    /// each with its amount (debts' as owed, above 0); `id` makes each
    /// one's ID from its name. Amounts of 0 or less get none, nor does a
    /// mortgage without a home (``StarterAnswers/asksForMortgage``), but a
    /// pension pot something is paid into gets one of 0.
    public static func estimateAccounts(for answers: StarterAnswers, currency: CurrencyCode, country: CountryCode?,
                                        on date: CalendarDate, id: (String) -> AccountID) -> [(Account, Decimal)] {
        func estimate(_ name: String, _ kind: AccountKind, _ amount: Decimal?,
                      configure: (inout Account) -> Void = { _ in }) -> (Account, Decimal)? {
            guard let amount, amount >= 0 else { return nil }
            let fullName = "\(name) (estimate)"
            var account = Account(id: id(fullName), name: fullName, kind: kind, currency: currency, opened: date)
            account.country = country
            account.tags = [estimateTag]
            account.notes = estimateNote
            configure(&account)
            return (account, amount)
        }
        return [
            estimate("Cash and savings", .savings, positive(answers.cash)),
            estimate("Investments", .other, positive(answers.investments)) { $0.assetClasses = .single(.equity) },
            estimate("Pension", .pensionFund, pensionPot(answers)) { account in
                account.assetClasses = pensionMix
                account.availableFromAge = answers.pensionFromAge
            },
            estimate("Home", .property, positive(answers.home)) { $0.includeIn = IncludeIn(plan: false) },
            estimate("Mortgage", .mortgage, answers.asksForMortgage ? positive(answers.mortgage) : nil) {
                $0.includeIn = IncludeIn(plan: false)
            },
            estimate("Other debts", .loan, positive(answers.otherDebts)) { $0.includeIn = IncludeIn(plan: false) },
        ].compactMap { $0 }
    }

    /// `amount` when it's above 0.
    private static func positive(_ amount: Decimal?) -> Decimal? {
        amount.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The pension pot's estimate: its amount above 0, else 0 when
    /// something is paid into it a month.
    private static func pensionPot(_ answers: StarterAnswers) -> Decimal? {
        positive(answers.pension) ?? (positive(answers.pensionPerMonth) == nil ? nil : 0)
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
            // Debts are stored as negative balances.
            let balance = account.kind.isLiability ? -amount : amount
            library.upsert(Valuation(account: account.id, date: date, balance: balance,
                                     note: "Estimate from first launch", source: .manual))
        }
        return estimates.map(\.0.id)
    }

    /// `plan` with the answers' pay and spending a month (in retirement
    /// too, unless it's given on its own), the age to retire at, the state
    /// pension (in place of the plan's pensions, when one above 0 is given)
    /// and the tax on investments.
    public static func complete(_ plan: inout PlanDocument, with answers: StarterAnswers, asOf: CalendarDate) {
        plan.setMonthly(payPerMonth: answers.payPerMonth, spendingPerMonth: answers.spendingPerMonth, asOf: asOf)
        if let retired = answers.retiredSpendingPerMonth, retired >= 0 {
            plan.spending.retired = retired * 12
        }
        plan.setRetirementAge(answers.retirementAge)
        if let perMonth = answers.statePensionPerMonth, perMonth > 0, let fromAge = answers.statePensionFromAge {
            plan.pensions = [PlanPension(name: statePensionName, fromAge: fromAge, perYear: perMonth * 12)]
        }
        if let rate = answers.investmentTax, rate >= 0 {
            plan.tax.investmentRate = rate
        }
    }

    /// `plan` with what ``StarterAnswers/pensionPerMonth`` pays into the
    /// pension a month as a yearly contribution into the pension pot's
    /// estimate in `library` until retirement, and each work phase's
    /// income that much higher, since it's paid before your pay reaches
    /// you: what pay less spending saves stays where it was, and the
    /// pension gets the contribution on top. Nothing without an amount
    /// above 0 or the estimate (``addEstimates(_:to:on:taken:)``).
    public static func addPensionContribution(_ answers: StarterAnswers, to plan: inout PlanDocument,
                                              in library: Library) {
        guard let perMonth = positive(answers.pensionPerMonth),
              let pot = library.openStartingEstimates.first(where: { $0.kind == .pensionFund }) else { return }
        let perYear = perMonth * 12
        plan.contributions.append(PlanContribution(account: pot.id, perYear: perYear))
        for index in plan.work.indices {
            plan.work[index].netIncome = (plan.work[index].netIncome ?? 0) + perYear
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

    /// `amount` to two significant figures: 420 → 420, 1234 → 1200; for
    /// round amounts in sentences ("you save about 1.400 € a month").
    public static func roundedToTwoFigures(_ amount: Decimal) -> Decimal {
        let value = amount.doubleValue
        guard value >= 100, value.isFinite else { return amount.rounded(scale: 0) }
        return amount.rounded(scale: 1 - Int(log10(value).rounded(.down)))
    }
}

extension Account {
    /// The kinds of real accounts that replace this starting estimate:
    /// current and savings accounts replace cash and savings; investment
    /// accounts the investments; pension funds and TFR the pension;
    /// property the home; a mortgage the mortgage; loans and credit cards
    /// other debts.
    public var kindsReplacingEstimate: Set<AccountKind> {
        switch kind {
        case .savings, .cash: [.cash, .savings]
        case .pensionFund, .tfr: [.pensionFund, .tfr]
        case .property: [.property]
        case .mortgage: [.mortgage]
        case .loan, .creditCard: [.loan, .creditCard]
        default: [.brokerage, .crypto, .metals, .other]
        }
    }
}

/// What replacing a starting estimate with real accounts does to it
/// (``Library/replacement(of:)``).
public enum EstimateReplacement: Hashable, Sendable {
    /// The real accounts have values on or before the day it was
    /// estimated, so it goes: its one value would count twice.
    case remove
    /// It counts until the day before the real accounts' first value, and
    /// `successor` continues it, so charts stay continuous.
    case close(on: CalendarDate, successor: AccountID)
}

extension Library {
    /// The open starting estimates, by name: what the first answer stands
    /// on until imported files replace them.
    public var openStartingEstimates: [Account] {
        accounts.values.filter { $0.isStartingEstimate && !$0.isClosed }
            .sorted { $0.name < $1.name }
    }

    /// The open accounts with values that can replace `estimate`: not
    /// estimates themselves, of a kind that replaces it
    /// (``Account/kindsReplacingEstimate``), by name.
    public func accountsReplacing(_ estimate: Account) -> [Account] {
        let kinds = estimate.kindsReplacingEstimate
        return accounts.values
            .filter { !$0.isStartingEstimate && !$0.isClosed && kinds.contains($0.kind) }
            .filter { !valuations(for: $0.id).isEmpty }
            .sorted { $0.name < $1.name }
    }

    /// How the accounts that can replace `estimate` replace it
    /// (``accountsReplacing(_:)``); `nil` without any. Its successor is the
    /// one of its own kind (else any) whose values start first.
    public func replacement(of estimate: Account) -> EstimateReplacement? {
        let starts = accountsReplacing(estimate).compactMap { account in
            valuations(for: account.id).map(\.date).min().map { (account, $0) }
        }
        guard let first = starts.map(\.1).min() else { return nil }
        if first <= estimate.opened { return .remove }
        let sameKind = starts.filter { $0.0.kind == estimate.kind }
        let successor = (sameKind.isEmpty ? starts : sameKind)
            .min { ($0.1, $0.0.id) < ($1.1, $1.0.id) }
        guard let successor else { return nil }
        return .close(on: first.adding(days: -1), successor: successor.0.id)
    }

    /// Points the plans' contributions into `estimate` at the account that
    /// takes its place under `replacement`: a close's successor, else the
    /// one of its kind (else any) of the accounts replacing it, by name.
    /// Without this, replacing the pension's estimate would leave its
    /// contribution outside the plan while the work phase still pays it,
    /// so it would be saved where you can draw it.
    public mutating func handOverContributions(of estimate: Account, replacement: EstimateReplacement) {
        let replacing = accountsReplacing(estimate)
        let heir: AccountID? = switch replacement {
        case .close(_, let successor): successor
        case .remove: (replacing.first { $0.kind == estimate.kind } ?? replacing.first)?.id
        }
        guard let heir else { return }
        for (id, plan) in plans where plan.contributions.contains(where: { $0.account == estimate.id }) {
            for index in plan.contributions.indices where plan.contributions[index].account == estimate.id {
                plans[id]?.contributions[index].account = heir
            }
        }
    }

    /// Makes the open starting estimates accounts of your own whose values
    /// you type (UI.md, "Empty states and first launch": *Type your
    /// balances*): each loses its tag and its first-launch note, takes the
    /// name in `names` (else its own without "(estimate)") and typed values
    /// (`values: typed`); the investments become a brokerage account
    /// recorded as a balance. Their values stay, so the next check-in
    /// counts them as any account's. Returns their IDs, by name.
    @discardableResult
    public mutating func adoptStartingEstimates(names: [AccountID: String] = [:]) -> [AccountID] {
        let estimates = openStartingEstimates
        for estimate in estimates {
            var account = estimate
            account.tags.removeAll { $0 == Account.startingEstimateTag }
            let typed = names[account.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            account.name = typed.isEmpty ? Self.nameWithoutEstimate(account.name) : typed
            if account.notes == StarterSetup.estimateNote { account.notes = nil }
            if account.kind == .other {
                account.kind = .brokerage
                account.valuation = .balance
            }
            account.values = .typed
            accounts[account.id] = account
        }
        return estimates.map(\.id)
    }

    /// "Cash and savings" for "Cash and savings (estimate)".
    static func nameWithoutEstimate(_ name: String) -> String {
        let suffix = " (estimate)"
        return name.hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
    }

    /// Whether every value on `date` is a starting estimate's (and there
    /// is one): first launch's sketch, which saves no yearly baseline.
    public func valuesAreStartingEstimates(on date: CalendarDate) -> Bool {
        let accountIDs = Set(months[date.yearMonth]?.valuations.filter { $0.date == date }.map(\.account) ?? [])
        return !accountIDs.isEmpty && accountIDs.allSatisfy { accounts[$0]?.isStartingEstimate == true }
    }
}
