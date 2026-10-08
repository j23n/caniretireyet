import Foundation
import Model
import Planner
import Tracker

// The Overview's numbers, computed from the library without SwiftUI so they
// can be checked on Linux. The views in this folder only lay them out.

/// How far back the history chart reaches (UI.md, "Overview": 1Y, 3Y, 5Y, All).
enum OverviewRange: String, CaseIterable, Hashable, Sendable {
    case oneYear = "1Y"
    case threeYears = "3Y"
    case fiveYears = "5Y"
    case all = "All"

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

    /// The years the range spans, or `nil` for all of the history.
    var years: Int? {
        switch self {
        case .oneYear: 1
        case .threeYears: 3
        case .fiveYears: 5
        case .all: nil
        }
    }
}

/// What the Overview's allocation bars group by (UI.md, "Allocation").
enum OverviewAllocation: String, CaseIterable, Hashable, Sendable {
    case assetClass
    case accountGroup
    case currency
    case institution
    case liquidity

    var title: String {
        switch self {
        case .assetClass: "Asset class"
        case .accountGroup: "Account group"
        case .currency: "Currency"
        case .institution: "Institution"
        case .liquidity: "Liquid vs locked"
        }
    }

    var dimension: BreakdownDimension {
        switch self {
        case .assetClass: .assetClass
        case .accountGroup: .accountGroup
        case .currency: .currency
        case .institution: .institution
        case .liquidity: .liquidity
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

// MARK: - Hero

/// The hero number: net worth today, with the change between the last two
/// check-ins and since the end of last year.
struct OverviewHero: Hashable, Sendable {
    /// The date reported on: today.
    var date: CalendarDate
    var total: Decimal
    /// Whether every account was valued completely.
    var isComplete: Bool
    /// The change between the last two check-ins on or before ``date``.
    var sinceLastCheckIn: Decimal?
    /// The previous check-in's date.
    var lastCheckIn: CalendarDate?
    /// The month the change covers, when the check-in before was the end
    /// of the month before ("in September"); `nil` otherwise ("since 31 Aug").
    var changeMonth: CalendarDate?
    /// The change since 31 December of last year, as a fraction of the value then.
    var thisYear: Double?

    init(valuator: Valuator, asOf date: CalendarDate) {
        self.date = date
        let now = valuator.total(on: date, in: .netWorth)
        total = now.total
        isComplete = now.isComplete
        if let report = valuator.changeSinceLastCheckIn(asOf: date, in: .netWorth) {
            sinceLastCheckIn = report.total.change
            lastCheckIn = report.from
            changeMonth = Self.month(from: report.from, to: report.to)
        }
        if let yearEnd = YearMonth(year: date.year - 1, month: 12)?.lastDay, yearEnd < date,
           let first = valuator.firstValuationDate(in: .netWorth), first <= yearEnd {
            let start = valuator.total(on: yearEnd, in: .netWorth).total
            if start != 0 {
                thisYear = ((now.total - start) / abs(start)).doubleValue
            }
        }
    }
}

extension OverviewHero {
    /// The month a change from `from` to `to` covers: `to`'s, when `from`
    /// is the last day of the month before; `nil` otherwise.
    static func month(from: CalendarDate, to: CalendarDate) -> CalendarDate? {
        from == to.yearMonth.previous.lastDay ? to : nil
    }
}

// MARK: - History

/// The history chart's data for one range (UI.md, "History chart"): the
/// totals stacked by asset class, debts below zero, and with *Future* on
/// the plan's projection up to the chosen horizon (``FutureHorizon``).
///
/// The past is net worth. With a projection it's plan assets instead (the
/// accounts the plan counts, e.g. without your home), still by asset class:
/// the projection is of plan assets, so the past's total meets its start at
/// today instead of dropping onto it.
struct OverviewHistory: Hashable, Sendable {
    /// What the past covers: net worth, or plan assets with a projection.
    var scope: NetWorthScope
    /// The total on each date: the callout's total, the relative axis's 1×,
    /// and the line drawn when nothing can be stacked (every value zero).
    var points: [ChartPoint]
    /// The totals by asset class, in stacking order (bottom first), on the
    /// same dates as `points` and with their completeness; groups with no
    /// value in the range are left out.
    var stacked: [ChartSeries]
    var projection: [FanPoint]
    var markers: [ChartMarker]
    /// The history's values that use a price more than 31 days older than
    /// their date, for a note under the chart; `nil` when there are none.
    var oldPrices: OldPriceSummary?
    /// What the history's partial totals (drawn dashed) are missing: prices,
    /// rates, accounts without a value yet; `nil` when it's complete.
    var missing: MissingValues?

    /// - Parameters:
    ///   - projection: the main plan's portfolio fan, starting at `end`.
    ///     With one, the past covers plan assets (``scope``).
    ///   - markers: retirement, pension starts and the like.
    ///   - horizon: where the projection stops (``FutureHorizon``); all of
    ///     it when `nil`.
    ///
    /// Markers outside what's shown are left out.
    init(valuator: Valuator, through end: CalendarDate, range: OverviewRange, projection: [FanPoint] = [],
         markers: [ChartMarker] = [], horizon: Date? = nil) {
        let scope: NetWorthScope = projection.isEmpty ? .netWorth : .planAssets
        self.scope = scope
        let start = range.years.map { end.adding(years: -$0) }
        let dates = valuator.dates(.monthEnds, in: scope, through: end).filter { date in start.map { date >= $0 } ?? true }
        // One total per date makes the line, the stacked areas and the missing values.
        let totals = dates.map { valuator.total(on: $0, in: scope) }
        points = totals.map { total in
            ChartPoint(date: total.date.dateValue, value: total.total.doubleValue, isComplete: total.isComplete)
        }
        stacked = Self.byAssetClass(totals.map { valuator.breakdown(of: $0, by: .assetClass) })
        oldPrices = OldPriceSummary(valuator.oldPrices(in: scope, on: dates))
        missing = points.hasIncompletePoints ? MissingValues(totals.flatMap(\.accounts)) : nil
        self.projection = horizon.map { ProjectionWindow.clip(projection, at: $0) } ?? projection
        let first = points.first?.date ?? end.dateValue
        let last = self.projection.last?.date ?? end.dateValue
        self.markers = markers.filter { $0.date >= first && $0.date <= last }
    }

    /// One series per asset class, and one for debts, in stacking order
    /// (bottom first), from a breakdown per date. A point is as complete as
    /// its date's total; a group that's zero on every date is left out.
    static func byAssetClass(_ breakdowns: [Breakdown]) -> [ChartSeries] {
        let keys = Set(breakdowns.flatMap { $0.slices.map(\.key) }).sorted()
        return keys.compactMap { key in
            let points = breakdowns.map { breakdown in
                ChartPoint(date: breakdown.date.dateValue, value: breakdown.value(of: key).doubleValue,
                           isComplete: breakdown.isComplete)
            }
            guard points.contains(where: { $0.value != 0 }) else { return nil }
            return ChartSeries(id: key.chartID, name: key.description, color: key.chartColor, points: points)
        }
    }
}

// MARK: - Baseline

/// How the accounts a baseline covers compare today with its median
/// ("12.400 € ahead of your Jan baseline"; PROGRESS.md, "Actual vs. a
/// baseline"). The median between year ends is interpolated linearly by
/// day. Basic: amounts are compared as they are, without adjusting the
/// baseline's money for inflation, in the baseline's currency (its plan's):
/// your accounts are converted at the date's exchange rate, and without one
/// there's no gap to show.
struct OverviewBaselineGap: Hashable, Sendable {
    /// When the baseline was saved.
    var created: CalendarDate
    var label: String?
    /// The baseline's currency, which `actual` and `expected` are in.
    var currency: CurrencyCode
    /// The baseline's accounts on the date, with those that replaced them
    /// and those opened since (``Baseline/comparedAccounts(among:)``).
    var actual: Decimal
    /// The baseline's median on the date.
    var expected: Decimal

    /// Positive when ahead.
    var gap: Decimal { actual - expected }

    /// `currency` is the baseline's (``PlanMoney/currency(of:settings:)``);
    /// `nil` takes the valuator's base currency.
    init?(baseline: Baseline, valuator: Valuator, on date: CalendarDate, currency: CurrencyCode? = nil) {
        guard date > baseline.start.date, !baseline.accounts.isEmpty else { return nil }
        var knots: [(date: CalendarDate, value: Decimal)] = [(baseline.start.date, baseline.start.value)]
        for year in baseline.years.sorted(by: { $0.year < $1.year }) {
            guard let end = YearMonth(year: year.year, month: 12)?.lastDay, end > baseline.start.date else { continue }
            knots.append((end, year.p50))
        }
        guard let upper = knots.firstIndex(where: { $0.date >= date }), upper > 0 else { return nil }
        let from = knots[upper - 1]
        let to = knots[upper]
        let length = from.date.days(to: to.date)
        guard length > 0 else { return nil }
        let fraction = Decimal(from.date.days(to: date)) / Decimal(length)
        expected = from.value + (to.value - from.value) * fraction
        let base = baseline.comparedAccounts(among: valuator.accounts).reduce(Decimal(0)) { total, account in
            total + (valuator.value(of: account, on: date)?.knownValue ?? 0)
        }
        let currency = currency ?? valuator.baseCurrency
        guard let converted = PlanMoney.convert(base, to: currency, on: date, valuator: valuator) else { return nil }
        actual = converted
        self.currency = currency
        created = baseline.created
        label = baseline.label
    }

    /// "Jan", or "Jan 2025" for a baseline from another year than `date`.
    func name(relativeTo date: CalendarDate, locale: Locale = .current) -> String {
        let style = created.year == date.year
            ? Date.FormatStyle.dateTime.month(.abbreviated).locale(locale)
            : Date.FormatStyle.dateTime.month(.abbreviated).year().locale(locale)
        return created.dateValue.formatted(style)
    }
}

// MARK: - Needs attention

/// One thing on the Overview that needs you (UI.md, "Needs attention").
struct OverviewAttentionItem: Hashable, Sendable, Identifiable {
    /// Where tapping the item goes.
    enum Target: Hashable, Sendable {
        case account(AccountID)
        case instrument(InstrumentID)
        case checkIn
        case plan
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
enum OverviewAttention {
    static func items(library: Library, valuator: Valuator, asOf: CalendarDate, today: CalendarDate,
                      stalenessThreshold: Int, locale: Locale = .current) -> [OverviewAttentionItem] {
        func accountName(_ id: AccountID) -> String { library.accounts[id]?.name ?? id.rawValue }
        func instrumentName(_ id: InstrumentID) -> String { library.instruments[id]?.name ?? id.rawValue }

        var items: [OverviewAttentionItem] = []

        // An account that holds nothing has nothing to check in (AccountStaleness).
        for stale in valuator.staleAccounts(on: today, threshold: stalenessThreshold, in: .netWorth)
        where valuator.emptySince(of: stale.account, on: today) == nil {
            let name = accountName(stale.account)
            if let last = stale.lastValuation {
                items.append(OverviewAttentionItem(
                    id: "stale.\(stale.account)", systemImage: "clock.badge.exclamationmark",
                    title: "\(name): last value \(monthName(last, today: today, locale: locale))",
                    detail: "Update it in your next check-in", target: .account(stale.account)))
            } else {
                items.append(OverviewAttentionItem(
                    id: "stale.\(stale.account)", systemImage: "clock.badge.exclamationmark",
                    title: "\(name): no value yet", detail: "Add its first value in a check-in",
                    target: .account(stale.account)))
            }
        }
        items += tradeProblems(library: library, valuator: valuator, locale: locale)

        var missingPrices: [InstrumentID: [AccountID]] = [:]
        var missingRates: [String: (from: CurrencyCode, to: CurrencyCode, accounts: [AccountID])] = [:]
        for problem in valuator.netWorth(on: asOf).problems {
            switch problem {
            case .missingPrice(let account, let instrument):
                missingPrices[instrument, default: []].append(account)
            case .missingFX(let account, let from, let to):
                let key = "\(from)-\(to)"
                var entry = missingRates[key] ?? (from, to, [])
                entry.accounts.append(account)
                missingRates[key] = entry
            case .noValuation:
                break // Stale accounts cover it.
            }
        }
        for (instrument, accounts) in missingPrices.sorted(by: { $0.key < $1.key }) {
            items.append(OverviewAttentionItem(
                id: "price.\(instrument)", systemImage: "tag.slash",
                title: "No price for \(instrumentName(instrument))",
                detail: "\(list(accounts.map(accountName))) \(accounts.count == 1 ? "leaves" : "leave") it out of "
                    + "your net worth. Type in a price at your next check-in.",
                target: .instrument(instrument)))
        }
        for (key, entry) in missingRates.sorted(by: { $0.key < $1.key }) {
            items.append(OverviewAttentionItem(
                id: "fx.\(key)", systemImage: "arrow.left.arrow.right",
                title: "No \(entry.from) to \(entry.to) exchange rate",
                detail: "\(list(entry.accounts.map(accountName))) \(entry.accounts.count == 1 ? "isn't" : "aren't") "
                    + "fully counted. Type in a rate at your next check-in.",
                target: .checkIn))
        }

        for (instrument, date) in outdatedPrices(library: library, valuator: valuator, asOf: asOf)
        where missingPrices[instrument] == nil {
            items.append(OverviewAttentionItem(
                id: "outdated.\(instrument)", systemImage: "tag",
                title: "\(instrumentName(instrument)): last price \(AmountFormat.shortDate(date, locale: locale))",
                detail: "Older than the account's latest value. Fetch or type in a price at your next check-in.",
                target: .instrument(instrument)))
        }
        items += pastGaps(library: library, valuator: valuator, asOf: asOf, locale: locale)
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
                              locale: Locale = .current) -> [OverviewAttentionItem] {
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
            return OverviewAttentionItem(
                id: "trades.\(account.id)", systemImage: "exclamationmark.triangle",
                title: "\(account.name): \(notes.count == 1 ? "1 problem" : "\(notes.count) problems") with trades",
                detail: "\(shown)\(more). Open the account to fix \(notes.count == 1 ? "it" : "them").",
                target: .account(account.id))
        }
    }

    /// Prices and exchange rates missing on month ends before `asOf`, which
    /// leave accounts out of the net-worth history, with *Fill In Past
    /// Prices*: an item per currency, and per instrument for one or two
    /// (more are one item, so they don't crowd the card). The latest
    /// check-in's own gaps are the items above, typed in at the next check-in.
    static func pastGaps(library: Library, valuator: Valuator, asOf: CalendarDate,
                         locale: Locale = .current) -> [OverviewAttentionItem] {
        let dates = valuator.dates(.monthEnds, in: .netWorth, through: asOf).filter { $0 < asOf }
        guard let missing = valuator.missingValues(in: .netWorth, on: dates)?.filter({ $0.item.isPriceOrRate })
        else { return [] }
        func counted(_ accounts: [AccountID], _ dates: [CalendarDate]) -> String {
            let names = Set(accounts).map { library.accounts[$0]?.name ?? $0.rawValue }.sorted()
            return "\(MissingValueNote.shortList(names)) \(names.count == 1 ? "isn't" : "aren't") fully counted in "
                + "your net worth \(MissingValueNote.when(dates, locale: locale))"
        }
        var items: [OverviewAttentionItem] = []
        var prices: [(InstrumentID, MissingValues.Gap)] = []
        for gap in missing.gaps {
            switch gap.item {
            case .rate(let from, let to):
                items.append(OverviewAttentionItem(
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
            items.append(OverviewAttentionItem(
                id: "past.prices", systemImage: "tag.slash",
                title: "Past prices for \(prices.count) instruments are missing",
                detail: "\(MissingValueNote.shortList(prices.map { name($0.0) })): "
                    + counted(gaps.flatMap(\.accounts), Set(gaps.flatMap(\.dates)).sorted()) + fetchOrType,
                target: .fillPastPrices))
        } else {
            for (instrument, gap) in prices {
                items.append(OverviewAttentionItem(
                    id: "past.price.\(instrument)", systemImage: "tag.slash",
                    title: "Past prices for \(name(instrument)) are missing",
                    detail: counted(gap.accounts, gap.dates) + fetchOrType, target: .fillPastPrices))
            }
        }
        return items
    }

    /// Instruments held in accounts open on `asOf` whose latest price is
    /// older than the holding account's latest valuation: usually a price
    /// that couldn't be fetched at that check-in. Sorted by instrument.
    static func outdatedPrices(library: Library, valuator: Valuator,
                               asOf: CalendarDate) -> [(InstrumentID, CalendarDate)] {
        var oldest: [InstrumentID: CalendarDate] = [:]
        for account in library.accounts.values where account.isOpen(on: asOf) && account.includedInNetWorth {
            // What the account holds: its latest valuation, or a trades account's snapshot
            // (dated its latest valuation or trade).
            guard let valuation = valuator.snapshot(of: account.id, on: asOf), !valuation.isBalance else { continue }
            for position in valuation.positions where position.quantity != 0 {
                guard let price = valuator.prices.latest(for: position.instrument, onOrBefore: asOf),
                      price.date < valuation.date
                else { continue }
                oldest[position.instrument] = min(oldest[position.instrument] ?? price.date, price.date)
            }
        }
        return oldest.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    /// "May", or "May 2025" when it isn't this year.
    static func monthName(_ date: CalendarDate, today: CalendarDate, locale: Locale = .current) -> String {
        let style = date.year == today.year
            ? Date.FormatStyle.dateTime.month(.wide).locale(locale)
            : Date.FormatStyle.dateTime.month(.wide).year().locale(locale)
        return date.dateValue.formatted(style)
    }

    /// "A", "A and B", "A, B and C".
    static func list(_ names: [String]) -> String {
        let unique = names.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        guard let last = unique.last else { return "" }
        guard unique.count > 1 else { return last }
        return unique.dropLast().joined(separator: ", ") + " and " + last
    }
}
