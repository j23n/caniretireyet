import Foundation
import Model

extension Library {
    /// Every check across the library's files, as warnings in the file of
    /// what's wrong, sorted by path. Loading reports what each file shows on
    /// its own (Storage's `LoadReport`); the app's Sync screen and
    /// `retire validate` show both. The library is used as it is: these
    /// only point out what to fix.
    ///
    /// - records of accounts and instruments that don't exist, and a
    ///   successor or main plan that doesn't exist;
    /// - money in and out, one-offs, tax and interest that aren't counted
    ///   (``Model/Valuation/moneyInOut(on:)``);
    /// - valuations dated outside their account's opened and closed dates,
    ///   and positive balances of debts (debts are negative);
    /// - check-ins whose net worth can't be fully computed (a missing price
    ///   or FX rate);
    /// - plans naming accounts that don't exist, and import profiles naming
    ///   accounts or instruments that don't exist, or with a layout this
    ///   version doesn't import;
    /// - trades that can't be applied as they are (``Valuator/tradeIssues(for:)``).
    ///
    /// `valuator` is the library's, when the caller has one.
    public func problems(valuator: Valuator? = nil) -> [LibraryIssue] {
        var checks = LibraryChecks(library: self, valuator: valuator ?? Valuator(library: self))
        checks.references()
        checks.moneyInOut()
        checks.valuationDates()
        checks.debtSigns()
        checks.incompleteCheckIns()
        checks.plans()
        checks.importProfiles()
        checks.trades()
        return checks.issues.sortedByPath()
    }
}

/// The checks of ``Model/Library/problems(valuator:)``, collecting warnings.
private struct LibraryChecks {
    let library: Library
    let valuator: Valuator
    var issues: [LibraryIssue] = []

    private mutating func warn(_ file: LibraryFile, _ message: String) {
        issues.append(LibraryIssue(path: file.path, message: message, severity: .warning))
    }

    private var sortedMonths: [(key: YearMonth, value: MonthFile)] {
        library.months.sorted { $0.key < $1.key }
    }

    /// Records that refer to accounts, instruments or plans that don't exist.
    mutating func references() {
        for (month, file) in sortedMonths {
            let accounts = Set(file.valuations.map(\.account) + file.trades.map(\.account))
                .filter { library.accounts[$0] == nil }
            let instruments = Set(file.valuations.flatMap { $0.positions.map(\.instrument) }
                + file.prices.map(\.instrument) + file.trades.compactMap(\.instrument))
                .filter { library.instruments[$0] == nil }
            if !accounts.isEmpty {
                warn(.month(month), "Refers to accounts that don't exist: "
                    + "\(accounts.sorted().map(\.rawValue).joined(separator: ", ")).")
            }
            if !instruments.isEmpty {
                warn(.month(month), "Refers to instruments that don't exist: "
                    + "\(instruments.sorted().map(\.rawValue).joined(separator: ", ")).")
            }
        }
        for account in library.sortedAccounts {
            if let successor = account.successor, library.accounts[successor] == nil {
                warn(.account(account.id), "The successor \"\(successor)\" doesn't exist.")
            }
        }
        if let plan = library.settings.mainPlan, library.plans[plan] == nil {
            warn(.settings, "The main plan \"\(plan)\" doesn't exist.")
        }
    }

    /// Money in and out, one-offs and tax that summaries leave out, by the
    /// rule for what counts (``Model/Valuation/moneyInOut(on:)``), and
    /// interest on an account whose kind doesn't record it.
    mutating func moneyInOut() {
        for valuation in library.allValuations {
            guard let account = library.accounts[valuation.account] else { continue }
            let whose = "The valuation of \(account.id) on \(valuation.date)"
            for reason in valuation.moneyInOut(on: account.kind).notCounted {
                warn(.month(valuation.date.yearMonth), "\(whose) \(reason); it isn't counted.")
            }
            if valuation.interest != nil, !account.kind.recordsInterest {
                warn(.month(valuation.date.yearMonth), "\(whose) records interest, but only savings accounts do; "
                    + "it isn't used.")
            }
        }
    }

