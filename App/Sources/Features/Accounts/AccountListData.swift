import Foundation
import Model
import Tracker

// The account list's rows, groups and subtotals, for the Accounts tab and
// the sidebar, computed without SwiftUI so they can be checked on Linux.

/// One account in the list, valued.
struct AccountListItem: Hashable, Sendable, Identifiable {
    var account: Account
    /// The date the row reports on: today, or the closing date.
    var date: CalendarDate
    /// The value in the base currency on ``date``.
    var value: Decimal
    /// Set when the latest value is too old (open accounts that hold
    /// something only: ``AccountStaleness``).
    var stale: StaleAccount?
    /// The last 12 months in the account's own currency (no exchange rate
    /// needed), for the sparkline; values that can't be worked out are
    /// incomplete, drawn as gaps.
    var sparkline: [ChartPoint]

    var id: AccountID { account.id }

    /// `includesSparkline: false` leaves ``sparkline`` empty, for places that
    /// don't draw it (the sidebar).
    init(account: Account, valuator: Valuator, date: CalendarDate, stalenessThreshold: Int?,
         includesSparkline: Bool = true) {
        self.account = account
        self.date = date
        value = valuator.value(of: account.id, on: date)?.knownValue ?? 0
        stale = stalenessThreshold.flatMap { AccountStaleness.stale(account.id, valuator: valuator, on: date,
                                                                    threshold: $0) }
        let yearAgo = date.adding(months: -12)
        // A trades account's history starts with its first valuation or trade.
        let first = valuator.firstRecordDate(of: account.id)
        if includesSparkline, let first, first <= date {
            sparkline = valuator.series(of: account.id, in: .account, from: max(yearAgo, first), through: date)
                .chartPoints
        } else {
            sparkline = []
        }
    }
}

/// When an open account asks for a new value (UI.md, "Accounts"): it's
/// stale when its latest value is older than the threshold, unless it holds
/// nothing (a zero balance, or no cash and no quantity). An empty account
/// has nothing to check in, so it isn't marked stale anywhere (the list,
/// the sidebar, the detail, *Needs attention*); once it's been empty for
/// longer than the threshold, its detail suggests closing it instead.
enum AccountStaleness {
    /// `account`'s staleness on `date`, or `nil` when it's up to date, not
    /// open, or empty.
    static func stale(_ account: AccountID, valuator: Valuator, on date: CalendarDate,
                      threshold: Int) -> StaleAccount? {
        guard let stale = valuator.staleness(of: account, on: date, threshold: threshold) else { return nil }
        return valuator.emptySince(of: account, on: date) == nil ? stale : nil
    }

    /// The day an open account has held nothing since, when that's more
    /// than `threshold` days before `date`: the detail offers to close it
    /// on that day. `nil` for a closed account, or one that holds something.
    static func emptySince(_ account: Account, valuator: Valuator, on date: CalendarDate,
                           threshold: Int) -> CalendarDate? {
        guard !account.isClosed, let since = valuator.emptySince(of: account.id, on: date),
              since.days(to: date) > threshold
        else { return nil }
        return since
    }
}

/// One group of the list (Cash, Investments, …) with its subtotal.
struct AccountListSection: Hashable, Sendable, Identifiable {
    var group: AccountGroup
    var items: [AccountListItem]

    var id: AccountGroup { group }

    /// The sum of the rows, in the base currency.
    var subtotal: Decimal {
        items.reduce(Decimal(0)) { $0 + $1.value }
    }
}

/// The account list for a search (UI.md, "Accounts"): the Accounts tab's,
/// and without sparklines the sidebar's, so the two always agree.
struct AccountList: Hashable, Sendable {
    /// Open accounts by group, in display order; only groups that have some.
    var sections: [AccountListSection]
    /// Closed accounts, most recently closed first.
    var closed: [AccountListItem]

    /// The value whose text is widest among the rows (open and closed), in
    /// the base currency. Each row reserves this width for its amount, so the
    /// amounts line up on the right and the sparklines in a column beside them.
    func widestValue(currency: CurrencyCode, locale: Locale = .current) -> Decimal? {
        let values = sections.flatMap(\.items).map(\.value) + closed.map(\.value)
        return values.max { lhs, rhs in
            AmountFormat.amount(lhs, currency: currency, locale: locale).count
                < AmountFormat.amount(rhs, currency: currency, locale: locale).count
        }
    }

    /// How many open accounts are shown.
    var openCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }

    var isEmpty: Bool {
        sections.isEmpty && closed.isEmpty
    }

    /// The open accounts' values added up, in the base currency: the sum of
    /// the sections' subtotals (accounts left out of net worth too, as listed).
    var openTotal: Decimal {
        sections.reduce(Decimal(0)) { $0 + $1.subtotal }
    }

    /// *Closed (3)*.
    var closedTitle: String {
        "Closed (\(closed.count))"
    }

    /// `includesSparklines: false` leaves every row's sparkline empty.
    init(library: Library, valuator: Valuator, query: String = "", today: CalendarDate, stalenessThreshold: Int,
         includesSparklines: Bool = true) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let accounts = library.accounts.values.filter { Self.matches($0, query: trimmed) }
        let open = accounts.filter { !Self.listsAsClosed($0, today: today) }.sortedForDisplay()
        let closedAccounts = accounts.filter { Self.listsAsClosed($0, today: today) }
            .sorted { ($0.closed ?? $0.opened, $1.name) > ($1.closed ?? $1.opened, $0.name) }

        var sections: [AccountListSection] = []
        for account in open {
            let item = AccountListItem(account: account, valuator: valuator, date: today,
                                       stalenessThreshold: stalenessThreshold, includesSparkline: includesSparklines)
            if let index = sections.firstIndex(where: { $0.group == account.group }) {
                sections[index].items.append(item)
            } else {
                sections.append(AccountListSection(group: account.group, items: [item]))
            }
        }
        self.sections = sections
        closed = closedAccounts.map { account in
            AccountListItem(account: account, valuator: valuator, date: account.closed ?? today,
                            stalenessThreshold: nil, includesSparkline: includesSparklines)
        }
    }

    /// Whether `query` searches: it has more than spaces. A blank query
    /// lists every account, as an empty one does.
    static func isSearching(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether `account` is listed with the closed accounts on `today`: it
    /// closed before today. One closing today or later is still open.
    static func listsAsClosed(_ account: Account, today: CalendarDate) -> Bool {
        account.isClosed && !account.isOpen(on: today)
    }

    /// Whether `account` matches a search: its name, institution, kind,
    /// group, tags or notes contain every word of `query`, ignoring case and
    /// accents. An empty query matches everything.
    static func matches(_ account: Account, query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = ([account.name, account.institution ?? "", account.kind.displayName, account.group.description,
                         account.notes ?? "", account.currency.rawValue] + account.tags)
            .joined(separator: " ")
        return words.allSatisfy { word in
            haystack.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
