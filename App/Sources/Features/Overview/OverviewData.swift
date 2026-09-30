import Foundation
import Model
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

/// The hero number: net worth (or plan assets) on the latest check-in, with
/// its change since the check-in before and since the end of last year.
struct OverviewHero: Hashable, Sendable {
    var scope: NetWorthScope
    /// The date reported on: the latest check-in.
    var date: CalendarDate
    var total: Decimal
    /// Whether every account was valued completely.
    var isComplete: Bool
    /// The change since the previous check-in.
    var sinceLastCheckIn: Decimal?
    /// The previous check-in's date.
    var lastCheckIn: CalendarDate?
    /// The change since 31 December of last year, as a fraction of the value then.
    var thisYear: Double?

    init(valuator: Valuator, asOf date: CalendarDate, scope: NetWorthScope) {
        self.scope = scope
        self.date = date
        let now = valuator.total(on: date, in: scope)
        total = now.total
        isComplete = now.isComplete
        if let report = valuator.changeSinceLastCheckIn(asOf: date, in: scope) {
            sinceLastCheckIn = report.total.change
            lastCheckIn = report.from
        }
        if let yearEnd = YearMonth(year: date.year - 1, month: 12)?.lastDay, yearEnd < date,
           let first = valuator.firstValuationDate(in: scope), first <= yearEnd {
            let start = valuator.total(on: yearEnd, in: scope).total
            if start != 0 {
                thisYear = ((now.total - start) / abs(start)).doubleValue
            }
        }
    }
}

// MARK: - History

/// The history chart's data for one range: the line (or stacked areas by
/// asset class) and, with *Future* on, the plan's projection clipped to a
/// matching horizon.
struct OverviewHistory: Hashable, Sendable {
    var points: [ChartPoint]
    var stacked: [ChartSeries]
    var projection: [FanPoint]
    var markers: [ChartMarker]
    /// The history's values that use a price more than 31 days older than
    /// their date, for a note under the chart; `nil` when there are none.
    var oldPrices: OldPriceSummary?

    /// - Parameters:
    ///   - projection: the main plan's portfolio fan, starting at `end`.
    ///   - markers: retirement, pension starts and the like.
    ///
    /// The projection reaches as far ahead as the range reaches back (all of
    /// it for *All*); markers outside what's shown are left out.
    init(valuator: Valuator, through end: CalendarDate, scope: NetWorthScope, range: OverviewRange, stacked: Bool,
         projection: [FanPoint] = [], markers: [ChartMarker] = []) {
        let start = range.years.map { end.adding(years: -$0) }
        points = valuator.series(scope, through: end)
            .filter { point in start.map { point.date >= $0 } ?? true }
            .chartPoints
        let dates = valuator.dates(.monthEnds, in: scope, through: end).filter { date in start.map { date >= $0 } ?? true }
        oldPrices = OldPriceSummary(valuator.oldPrices(in: scope, on: dates))
        let startDate = start?.dateValue
        if stacked {
            self.stacked = valuator.breakdownSeries(by: .assetClass, in: scope, through: end).chartSeries
                .map { series in
                    var clipped = series
                    clipped.points = series.points.filter { point in startDate.map { point.date >= $0 } ?? true }
                    return clipped
                }
                .filter { series in series.points.contains { $0.value != 0 } }
        } else {
            self.stacked = []
        }
        let horizon = range.years.map { end.adding(years: $0).dateValue }
        self.projection = horizon.map { Self.clip(projection, at: $0) } ?? projection
        let first = points.first?.date ?? end.dateValue
        let last = self.projection.last?.date ?? end.dateValue
        self.markers = markers.filter { $0.date >= first && $0.date <= last }
    }

    /// The fan up to `horizon`, with a point interpolated at the horizon when
    /// the fan goes beyond it.
    static func clip(_ fan: [FanPoint], at horizon: Date) -> [FanPoint] {
        var kept = fan.filter { $0.date <= horizon }
        guard let before = kept.last, before.date < horizon,
              let after = fan.first(where: { $0.date > horizon })
        else { return kept }
        let span = after.date.timeIntervalSince(before.date)
        guard span > 0 else { return kept }
        let t = horizon.timeIntervalSince(before.date) / span
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        kept.append(FanPoint(date: horizon, p10: mix(before.p10, after.p10), p25: mix(before.p25, after.p25),
                             p50: mix(before.p50, after.p50), p75: mix(before.p75, after.p75),
                             p90: mix(before.p90, after.p90)))
        return kept
    }
}

// MARK: - Baseline

/// How the accounts a baseline covers compare today with its median
/// ("12.400 € ahead of your Jan baseline"; PROGRESS.md, "Actual vs. a
/// baseline"). The median between year ends is interpolated linearly by
/// day. Basic: amounts are compared as they are, without adjusting the
/// baseline's euros for inflation.
struct OverviewBaselineGap: Hashable, Sendable {
    /// When the baseline was saved.
    var created: CalendarDate
    var label: String?
    /// The baseline's accounts on the date.
    var actual: Decimal
    /// The baseline's median on the date.
    var expected: Decimal

    /// Positive when ahead.
    var gap: Decimal { actual - expected }

    init?(baseline: Baseline, valuator: Valuator, on date: CalendarDate) {
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
        actual = baseline.accounts.reduce(Decimal(0)) { total, account in
            total + (valuator.value(of: account, on: date)?.knownValue ?? 0)
        }
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
    }

    var id: String
    var systemImage: String
    var title: String
    var detail: String
    var target: Target
}

/// Finds what needs attention in the library's data: stale accounts,
/// missing and outdated prices, missing exchange rates. The screen adds the
/// library's own state (sync conflicts, save errors) and plan warnings.
enum OverviewAttention {
    static func items(library: Library, valuator: Valuator, asOf: CalendarDate, today: CalendarDate,
                      stalenessThreshold: Int, locale: Locale = .current) -> [OverviewAttentionItem] {
        func accountName(_ id: AccountID) -> String { library.accounts[id]?.name ?? id.rawValue }
        func instrumentName(_ id: InstrumentID) -> String { library.instruments[id]?.name ?? id.rawValue }

        var items: [OverviewAttentionItem] = []

        for stale in valuator.staleAccounts(on: today, threshold: stalenessThreshold, in: .netWorth) {
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