    /// Valuations before an account opened or after it closed don't count.
    mutating func valuationDates() {
        for (month, file) in sortedMonths {
            for (id, valuations) in Dictionary(grouping: file.valuations, by: \.account).sorted(by: { $0.key < $1.key }) {
                guard let account = library.accounts[id] else { continue }
                let dates = valuations.map(\.date).sorted()
                if let first = dates.first(where: { $0 < account.opened }) {
                    warn(.month(month), "\(id) has a valuation on \(first) but opened on \(account.opened), so it "
                        + "doesn't count. Set `opened` earlier if the account was open then.")
                }
                if let closed = account.closed, let first = dates.first(where: { $0 > closed }) {
                    warn(.month(month), "\(id) has a valuation on \(first) but closed on \(closed), so it doesn't "
                        + "count.")
                }
            }
        }
    }

    /// Loans, mortgages and credit cards are recorded as negative balances.
    mutating func debtSigns() {
        for (month, file) in sortedMonths {
            let positive = file.valuations.filter { valuation in
                guard let account = library.accounts[valuation.account], account.kind.isLiability,
                      let balance = valuation.balance else { return false }
                return balance > 0
            }
            for (id, valuations) in Dictionary(grouping: positive, by: \.account).sorted(by: { $0.key < $1.key }) {
                let kind = library.accounts[id]?.kind.rawValue ?? ""
                let dates = valuations.map(\.date).sorted().map(\.description)
                warn(.month(month), "\(id) is a debt (\(kind)) but has a positive balance on "
                    + "\(Wording.list(dates)). Debts are recorded as negative amounts.")
            }
        }
    }

    /// Check-ins whose value can't be computed: a position without a price,
    /// or an amount without an FX rate. Each problem is reported once, in the
    /// month file of the first check-in it affects.
    mutating func incompleteCheckIns() {
        var dates: [ValuationProblem: [CalendarDate]] = [:]
        var order: [ValuationProblem] = []
        for date in library.checkInDates {
            for problem in valuator.netWorth(on: date).problems {
                if case .noValuation = problem { continue }
                if dates[problem] == nil { order.append(problem) }
                dates[problem, default: []].append(date)
            }
        }
        for problem in order {
            guard let affected = dates[problem], let first = affected.first, let last = affected.last else { continue }
            let when = affected.count == 1 ? "on \(first)"
                : "on \(affected.count) check-ins, \(first) to \(last)"
            warn(.month(first.yearMonth), "Net worth can't be fully computed \(when): \(problem).")
        }
    }

    /// Plans that name accounts that don't exist.
    mutating func plans() {
        for plan in library.plans.values.sorted(by: { $0.id < $1.id }) {
            for (index, contribution) in plan.contributions.enumerated()
            where library.accounts[contribution.account] == nil {
                warn(.plan(plan.id), "contributions[\(index)].account: the account \"\(contribution.account)\" "
                    + "doesn't exist.")
            }
            for (index, account) in plan.portfolio.exclude.enumerated() where library.accounts[account] == nil {
                warn(.plan(plan.id), "portfolio.exclude[\(index)]: the account \"\(account)\" doesn't exist.")
            }
        }
    }

    /// Import profiles that name accounts or instruments that don't exist,
    /// or that this version can't use.
    mutating func importProfiles() {
        for profile in library.importProfiles.values.sorted(by: { $0.id < $1.id }) {
            let file = LibraryFile.importProfile(profile.id)
            guard profile.layout.isKnown else {
                warn(file, "layout: \"\(profile.layout)\" isn't a layout this version imports, so the profile is "
                    + "kept but not offered.")
                continue
            }
            let accounts = Set(profile.columns.compactMap(\.account) + [profile.constants.account].compactMap { $0 }
                + profile.matches.accounts.values).filter { library.accounts[$0] == nil }
            let instruments = Set(profile.columns.compactMap(\.instrument)
                + [profile.constants.instrument].compactMap { $0 } + profile.matches.instruments.values)
                .filter { library.instruments[$0] == nil }
            if !accounts.isEmpty {
                warn(file, "Refers to accounts that don't exist: "
                    + "\(accounts.sorted().map(\.rawValue).joined(separator: ", ")). Importing proposes new ones.")
            }
            if !instruments.isEmpty {
                warn(file, "Refers to instruments that don't exist: "
                    + "\(instruments.sorted().map(\.rawValue).joined(separator: ", ")). Importing proposes new ones.")
            }
        }
    }

    /// Trades that can't be applied as they are (docs/TRADES.md, "Checks"),
    /// in the month file of each.
    mutating func trades() {
        for issue in valuator.tradeIssues() {
            warn(.month(issue.date.yearMonth), "\(issue.account): \(issue.message)")
        }
    }
}
