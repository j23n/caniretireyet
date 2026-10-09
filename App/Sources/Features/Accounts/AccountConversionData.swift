import Foundation
import Model
import Tracker

// Switching an account between monthly snapshots and trade history
// (docs/TRADES.md, "Converting an account"; UI.md, "Account detail"): what
// the conversion will write, in words, before it's applied. Plain values,
// so they can be checked on Linux.

/// Which way an account is converted.
enum AccountConversionDirection: Hashable, Sendable, Identifiable {
    /// Snapshots → trades (*Switch to Trade History…*).
    case toTrades
    /// Trades → snapshots (*Switch to Snapshots…*).
    case toSnapshots

    var id: Self { self }

    /// The sheet's title and button.
    var title: String {
        self == .toTrades ? "Switch to Trade History" : "Switch to Snapshots"
    }
}

/// What converting an account will do, for the sheet's preview.
struct AccountConversionSummary: Hashable, Sendable {
    /// A trade the conversion writes, as the preview lists it.
    struct Line: Hashable, Sendable, Identifiable {
        var trade: Trade
        /// "Buy 10 VWCE at 134,15 €" (``TradeWording/summary(of:in:locale:)``).
        var title: String
        var id: TradeKey { trade.key }
    }

    /// One kind of estimate, counted: "12 buys and sells are priced at the value's price".
    struct NoteGroup: Hashable, Sendable, Identifiable {
        var kind: ConversionNote.Kind
        /// Each note, dated: "30 Jun 2026: The buy of 10 vwce is priced at …".
        var details: [String]
        var id: String { kind.rawValue }

        /// The kind in words, counted (``AccountConversionSummary/summary(of:count:)``).
        var summary: String { AccountConversionSummary.summary(of: kind, count: details.count) }
    }

    let direction: AccountConversionDirection
    let conversion: AccountConversion
    var openings: [Line]
    var buys: [Line]
    var sells: [Line]
    var notes: [NoteGroup]
    /// The trades a conversion to snapshots removes.
    var removedCount: Int
    /// The valuations it writes (replaced or added).
    var valuationCount: Int
    /// Valuations added on a month's last trade (to snapshots).
    var addedValuationCount: Int

    /// The preview of converting `account` in `direction`; `nil` when it
    /// can't be (no such account, or it already records that way).
    init?(account: AccountID, direction: AccountConversionDirection, library: Library, locale: Locale = .current) {
        let conversion = direction == .toTrades
            ? library.conversionToTrades(of: account) : library.conversionToSnapshots(of: account)
        guard let conversion else { return nil }
        self.direction = direction
        self.conversion = conversion
        // Worded from the library as it is: a conversion changes no instrument, nor the account's currency.
        func lines(_ type: TradeType) -> [Line] {
            conversion.trades.filter { $0.type == type }
                .map { Line(trade: $0, title: TradeWording.summary(of: $0, in: library, locale: locale)) }
        }
        openings = lines(.opening)
        buys = lines(.buy)
        sells = lines(.sell)
        removedCount = conversion.removedTrades.count
        let existing = Set(library.valuations(for: account).map(\.key))
        valuationCount = conversion.valuations.count
        addedValuationCount = conversion.valuations.count { !existing.contains($0.key) }
        var groups: [NoteGroup] = []
        for note in conversion.notes {
            let detail = AmountFormat.mediumDate(note.date, locale: locale) + ": " + note.message
            if let index = groups.firstIndex(where: { $0.kind == note.kind }) {
                groups[index].details.append(detail)
            } else {
                groups.append(NoteGroup(kind: note.kind, details: [detail]))
            }
        }
        notes = groups
    }

    /// The months whose history files the conversion changes, and backs up.
    var months: [YearMonth] { conversion.months }

    /// "12 months, Oct 2025 – Sep 2026", or "1 month, Sep 2026".
    func monthsText(locale: Locale = .current) -> String {
        guard let first = months.first, let last = months.last else { return "No months" }
        func name(_ month: YearMonth) -> String {
            month.lastDay.dateValue.formatted(.dateTime.month(.abbreviated).year().locale(locale))
        }
        let count = Wording.count(months.count, "month")
        return first == last ? "\(count), \(name(first))" : "\(count), \(name(first)) – \(name(last))"
    }

    /// What the conversion writes, in one sentence.
    var headline: String {
        switch direction {
        case .toTrades:
            var parts: [String] = []
            if !openings.isEmpty { parts.append(Wording.count(openings.count, "opening position")) }
            if !buys.isEmpty { parts.append(Wording.count(buys.count, "buy")) }
            if !sells.isEmpty { parts.append(Wording.count(sells.count, "sale")) }
            let trades = parts.isEmpty ? "no trades" : Wording.list(parts)
            return "The account's values become \(trades), and its values keep only their cash and new money."
        case .toSnapshots:
            let values = Wording.count(valuationCount, "value")
            return "Its \(Wording.count(removedCount, "trade")) become the positions, average cost and cash "
                + "of \(values)" + (addedValuationCount > 0
                    ? ", \(Wording.count(addedValuationCount, "of them", plural: "of them")) added on a month's "
                        + "last trade."
                    : ".")
        }
    }

    /// The warning of a conversion to snapshots: the trades' detail is lost, a backup is kept.
    static let snapshotsWarning = "Each trade's detail is lost: its date, price, fees, and the income and realised "
        + "gains worked out from it. The files are backed up first, so it can be restored from Sync & backups."

    /// A note kind in words, counted.
    static func summary(of kind: ConversionNote.Kind, count: Int) -> String {
        switch kind {
        case .costFromMarketValue:
            return count == 1
                ? "1 opening position has no recorded cost: its cost is its value on that day."
                : "\(count) opening positions have no recorded cost: their cost is their value on that day."
        case .unknownCost:
            return count == 1
                ? "1 opening position has no cost and no price: its cost is unknown."
                : "\(count) opening positions have no cost and no price: their cost is unknown."
        case .priceFromValuation:
            return count == 1
                ? "1 buy or sale is an estimate, priced at its value's price."
                : "\(count) buys and sales are estimates, priced at their value's price."
        case .noPrice:
            return count == 1
                ? "1 buy or sale has no price: add its amount afterwards."
                : "\(count) buys and sales have no price: add their amounts afterwards."
        case .cashFromBalance:
            return count == 1 ? "1 balance became cash." : "\(count) balances became cash."
        case .existingTrades:
            return "The account already has trades, which will count too. Check them afterwards."
        case .addedValuation:
            return count == 1
                ? "1 value is added on a month's last trade, so the history keeps what the trades did."
                : "\(count) values are added on a month's last trade, so the history keeps what the trades did."
        case .tradesRemoved:
            return "The trades are removed: their income, fees and realised gains are no longer recorded."
        case .settledOutside:
            return "The account has never held cash, so its buys and sales are paid from outside it: its cash stays "
                + "at zero, and what they cost or brought in is new money."
        default:
            return count == 1 ? "1 note." : "\(count) notes."
        }
    }
}
