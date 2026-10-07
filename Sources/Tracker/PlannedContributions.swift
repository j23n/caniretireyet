import Foundation
import Model

/// What the main plan pays into each account (its `contributions`), the new
/// money of a balance the check-in asks about when it was left empty
/// (PROGRESS.md, "Data this needs from day one"): a pension fund, TFR,
/// property or other balance, whose balance alone can't tell what was paid
/// in from what it earned.
public struct PlannedContributions: Hashable, Sendable {
    private var byAccount: [AccountID: [PlanContribution]]
    /// When contributions until retirement stop: the plan's retirement age
    /// from the birth date; `nil` when the plan finds the age, or without a
    /// birth date, and then they go on.
    private var retirement: CalendarDate?

    /// None: nothing is paid into any account.
    public init() {
        byAccount = [:]
        retirement = nil
    }

    /// The main plan's, or none without one.
    public init(library: Library) {
        if let id = library.settings.mainPlan, let plan = library.plans[id] {
            self.init(plan: plan, birthDate: library.settings.person?.birthDate)
        } else {
            self.init()
        }
    }

    public init(plan: PlanDocument, birthDate: CalendarDate?) {
        byAccount = Dictionary(grouping: plan.contributions, by: \.account)
        retirement = plan.retirement.age.age.flatMap { age in birthDate?.adding(years: age) }
    }

    /// What the plan pays into `account` after `from` through `to`, in the
    /// library's base currency: a yearly amount for the share of each year's
    /// days it covers, while it runs (until its date, or retirement); a
    /// one-off amount spread over its year.
    public func amount(into account: AccountID, after from: CalendarDate, through to: CalendarDate) -> Decimal {
        guard from < to, let contributions = byAccount[account] else { return 0 }
        var total: Decimal = 0
        for contribution in contributions {
            if let amount = contribution.amount, let year = contribution.year {
                total += amount * Self.share(of: year, after: from, through: to)
            } else if contribution.perYear != 0 {
                let stop: CalendarDate? = switch contribution.effectiveUntil {
                case .date(let date): date
                case .retirement: retirement
                }
                let last = min(to, stop ?? to)
                guard from < last else { continue }
                for year in from.year...last.year {
                    total += contribution.perYear * Self.share(of: year, after: from, through: last)
                }
            }
        }
        return total
    }

    /// The share of `year`'s days that are after `from` through `to`.
    static func share(of year: Int, after from: CalendarDate, through to: CalendarDate) -> Decimal {
        guard let first = CalendarDate(year: year, month: 1, day: 1),
              let last = CalendarDate(year: year, month: 12, day: 31) else { return 0 }
        let before = first.adding(days: -1)
        let start = max(from, before)
        let end = min(to, last)
        guard start < end else { return 0 }
        return Decimal(start.days(to: end)) / Decimal(before.days(to: last))
    }
}
