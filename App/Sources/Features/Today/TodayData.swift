import Foundation
import Glance
import Model
import Planner
import Tracker

// Today's words and what needs attention. Its numbers come from the
// package: the history chart (Tracker's `HistoryChartData`), the answer
// (the Planner's `LatestAnswer`) and *On track?* (the Planner's
// `PlanOnTrack`). The views in this folder only lay them out.

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

// MARK: - Hero and change

// The hero number and the *Net worth* tile, net worth today with the change
// between the last two check-ins and since the end of last year, are
// Glance's `NetWorthGlance`, as the widgets have it. *This year* splits that
// change since the end of last year into markets, saved and other with
// Tracker's `Valuator.changeThisYear(asOf:)`, from the same 31 December
// (tested in TrackerTests, and against the hero in GlanceTests). The answer's
// headline counts the time to go with Glance's `RetirementCountdown`, and its
// ring shows Glance's `ReadinessFigure` (GlanceTests).

// MARK: - This year

/// The words of Today's *This year* card (UI.md, "This year").
enum TodayYearText {
    /// "Savings rate 17%: you saved 1.956 € of the 11.525 € that came in
    /// since 30 Jun, 1.325 € of it paid into pensions, and spent 9.569 €."
    /// With tax recorded, from a current account or a tax pot, what came in
    /// is after it: "… that came in since 30 Jun after 3.000 € in tax, …".
    /// When more was saved than came in, it says some income may not be
    /// recorded. The amounts hide with the eye; the rate stays. `nil` when
    /// nothing came in.
    static func savings(_ savings: SavingsRate, today: CalendarDate, locale: Locale) -> AmountSentence? {
        guard let rate = savings.rate else { return nil }
        let percent = AmountFormat.percent(rate, digits: 0, locale: locale)
        let since = AmountFormat.shortDate(savings.from, relativeTo: today, locale: locale)
        let currency = savings.moneyInOut.currency
        func amount(_ value: Decimal) -> AmountSentence {
            .amount(AmountFormat.amount(value, currency: currency, locale: locale))
        }
        var text: AmountSentence = "Savings rate \(percent): you saved \(amount(savings.saved)) of the "
        text += "\(amount(savings.income)) that came in since \(since)"
        if savings.tax > 0 {
            text += " after \(amount(savings.tax)) in tax"
        }
        if savings.pensionContributions > 0 {
            text += ", \(amount(savings.pensionContributions)) of it paid into pensions"
        }
        guard savings.spent >= 0 else {
            return text + ". More was saved than came in: some income may not be recorded."
        }
        return text + ", and spent \(amount(savings.spent))."
    }
}

// MARK: - Needs attention

/// One thing on Today that needs you (UI.md, "Needs attention").
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
                    id: "stale.\(stale.account)", systemImage: "clock.badge.exclamationmark",
                    title: "\(name): last value \(GlanceText.month(last, relativeTo: today, locale: locale))",
                    detail: "Update it in your next check-in", target: .account(stale.account)))
            } else {
                items.append(TodayAttentionItem(
                    id: "stale.\(stale.account)", systemImage: "clock.badge.exclamationmark",
                    title: "\(name): no value yet",
                    detail: library.accounts[stale.account]?.acceptsTypedValues == true
                        ? "Update its value" : "Import a file with its values",
                    target: .account(stale.account)))
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
                    + "\(gap.accounts.count == 1 ? "leaves" : "leave") it out of your net worth. Fetch or type in a "
                    + "price under Instruments.",
                target: .instrument(instrument)))
        }
        for gap in gaps {
            guard case .rate(let from, let to) = gap.item else { continue }
            items.append(TodayAttentionItem(
                id: "fx.\(from)-\(to)", systemImage: "arrow.left.arrow.right",
                title: "No \(from) to \(to) exchange rate",
                detail: "\(Wording.names(gap.accounts.map(accountName))) "
                    + "\(gap.accounts.count == 1 ? "isn't" : "aren't") fully counted. Fetch or type in a rate under "
                    + "Instruments.",
                target: .instruments))
        }

        for (instrument, date) in valuator.outdatedPrices(in: library, asOf: today)
        where !missingPrices.contains(instrument) {
            items.append(TodayAttentionItem(
                id: "outdated.\(instrument)", systemImage: "tag",
                title: "\(instrumentName(instrument)): last price \(AmountFormat.shortDate(date, locale: locale))",
                detail: "Older than the account's latest value. Fetch or type in a price under Instruments.",
                target: .instrument(instrument)))
        }
        items += pastGaps(library: library, valuator: valuator, asOf: today, locale: locale)
        return items
    }

    /// An item per account whose trades have problems, opening the account:
    /// "Directa: 2 problems with trades", then "More sold than held · VWCE
    /// differs from the statement. Open the account to fix them." The
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
                title: "\(account.name): \(Wording.count(notes.count, "problem")) with trades",
                detail: "\(shown)\(more). Open the account to fix \(notes.count == 1 ? "it" : "them").",
                target: .account(account.id))
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
                    detail: counted(gap.accounts, gap.dates) + ". Fill in past prices to fetch them.",
                    target: .fillPastPrices))
            case .price(let instrument):
                prices.append((instrument, gap))
            case .noValuation:
                break
            }
        }
        func name(_ id: InstrumentID) -> String { library.instruments[id]?.name ?? id.rawValue }
        let fetchOrType = ". Fill in past prices to fetch them, or type them in."
        if prices.count > 2 {
            let gaps = prices.map(\.1)
            items.append(TodayAttentionItem(
                id: "past.prices", systemImage: "tag.slash",
                title: "Past prices for \(prices.count) instruments are missing",
                detail: "\(MissingValueNote.shortList(prices.map { name($0.0) })): "
                    + counted(gaps.flatMap(\.accounts), Set(gaps.flatMap(\.dates)).sorted()) + fetchOrType,
                target: .fillPastPrices))
        } else {
            for (instrument, gap) in prices {
                items.append(TodayAttentionItem(
                    id: "past.price.\(instrument)", systemImage: "tag.slash",
                    title: "Past prices for \(name(instrument)) are missing",
                    detail: counted(gap.accounts, gap.dates) + fetchOrType, target: .fillPastPrices))
            }
        }
        return items
    }
}
