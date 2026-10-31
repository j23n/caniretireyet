import Foundation
import Glance
import Model
import Planner
import Tracker

// Today's words and what needs attention. Its numbers come from the
// package: the history chart (Tracker's `HistoryChartData`), the answer
// (the Planner's `LatestAnswer`, said as Glance's `LastMonday`). The views
// in this folder only lay them out.

extension HistoryRange {
    /// The label on the picker.
    var title: String { rawValue }

    /// How VoiceOver reads the label.
    var spokenTitle: String {
        switch self {
        case .oneYear: "1 year"
        case .threeYears: "3 years"
        case .fiveYears: "5 years"
        case .all: "All"
        }
    }
}

/// What Today's allocation bars group by (UI.md, "Allocation"),
/// remembered by its raw value.
extension BreakdownDimension {
    var title: String {
        switch self {
        case .assetClass: "Asset class"
        case .accountGroup: "Account group"
        case .currency: "Currency"
        case .institution: "Institution"
        case .liquidity: "Liquid vs locked"
        }
    }

    /// At most this many bars; the rest fold into "Other".
    var limit: Int? {
        switch self {
        case .institution, .currency: 7
        default: nil
        }
    }
}

// MARK: - Net worth and change

// The *Net worth* row and the accounts' header, net worth today with the
// change between the last two check-ins and since the end of last year, are
// Glance's `NetWorthGlance`, as the widgets have it. *This year* splits that
// change since the end of last year into markets, saved and other with
// Tracker's `Valuator.changeThisYear(asOf:)`, from the same 31 December
// (tested in TrackerTests, and against `NetWorthGlance` in GlanceTests).

// MARK: - The answer

/// Today's words that the package doesn't have (UI.md, "Today").
enum TodayText {
    /// How far off the last Monday is: "about 25 years from now", "6
    /// months from now", "under a month from now"; `nil` when it isn't
    /// after `today`.
    static func away(_ lastMonday: LastMonday, today: CalendarDate) -> String? {
        guard let countdown = RetirementCountdown(from: today, to: lastMonday.date) else { return nil }
        if countdown.years >= 2 {
            let years = countdown.years + (countdown.months >= 6 ? 1 : 0)
            return "about \(Wording.count(years, "year")) from now"
        }
        if countdown.totalMonths == 0 { return "under a month from now" }
        return "\(Wording.count(countdown.totalMonths, "month")) from now"
    }

    /// The age and how sure, on Today's dusk: "At 63 · in 9 of 10 futures".
    static func ageAndFutures(_ lastMonday: LastMonday) -> String {
        "At \(lastMonday.age) · in \(GlanceText.futures(lastMonday.confidence)) futures"
    }

    /// The title over your pay at the last check-in: "Your pay in
    /// September", or "Your pay since 15 Aug".
    static func payTitle(from: CalendarDate, to: CalendarDate, today: CalendarDate,
                         locale: Locale = .current) -> String {
        inPeriod("Your pay", from: from, to: to, today: today, locale: locale)
    }

    /// The title over how net worth moved at the last check-in: "Your net
    /// worth in September", or "Your net worth since 15 Aug".
    static func netWorthMovedTitle(from: CalendarDate, to: CalendarDate, today: CalendarDate,
                                   locale: Locale = .current) -> String {
        inPeriod("Your net worth", from: from, to: to, today: today, locale: locale)
    }

    /// `words` and the month the days cover, "in September", or the day
    /// they start, "since 15 Aug".
    private static func inPeriod(_ words: String, from: CalendarDate, to: CalendarDate, today: CalendarDate,
                                 locale: Locale) -> String {
        guard let month = GlanceText.coveredMonth(from: from, to: to) else {
            return "\(words) since \(AmountFormat.shortDate(from, relativeTo: today, locale: locale))"
        }
        return "\(words) in \(GlanceText.month(month, relativeTo: today, locale: locale))"
    }
}

// MARK: - What moved

