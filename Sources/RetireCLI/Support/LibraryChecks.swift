import Foundation
import Model
import Storage
import TaxKit
import Tracker

/// Checks across files that loading doesn't make, for `retire validate`.
/// Storage already points out records of unknown accounts and instruments,
/// unknown successors and a missing main plan; these add:
///
/// - valuations dated outside their account's opened and closed dates;
/// - positive balances of debt accounts (debts are negative);
/// - check-ins whose net worth can't be computed (a missing price or FX rate);
/// - plans naming accounts, tax systems, regimes or pension schemes that don't exist;
/// - accounts with a tax wrapper no tax system defines;
/// - import profiles naming accounts or instruments that don't exist, or
///   with a layout this version doesn't import (a ledger journal's profile
///   written by an earlier version);
/// - trades that need their account's other trades or market data to check
///   (a missing FX rate, an opening without cost, a split of what isn't
///   held) and positions listed in a trades account's valuation that differ
///   from its trades (Storage points out the rest).
///
/// Everything found is a warning: the library loads and works regardless.
struct LibraryChecks {
    let library: Library
    let registry: TaxRegistry

    func issues() -> [LoadIssue] {
        var issues: [LoadIssue] = []
        issues += valuationDates()
        issues += debtSigns()
        issues += incompleteCheckIns()
        issues += planReferences()
        issues += wrappers()
        issues += importProfileReferences()
        issues += trades()
        return issues
    }

    /// The trade issues Tracker finds that loading doesn't (see `LibraryLoader.checkTrades`).
    private func trades() -> [LoadIssue] {
        let kinds: Set<TradeIssue.Kind> = [.missingFX, .unknownCost, .splitNotHeld, .reconciliation]
        return Valuator(library: library).tradeIssues().filter { kinds.contains($0.kind) }.map { issue in
            warning(LibraryFile.month(issue.date.yearMonth).path, "\(issue.account): \(issue.message)")
        }
    }

    private func warning(_ path: String, _ message: String) -> LoadIssue {
        LoadIssue(path: path, message: message, severity: .warning)
    }

    /// Valuations before an account opened or after it closed don't count.
    private func valuationDates() -> [LoadIssue] {
        var issues: [LoadIssue] = []
        for (month, file) in library.months.sorted(by: { $0.key < $1.key }) {
            let path = LibraryFile.month(month).path
            for (id, valuations) in Dictionary(grouping: file.valuations, by: \.account).sorted(by: { $0.key < $1.key }) {
                guard let account = library.accounts[id] else { continue }
                let early = valuations.map(\.date).filter { $0 < account.opened }.sorted()
                let late = valuations.map(\.date).filter { date in account.closed.map { date > $0 } ?? false }.sorted()
                if let first = early.first {
                    issues.append(warning(path, "\(id) has a valuation on \(first) but opened on \(account.opened), "
                        + "so it doesn't count. Set `opened` earlier if the account was open then."))
                }
                if let first = late.first, let closed = account.closed {
                    issues.append(warning(path, "\(id) has a valuation on \(first) but closed on \(closed), "
                        + "so it doesn't count."))
                }
            }
        }
        return issues
    }

    /// Loans, mortgages and credit cards are recorded as negative balances.
    private func debtSigns() -> [LoadIssue] {
        var issues: [LoadIssue] = []
        for (month, file) in library.months.sorted(by: { $0.key < $1.key }) {
            let positive = file.valuations.filter { valuation in
                guard let account = library.accounts[valuation.account], account.kind.isLiability,
                      let balance = valuation.balance else { return false }
                return balance > 0
            }
            for (id, valuations) in Dictionary(grouping: positive, by: \.account).sorted(by: { $0.key < $1.key }) {
                let kind = library.accounts[id]?.kind.rawValue ?? ""
                let dates = valuations.map(\.date).sorted()
                issues.append(warning(LibraryFile.month(month).path,
                    "\(id) is a debt (\(kind)) but has a positive balance on \(Format.list(dates.map(\.description))). "
                    + "Debts are recorded as negative amounts."))
            }
        }
        return issues
    }

    /// Check-ins whose value can't be computed: a position without a price,
    /// or an amount without an FX rate. Each problem is reported once, in the
    /// month file of the first check-in it affects.
    private func incompleteCheckIns() -> [LoadIssue] {
        let valuator = Valuator(library: library)
        var dates: [ValuationProblem: [CalendarDate]] = [:]
        var order: [ValuationProblem] = []
        for date in library.checkInDates {
            for problem in valuator.netWorth(on: date).problems {
                if case .noValuation = problem { continue }
                if dates[problem] == nil { order.append(problem) }
                dates[problem, default: []].append(date)
            }
        }
        return order.map { problem in
            let affected = dates[problem]!
            let when = affected.count == 1 ? "on \(affected[0])"
                : "on \(affected.count) check-ins, \(affected[0]) to \(affected[affected.count - 1])"
            return warning(LibraryFile.month(affected[0].yearMonth).path,
                           "Net worth can't be fully computed \(when): \(problem).")
        }
    }

