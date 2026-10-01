import Foundation
import Model
import Tracker

// The account list's rows, groups and subtotals, computed without SwiftUI so
// they can be checked on Linux.

/// Which accounts the list shows: the sidebar has one place per group.
enum AccountsFilter: Hashable, Sendable {
    /// Every open account, grouped; closed ones in a collapsed section.
    case all
    /// Open accounts in one group.
    case group(AccountGroup)
    /// Closed accounts only.
    case closed
}

/// One account in the list, valued.
struct AccountListItem: Hashable, Sendable, Identifiable {
    var account: Account
    /// The date the row reports on: today, or the closing date.
    var date: CalendarDate
    /// The value in the base currency on ``date``.
    var value: Decimal
    /// Whether the value is fully known (no missing price or rate).
    var isComplete: Bool
    /// Set when the latest value is too old (open accounts only).
    var stale: StaleAccount?
    /// The last 12 months, for the sparkline.
    var sparkline: [ChartPoint]

    var id: AccountID { account.id }

    /// `includesSparkline: false` leaves ``sparkline`` empty, for places that
    /// don't draw it (the sidebar).
    init(account: Account, valuator: Valuator, date: CalendarDate, stalenessThreshold: Int?,
         includesSparkline: Bool = true) {
        self.account = account
        self.date = date
        let value = valuator.value(of: account.id, on: date)
        self.value = value?.knownValue ?? 0
        isComplete = value?.isComplete ?? true
        stale = stalenessThreshold.flatMap { valuator.staleness(of: account.id, on: date, threshold: $0) }
        let yearAgo = date.adding(months: -12)
        // A trades account's history starts with its first valuation or trade.
        let first = valuator.firstRecordDate(of: account.id)
        if includesSparkline, let first, first <= date {
            sparkline = valuator.series(of: account.id, from: max(yearAgo, first), through: date).chartPoints
        } else {
            sparkline = []
        }
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

/// The account list for one filter and search (UI.md, "Accounts").
struct AccountList: Hashable, Sendable {
    /// Open accounts by group, in display order.
    var sections: [AccountListSection]
    /// Closed accounts, most recently closed first.
    var closed: [AccountListItem]
    /// Net worth today (every open account included in it).
    var netWorth: Decimal

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

    /// `includesSparklines: false` leaves every row's sparkline empty.
    init(library: Library, valuator: Valuator, filter: AccountsFilter, query: String = "", today: CalendarDate,
         stalenessThreshold: Int, includesSparklines: Bool = true) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let accounts = library.accounts.values.filter { Self.matches($0, query: trimmed) }
        let open = accounts.filter { !Self.listsAsClosed($0, today: today) }.sortedForDisplay()
        let closedAccounts = accounts.filter { Self.listsAsClosed($0, today: today) }
            .sorted { ($0.closed ?? $0.opened, $1.name) > ($1.closed ?? $1.opened, $0.name) }

        var sections: [AccountListSection] = []
        if filter != .closed {
            for account in open {
                if case .group(let group) = filter, account.group != group { continue }
                let item = AccountListItem(account: account, valuator: valuator, date: today,
                                           stalenessThreshold: stalenessThreshold,
                                           includesSparkline: includesSparklines)
                if let index = sections.firstIndex(where: { $0.group == account.group }) {
                    sections[index].items.append(item)
                } else {
                    sections.append(AccountListSection(group: account.group, items: [item]))
                }
            }
        }
        self.sections = sections
        closed = filter == .all || filter == .closed
            ? closedAccounts.map { account in
                AccountListItem(account: account, valuator: valuator, date: account.closed ?? today,
                                stalenessThreshold: nil, includesSparkline: includesSparklines)
            }
            : []
        netWorth = valuator.netWorth(on: today).total
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