/// A line of the *Your pay* or *Your net worth* tile (UI.md, "What moved
/// it"): what it is and its amount, signed by what it did to the money:
/// tax and spent are below zero.
struct TodayMovedLine: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case cameIn, pension, tax, spent, saved, markets, oneOff, startedWith, lost, other, total
    }

    let kind: Kind
    let amount: Decimal
    /// Whether it adds up the lines above it: *You saved* on the pay tile,
    /// *Net worth* on the other.
    var isSum = false

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .cameIn: "Came in"
        case .pension: "Pension"
        case .tax: "Tax"
        case .spent: "Spent"
        case .saved: "You saved"
        case .markets: "Markets"
        case .oneOff: "One-off"
        case .startedWith: "New accounts"
        case .lost: "Lost value"
        case .other: "Other"
        case .total: "Net worth"
        }
    }
}

/// The lines of the *Your pay* and *Your net worth* tiles, from Tracker's
/// `WhatMoved`, which add up exactly.
enum TodayMoved {
    /// What came in, the tax and what was spent, then what that left
    /// saved. The pension contributions are a line of their own when there
    /// are some; tax only when there's some.
    static func payLines(_ pay: WhatMoved.Pay) -> [TodayMovedLine] {
        var lines = [TodayMovedLine(kind: .cameIn, amount: pay.moneyIn)]
        if pay.pension != 0 { lines.append(TodayMovedLine(kind: .pension, amount: pay.pension)) }
        if pay.tax != 0 { lines.append(TodayMovedLine(kind: .tax, amount: -pay.tax)) }
        lines.append(TodayMovedLine(kind: .spent, amount: -pay.spent))
        lines.append(TodayMovedLine(kind: .saved, amount: pay.saved, isSum: true))
        return lines
    }

    /// The most lines between what was saved and markets, and net worth,
    /// before they fold into one *Other*: so the tile stays one row tall.
    static let otherLines = 2

    /// What was saved and markets, the rest when it isn't zero, then net
    /// worth's change. The rest is a line each (a one-off, what new
    /// accounts started with, lost value, what nothing explains), or one
    /// *Other* when there are more than ``otherLines``.
    static func netWorthLines(_ moved: WhatMoved) -> [TodayMovedLine] {
        var lines = [TodayMovedLine(kind: .saved, amount: moved.saved)]
        if moved.markets != 0 { lines.append(TodayMovedLine(kind: .markets, amount: moved.markets)) }
        let rest = [TodayMovedLine(kind: .oneOff, amount: moved.oneOffs),
                    TodayMovedLine(kind: .startedWith, amount: moved.startedWith),
                    TodayMovedLine(kind: .lost, amount: moved.lost),
                    TodayMovedLine(kind: .other, amount: moved.unexplained)]
            .filter { $0.amount != 0 }
        if rest.count > otherLines {
            lines.append(TodayMovedLine(kind: .other, amount: moved.other))
        } else {
            lines += rest
        }
        lines.append(TodayMovedLine(kind: .total, amount: moved.change, isSum: true))
        return lines
    }

    /// Where each line's bar runs on the net worth tile's steps: each
    /// line from where the one before it ended, and a sum from zero.
    static func steps(_ lines: [TodayMovedLine]) -> [ClosedRange<Decimal>] {
        var running: Decimal = 0
        return lines.map { line in
            if line.isSum { return min(0, line.amount)...max(0, line.amount) }
            let from = running
            running += line.amount
            return min(from, running)...max(from, running)
        }
    }

    /// The pay tile's ring: what was saved, spent and paid in tax, each as
    /// a share of what came in, as far as they're above zero.
    static func ring(_ pay: WhatMoved.Pay) -> [(kind: TodayMovedLine.Kind, share: Double)] {
        let parts: [(TodayMovedLine.Kind, Decimal)] = [(.saved, pay.saved), (.spent, pay.spent), (.tax, pay.tax)]
        let positive = parts.map { ($0.0, max($0.1, 0)) }
        let total = positive.reduce(Decimal(0)) { $0 + $1.1 }
        guard total > 0 else { return [] }
        return positive.filter { $0.1 > 0 }.map { (kind: $0.0, share: ($0.1 / total).doubleValue) }
    }
}

// MARK: - Needs attention

/// One thing on Today that needs you (UI.md, "Needs attention"): what it
/// is ("Fondo pensione"), a short line on why ("Last value in May"), and
/// the action its row offers ("Update").
struct TodayAttentionItem: Hashable, Sendable, Identifiable {
    /// Where tapping the item goes.
    enum Target: Hashable, Sendable {
        case account(AccountID)
        case instrument(InstrumentID)
        case plan
        /// Instruments, where prices and exchange rates are typed in.
        case instruments
        /// *Fill In Past Prices* (Instruments), for past prices and rates.
        case fillPastPrices
    }