    /// Plans that name what doesn't exist.
    private func planReferences() -> [LoadIssue] {
        var issues: [LoadIssue] = []
        let systems = registry.ids.joined(separator: ", ")
        for plan in library.plans.values.sorted(by: { $0.id < $1.id }) {
            let path = LibraryFile.plan(plan.id).path
            if let missing = PlanEdit.missingRate(for: plan, library: library) {
                issues.append(warning(path, "currency: \(missing)"))
            }
            for (index, contribution) in plan.contributions.enumerated() {
                if let scheme = contribution.pension {
                    if registry.pensionScheme(scheme.rawValue) == nil {
                        issues.append(warning(path, "contributions[\(index)].pension: \"\(scheme)\" isn't a pension "
                            + "scheme any tax system defines."))
                    }
                } else if library.accounts[contribution.account] == nil {
                    issues.append(warning(path, "contributions[\(index)].account: the account \"\(contribution.account)\" "
                        + "doesn't exist."))
                }
            }
            for (index, account) in plan.portfolio.exclude.enumerated() where library.accounts[account] == nil {
                issues.append(warning(path, "portfolio.exclude[\(index)]: the account \"\(account)\" doesn't exist."))
            }
            for (index, residence) in plan.tax.residence.enumerated()
            where registry.system(residence.system.rawValue) == nil {
                issues.append(warning(path, "tax.residence[\(index)].system: \"\(residence.system)\" isn't a tax "
                    + "system this version knows (\(systems))."))
            }
            for (index, overlay) in plan.tax.overlays.enumerated() where registry.regime(overlay.regime.rawValue) == nil {
                issues.append(warning(path, "tax.overlays[\(index)].regime: \"\(overlay.regime)\" isn't a regime any "
                    + "tax system defines."))
            }
            for (index, phase) in plan.work.enumerated() {
                if let regime = phase.regime, registry.regime(regime.rawValue) == nil {
                    issues.append(warning(path, "work[\(index)].regime: \"\(regime)\" isn't a regime any tax system "
                        + "defines."))
                }
            }
            for (index, pension) in plan.pensions.enumerated()
            where registry.pensionScheme(pension.scheme.rawValue) == nil {
                issues.append(warning(path, "pensions[\(index)].scheme: \"\(pension.scheme)\" isn't a pension scheme "
                    + "any tax system defines."))
            }
        }
        return issues
    }

    /// Accounts whose tax wrapper no tax system defines.
    private func wrappers() -> [LoadIssue] {
        library.sortedAccounts.compactMap { account in
            guard let wrapper = account.tax?.wrapper, registry.wrapper(wrapper.rawValue) == nil else { return nil }
            return warning(LibraryFile.account(account.id).path,
                           "tax.wrapper: \"\(wrapper)\" isn't a wrapper any tax system defines.")
        }.sorted { $0.path < $1.path }
    }

    /// Import profiles that name accounts or instruments that don't exist,
    /// or that this version can't use.
    private func importProfileReferences() -> [LoadIssue] {
        var issues: [LoadIssue] = []
        for profile in library.importProfiles.values.sorted(by: { $0.id < $1.id }) {
            guard profile.layout.isKnown else {
                issues.append(warning(LibraryFile.importProfile(profile.id).path, "layout: \"\(profile.layout)\" "
                    + "isn't a layout this version imports, so the profile is kept but not offered."))
                continue
            }
            let accounts = Set(profile.columns.compactMap(\.account) + [profile.constants.account].compactMap { $0 }
                + profile.matches.accounts.values).filter { library.accounts[$0] == nil }
            let instruments = Set(profile.columns.compactMap(\.instrument)
                + [profile.constants.instrument].compactMap { $0 } + profile.matches.instruments.values)
                .filter { library.instruments[$0] == nil }
            let path = LibraryFile.importProfile(profile.id).path
            if !accounts.isEmpty {
                issues.append(warning(path, "Refers to accounts that don't exist: "
                    + "\(accounts.sorted().map(\.rawValue).joined(separator: ", ")). Importing proposes new ones."))
            }
            if !instruments.isEmpty {
                issues.append(warning(path, "Refers to instruments that don't exist: "
                    + "\(instruments.sorted().map(\.rawValue).joined(separator: ", ")). Importing proposes new ones."))
            }
        }
        return issues
    }
}
