import Foundation
import Model
import Tracker

/// Something that happens on a date within a chapter of the plan, marked
/// on its card on the strip (UI.md, "Plan"): an event, a pension or other
/// income starting after the chapter's first year, a later phase of
/// spending, a one-off saving.
public struct PlanChapterEvent: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// The plan's event at this index (``PlanDocument/events``).
        case event(Int)
        /// The plan's pension at this index, starting at `age`.
        case pension(Int, age: Int)
        /// The plan's other income at this index, starting at `age`.
        case income(Int, age: Int)
        /// The plan's later phase of spending at this index.
        case spendingPhase(Int)
        /// The plan's one-off contribution at this index, paid in `year`.
        case saving(Int, year: Int)
    }

    /// Inside the chapter's dates.
    public var date: Date
    public var kind: Kind

    public init(date: Date, kind: Kind) {
        self.date = date
        self.kind = kind
    }

    /// Unique within a chapter.
    public var id: String {
        switch kind {
        case .event(let index): "event-\(index)"
        case .pension(let index, _): "pension-\(index)"
        case .income(let index, _): "income-\(index)"
        case .spendingPhase(let index): "spending-\(index)"
        case .saving(let index, _): "saving-\(index)"
        }
    }
}

extension PlanChaptersModel {
    /// What happens on a date in the chapter at `index`, by date. Dates fall
    /// inside the chapter's (``dates(ofChapterAt:)``).
    public func events(inChapterAt index: Int, birthDate: CalendarDate) -> [PlanChapterEvent] {
        guard chapters.chapters.indices.contains(index) else { return [] }
        let chapter = chapters.chapters[index]
        let dates = self.dates(ofChapterAt: index)
        let birthYear = birthDate.year
        func inside(_ date: Date) -> Date { min(max(date, dates.lowerBound), dates.upperBound) }
        var events: [PlanChapterEvent] = []
        for item in chapter.items {
            switch item {
            case .event(let index) where plan.events.indices.contains(index):
                let date = switch plan.events[index].timing {
                case .year(let year): Self.midYear(year)
                case .age(let age): Self.birthday(birthDate, age: age)
                }
                events.append(PlanChapterEvent(date: inside(date), kind: .event(index)))
            case .pension(let index) where plan.pensions.indices.contains(index):
                guard let age = plan.pensions[index].fromAge, birthYear + age > chapter.years.lowerBound else {
                    continue
                }
                events.append(PlanChapterEvent(date: inside(Self.birthday(birthDate, age: age)),
                                               kind: .pension(index, age: age)))
            case .income(let index) where plan.income.indices.contains(index):
                guard let age = plan.income[index].from?.age, birthYear + age > chapter.years.lowerBound else {
                    continue
                }
                events.append(PlanChapterEvent(date: inside(Self.birthday(birthDate, age: age)),
                                               kind: .income(index, age: age)))
            case .spendingPhase(let index) where plan.spending.phases.indices.contains(index):
                let age = plan.spending.phases[index].fromAge
                guard birthYear + age > chapter.years.lowerBound else { continue }
                events.append(PlanChapterEvent(date: inside(Self.birthday(birthDate, age: age)),
                                               kind: .spendingPhase(index)))
            case .contribution(let index) where plan.contributions.indices.contains(index):
                let contribution = plan.contributions[index]
                guard contribution.isOneOff, contribution.amount != nil else { continue }
                let year = contribution.year ?? chapter.years.lowerBound
                events.append(PlanChapterEvent(date: inside(Self.midYear(year)), kind: .saving(index, year: year)))
            default:
                continue
            }
        }
        return events.sorted { $0.date < $1.date }
    }

    /// The round ages (multiples of 5) reached in the chapter at `index`,
    /// on their birthdays, kept clear of its edges' labels (120 days).
    public func ageTicks(inChapterAt index: Int, birthDate: CalendarDate) -> [(age: Int, date: Date)] {
        guard chapters.chapters.indices.contains(index) else { return [] }
        let dates = self.dates(ofChapterAt: index)
        let edge: TimeInterval = 120 * 86_400
        return chapters.chapters[index].ages.filter { $0 % 5 == 0 }.compactMap { age in
            let date = Self.birthday(birthDate, age: age)
            return date > dates.lowerBound + edge && date < dates.upperBound - edge ? (age, date) : nil
        }
    }

    /// The fan of `portfolio` in the chapter at `index`: at its start and
    /// at each year-end in it, two days either side allowed.
    public func fan(ofChapterAt index: Int, in portfolio: [FanPoint]) -> [FanPoint] {
        let dates = self.dates(ofChapterAt: index)
        let slack: TimeInterval = 2 * 86_400
        return portfolio.filter { $0.date >= dates.lowerBound - slack && $0.date <= dates.upperBound + slack }
    }

    /// The birthday at `age`, at noon.
    public static func birthday(_ birthDate: CalendarDate, age: Int) -> Date {
        let day = CalendarDate(year: birthDate.year + age, month: birthDate.month, day: min(birthDate.day, 28))
        return day?.dateValue ?? midYear(birthDate.year + age)
    }

    /// 1 July of `year`, at noon.
    public static func midYear(_ year: Int) -> Date {
        CalendarDate(year: year, month: 7, day: 1)?.dateValue ?? Date(timeIntervalSinceReferenceDate: 0)
    }
}