    var id: String
    var systemImage: String
    var title: String
    var detail: String
    var target: Target
    /// The row's action, a verb or two: "Update", "Fill In".
    var action = "Open"
}

/// Finds what needs attention in the library's data: stale accounts,
/// accounts with problems in their trades, missing and outdated prices,
/// missing exchange rates, and past prices and rates the net-worth history
/// is missing (with *Fill In Past Prices*). The screen adds the library's
/// own state (sync conflicts, save errors) and plan warnings.
enum TodayAttention {
    static func items(library: Library, valuator: Valuator, on today: CalendarDate, stalenessThreshold: Int,
                      locale: Locale = .current) -> [TodayAttentionItem] {
        func accountName(_ id: AccountID) -> String { library.accounts[id]?.name ?? id.rawValue }
        func instrumentName(_ id: InstrumentID) -> String { library.instruments[id]?.name ?? id.rawValue }

        var items: [TodayAttentionItem] = []

        // An account that holds nothing has nothing to check in (AccountStaleness).
        for stale in valuator.staleAccounts(on: today, threshold: stalenessThreshold, in: .netWorth)
        where valuator.emptySince(of: stale.account, on: today) == nil {
            let name = accountName(stale.account)
            if let last = stale.lastValuation {
                items.append(TodayAttentionItem(
                    id: "stale.\(stale.account)", systemImage: "clock",
                    title: name,
                    detail: "Last value in \(GlanceText.month(last, relativeTo: today, locale: locale))",
                    target: .account(stale.account), action: "Update"))
            } else {
                items.append(TodayAttentionItem(
                    id: "stale.\(stale.account)", systemImage: "clock",
                    title: name, detail: "No value yet", target: .account(stale.account),
                    action: library.accounts[stale.account]?.acceptsTypedValues == true ? "Update" : "Import"))
            }
        }
        items += tradeProblems(library: library, valuator: valuator, locale: locale)

        // Today's missing prices, then rates; an account without a value is stale above.
        let gaps = MissingValues(valuator.netWorth(on: today).accounts)?.gaps ?? []
        var missingPrices: Set<InstrumentID> = []
        for gap in gaps {
            guard case .price(let instrument) = gap.item else { continue }
            missingPrices.insert(instrument)
            items.append(TodayAttentionItem(
                id: "price.\(instrument)", systemImage: "tag.slash",
                title: "No price for \(instrumentName(instrument))",
                detail: "\(Wording.names(gap.accounts.map(accountName))) "
                    + "\(gap.accounts.count == 1 ? "leaves" : "leave") it out of your net worth",
                target: .instrument(instrument), action: "Add Price"))
        }
        for gap in gaps {
            guard case .rate(let from, let to) = gap.item else { continue }
            items.append(TodayAttentionItem(
                id: "fx.\(from)-\(to)", systemImage: "arrow.left.arrow.right",
                title: "No \(from) to \(to) exchange rate",
                detail: "\(Wording.names(gap.accounts.map(accountName))) "
                    + "\(gap.accounts.count == 1 ? "isn't" : "aren't") fully counted",
                target: .instruments, action: "Add Rate"))
        }

        for (instrument, date) in valuator.outdatedPrices(in: library, asOf: today)
        where !missingPrices.contains(instrument) {
            items.append(TodayAttentionItem(
                id: "outdated.\(instrument)", systemImage: "tag",
                title: instrumentName(instrument),
                detail: "Last price \(AmountFormat.shortDate(date, locale: locale)), older than its account's value",
                target: .instrument(instrument), action: "Update"))
        }
        items += pastGaps(library: library, valuator: valuator, asOf: today, locale: locale)
        return items
    }

