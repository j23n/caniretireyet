import Glance
import Model
import SwiftUI
import WidgetKit

/// What a widget draws at one moment: the snapshot the app last wrote, and
/// the day, which the countdowns are worked out from.
struct GlanceEntry: TimelineEntry {
    var date: Date
    /// `nil` until the app has written one (it hasn't been opened since the
    /// widgets were added, or this build has no App Group).
    var snapshot: GlanceSnapshot?

    /// The entry's day.
    var today: CalendarDate { CalendarDate(date, in: .current) }
}

/// Reads the snapshot the app writes into the App Group (``AppGroup``). The
/// numbers only change when the app writes a new snapshot, which reloads
/// every widget; the countdowns change with the day, so the timeline has an
/// entry for each of the next days, starting at midnight.
struct GlanceProvider: TimelineProvider {
    /// Days the timeline reaches ahead before asking again.
    static let days = 7

    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: .now, snapshot: .placeholder())
    }

    /// The widget gallery shows made-up numbers, never yours.
    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        completion(GlanceEntry(date: .now, snapshot: context.isPreview ? .placeholder() : Self.stored()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        let snapshot = Self.stored()
        let now = Date.now
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let midnights = (1...Self.days).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfToday) }
        let entries = [GlanceEntry(date: now, snapshot: snapshot)]
            + midnights.map { GlanceEntry(date: $0, snapshot: snapshot) }
        let next = midnights.last ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    /// The snapshot in the App Group's container, if the app has written one.
    static func stored() -> GlanceSnapshot? {
        AppGroup.snapshotURL.flatMap(GlanceFile.read(at:))
    }
}

extension GlanceSnapshot {
    /// Made-up numbers, for the widget gallery and while a widget loads:
    /// the mockups' (and UI.md's) 312.480 €, earliest at 54 in 15 years and
    /// 6 months, 58% of what retiring today would need. The dates are around
    /// `today`, so the countdowns read as they would.
    static func placeholder(today: CalendarDate = .today()) -> GlanceSnapshot {
        let last = today.startOfMonth.adding(days: -1)
        let values: [Decimal] = [271_300, 268_900, 266_200, 273_600, 279_100, 276_400, 270_800, 281_500, 288_000,
                                 293_900, 301_200, 308_270, 312_480]
        let history = values.enumerated().map { index, value in
            GlancePoint(date: last.adding(months: index - (values.count - 1)).endOfMonth, value: value)
        }
        let change = NetWorthChange(from: history[history.count - 2].date, to: last, start: 308_270, markets: 2_950,
                                    newMoney: 1_500, other: -240, end: 312_480)
        let owned: [(String, String, Decimal)] = [
            ("cash", "Cash", 53_100), ("equity", "Equity", 182_400), ("gold", "Gold", 6_100),
            ("crypto", "Crypto", 40_100), ("other", "Other", 30_780),
        ]
        let allocation = owned.map { key, name, value in
            AllocationSlice(key: key, name: name, value: value, share: value.doubleValue / 312_480)
        }
        let ages = [55, 55, 55, 55, 55, 54, 54, 54, 54]
        let answers = ages.enumerated().map { index, age in
            AnswerPoint(date: last.adding(months: index - (ages.count - 1)).endOfMonth, earliestAge: age)
        }
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 54,
                                      earliestDate: today.adding(months: 186).adding(days: 7), targetAge: 55,
                                      sustainableSpending: 38_400, readiness: 0.58)
        return GlanceSnapshot(
            currency: .eur,
            netWorth: NetWorthGlance(date: last, total: 312_480, isComplete: true, sinceLastCheckIn: change,
                                     thisYear: 0.142, history: history),
            allocation: allocation,
            retirement: RetirementGlance(answer: answer, history: answers),
            checkIn: CheckInGlance(last: last, next: today.endOfMonth),
            milestone: MilestoneGlance(kind: .roundAmount, amount: 400_000, progress: 0.78,
                                       typically: today.adding(months: 20)))
    }
}
