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

    /// The title over what moved at the last check-in: "What moved it in
    /// September" when the check-in before was the end of the month
    /// before, else "What moved it since 15 Aug". With `saysIt` the title
    /// points at the date above it (iPhone); else "What moved in September".
    static func movedTitle(from: CalendarDate, to: CalendarDate, today: CalendarDate, saysIt: Bool,
                           locale: Locale = .current) -> String {
        let moved = saysIt ? "What moved it" : "What moved"
        guard let month = GlanceText.coveredMonth(from: from, to: to) else {
            return "\(moved) since \(AmountFormat.shortDate(from, relativeTo: today, locale: locale))"
        }
        return "\(moved) in \(GlanceText.month(month, relativeTo: today, locale: locale))"
    }

    /// What a check-in saved, said as time of the plan's spending: "You
    /// saved about 2 weeks of the life you plan." `nil` without a saving or
    /// without the plan's spending (Glance's `SavingAsTime`).
    static func savedAsTime(saved: Decimal, markets: Decimal, yearlySpending: Decimal?) -> String? {
        SavingAsTime(saved: saved, markets: markets, yearlySpending: yearlySpending)
            .map { "You saved \($0.saved.text) of the life you plan." }
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