    /// An item per account whose trades have problems, opening the account:
    /// "Directa", then "2 problems with trades: More sold than held · VWCE
    /// differs from the statement", with *Fix*. The
    /// problems are the ones the account's page lists
    /// (``TradeIssueNote/notes(for:library:valuator:locale:)``): more sold
    /// than held, an opening without a cost, a statement that differs from
    /// the trades, and the rest. Sorted by account name.
    static func tradeProblems(library: Library, valuator: Valuator,
                              locale: Locale = .current) -> [TodayAttentionItem] {
        let affected = Set(valuator.tradeIssues().map(\.account)).compactMap { library.accounts[$0] }
        return affected.sorted { ($0.name, $0.id.rawValue) < ($1.name, $1.id.rawValue) }.compactMap { account in
            let notes = TradeIssueNote.notes(for: account.id, library: library, valuator: valuator, locale: locale)
            guard !notes.isEmpty else { return nil }
            var kinds: [String] = []
            for note in notes where !kinds.contains(note.title) {
                kinds.append(note.title)
            }
            let shown = kinds.prefix(2).joined(separator: " · ")
            let more = kinds.count > 2 ? " · \(kinds.count - 2) more" : ""
            return TodayAttentionItem(
                id: "trades.\(account.id)", systemImage: "exclamationmark.triangle",
                title: account.name,
                detail: "\(Wording.count(notes.count, "problem")) with trades: \(shown)\(more)",
                target: .account(account.id), action: "Fix")
        }
    }

    /// Prices and exchange rates missing on month ends before `asOf`, which
    /// leave accounts out of the net-worth history, with *Fill In Past
    /// Prices*: an item per currency, and per instrument for one or two
    /// (more are one item, so they don't crowd the card). The latest
    /// check-in's own gaps are the items above, typed in under Instruments.
    static func pastGaps(library: Library, valuator: Valuator, asOf: CalendarDate,
                         locale: Locale = .current) -> [TodayAttentionItem] {
        let dates = valuator.dates(.monthEnds, in: .netWorth, through: asOf).filter { $0 < asOf }
        guard let missing = valuator.missingValues(in: .netWorth, on: dates)?.filter({ $0.item.isPriceOrRate })
        else { return [] }
        func counted(_ accounts: [AccountID], _ dates: [CalendarDate]) -> String {
            let names = Set(accounts).map { library.accounts[$0]?.name ?? $0.rawValue }.sorted()
            return "\(MissingValueNote.shortList(names)) \(names.count == 1 ? "isn't" : "aren't") fully counted in "
                + "your net worth \(MissingValueNote.when(dates, locale: locale))"
        }
        var items: [TodayAttentionItem] = []
        var prices: [(InstrumentID, MissingValues.Gap)] = []
        for gap in missing.gaps {
            switch gap.item {
            case .rate(let from, let to):
                items.append(TodayAttentionItem(
                    id: "past.fx.\(from)-\(to)", systemImage: "arrow.left.arrow.right",
                    title: "Past exchange rates for \(AmountFormat.symbol(for: from, locale: locale)) are missing",
                    detail: counted(gap.accounts, gap.dates), target: .fillPastPrices, action: "Fill In"))
            case .price(let instrument):
                prices.append((instrument, gap))
            case .noValuation:
                break
            }
        }
        func name(_ id: InstrumentID) -> String { library.instruments[id]?.name ?? id.rawValue }
        if prices.count > 2 {
            let gaps = prices.map(\.1)
            items.append(TodayAttentionItem(
                id: "past.prices", systemImage: "tag.slash",
                title: "Past prices for \(prices.count) instruments are missing",
                detail: "\(MissingValueNote.shortList(prices.map { name($0.0) })): "
                    + counted(gaps.flatMap(\.accounts), Set(gaps.flatMap(\.dates)).sorted()),
                target: .fillPastPrices, action: "Fill In"))
        } else {
            for (instrument, gap) in prices {
                items.append(TodayAttentionItem(
                    id: "past.price.\(instrument)", systemImage: "tag.slash",
                    title: "Past prices for \(name(instrument)) are missing",
                    detail: counted(gap.accounts, gap.dates), target: .fillPastPrices, action: "Fill In"))
            }
        }
        return items
    }
}

// MARK: - Milestones

/// The main plan's milestones as Today shows them: the Plan screen's, with
/// those reached as Progress works them out.
@MainActor
enum TodayMilestones {
    static func of(_ plan: PlanDocument, results: PlanResults?, library: LibraryStore,
                   plans: PlanStore) -> PlanMilestones {
        let progress = plans.planProgress(of: plan.id, document: plan)
        return PlanMilestones(plan: plan, library: library.library, valuator: library.valuator,
                              asOf: library.asOfDate, results: results, reached: progress.reached)
    }
}
