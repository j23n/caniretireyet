import Foundation
import Model

/// The notes to schedule from a snapshot (UI.md, "Notifications"), worked
/// out again whenever the snapshot or the settings change:
///
/// - **Monthly:** on the chosen day and time, the answer and the ask to
///   check in for the month a check-in then is for (the month before, on
///   a day early in the month). After a month or two without a check-in it says where you
///   were at the last one and asks to catch up; after three, it comes
///   every third month.
/// - **Yearly:** *Your year* on 3 January, your birthday, the anniversary
///   of your first record, and a check-up a year after the main plan last
///   changed, each at 10:00.
/// - At most one note a day: the monthly one keeps its day, another moves
///   to the next free day.
/// - Never an amount.
public enum NotePlanner {
    /// How many months ahead monthly notes are scheduled.
    public static let months = 12
    /// When the yearly notes show.
    public static let yearlyHour = 10
    /// *Your year* shows on this day of January.
    public static let yourYearDay = 3
    /// A monthly note's milestone line shows from this far there.
    public static let milestoneShare = 0.8
    /// Months without a check-in after which the monthly note comes every third month.
    public static let quietAfter = 3

    /// The notes after `now`, soonest first.
    public static func notes(for snapshot: GlanceSnapshot, settings: NoteSettings, now: NoteTime,
                             locale: Locale = .current) -> [EngagementNote] {
        let words = Words(snapshot: snapshot, locale: locale)
        var notes: [EngagementNote] = []
        if settings.monthly {
            for offset in 0..<months {
                let month = now.date.yearMonth.adding(months: offset)
                let time = NoteTime(date: settings.date(in: month), hour: settings.hour, minute: settings.minute)
                guard time > now, let note = words.monthly(for: checkInMonth(on: time.date), at: time) else {
                    continue
                }
                notes.append(note)
            }
        }

        var yearly: [EngagementNote] = []
        if settings.yourYear, let note = words.yourYear(after: now) { yearly.append(note) }
        if settings.birthday, let note = words.birthday(after: now) { yearly.append(note) }
        if settings.recordsAnniversary, let note = words.recordsAnniversary(after: now) { yearly.append(note) }
        if settings.planCheckUp, let note = words.planCheckUp(after: now) { yearly.append(note) }

        // One note a day: the monthly one keeps its day.
        var taken = Set(notes.map(\.time.date))
        for var note in yearly.sorted(by: { $0.time < $1.time }) {
            while taken.contains(note.time.date) { note.time.date = note.time.date.adding(days: 1) }
            taken.insert(note.time.date)
            notes.append(note)
        }
        return notes.sorted { $0.time < $1.time }
    }

    /// The month a check-in on `date` is for, as the check-in's rules date
    /// it (`CheckInDates`, ``CheckInGlance``): its own in the month's last
    /// days, else the month before. A note on the 5th asks for the month
    /// that just ended.
    public static func checkInMonth(on date: CalendarDate) -> YearMonth {
        date.days(to: date.endOfMonth) < CheckInGlance.earlyCheckInDays ? date.yearMonth : date.yearMonth.previous
    }

    /// The first `date`'s anniversary at `hour` after `now`, a year or more
    /// after it, with how many years on it is.
    static func anniversary(of date: CalendarDate, hour: Int, after now: NoteTime) -> (time: NoteTime, years: Int) {
        var years = max(1, date.wholeYears(to: now.date))
        while true {
            let time = NoteTime(date: date.adding(years: years), hour: hour, minute: 0)
            if time > now { return (time, years) }
            years += 1
        }
    }
}

// MARK: - The words

/// The notes' words for one snapshot.
private struct Words {
    var snapshot: GlanceSnapshot
    var locale: Locale

    var journey: JourneyGlance { snapshot.journey ?? JourneyGlance() }
    var answer: RetirementAnswer? { snapshot.retirement?.answer }

    func monthName(_ month: YearMonth) -> String {
        month.lastDay.dateValue.formatted(Date.FormatStyle.dateTime.month(.wide).locale(locale))
    }

    func monthName(_ date: CalendarDate) -> String { monthName(date.yearMonth) }

    func monthAndYear(_ date: CalendarDate) -> String { GlanceText.monthAndYear(date, locale: locale) }

    /// The month the last check-in is for: its own, or the one before when
    /// it left its month due (``CheckInGlance``).
    var lastCheckInMonth: YearMonth? {
        snapshot.checkIn.last == nil ? nil : snapshot.checkIn.next.yearMonth.previous
    }

    // MARK: Monthly

    func monthly(for month: YearMonth, at time: NoteTime) -> EngagementNote? {
        let title = "\(monthName(month)) check-in"
        guard let due = lastCheckInMonth?.next else {
            // No check-in yet.
            let body = answer == nil ? noAnswerAsk(month) : "Import \(monthName(month))'s files to see where you stand."
            return EngagementNote(kind: .monthly, time: time, title: title, body: body, link: .checkIn)
        }
        let owed = due.months(to: month) + 1
        switch owed {
        case ...0:
            return nil
        case 1:
            guard let answer else {
                return EngagementNote(kind: .monthly, time: time, title: title, body: noAnswerAsk(month),
                                      link: .checkIn)
            }
            let body = [answerSentence(answer), milestoneSentence(),
                        "Import \(monthName(month))'s files to see where you stand."]
                .compactMap(\.self).joined(separator: " ")
            return EngagementNote(kind: .monthly, time: time, title: title, body: body, link: .checkIn,
                                  showsChart: true)
        case 2...NotePlanner.quietAfter:
            let months = (0..<owed).map { monthName(due.adding(months: $0)) + "'s" }
            let ask = "Catch up by importing \(Wording.list(months)) files together."
            let body = [lastCheckInSentence(), ask].compactMap(\.self).joined(separator: " ")
            return EngagementNote(kind: .catchUp, time: time, title: title, body: body, link: .checkIn)
        default:
            guard (owed - NotePlanner.quietAfter - 1) % 3 == 0 else { return nil }
            let body = [lastCheckInSentence(), "The months since then import together, whenever it suits you."]
                .compactMap(\.self).joined(separator: " ")
            return EngagementNote(kind: .quarterly, time: time, title: title, body: body, link: .checkIn)
        }
    }

    func noAnswerAsk(_ month: YearMonth) -> String {
        "Import \(monthName(month))'s files, then calculate your plan to see when you could retire."
    }

    /// "You could retire at 54, 2 years sooner than in January, and you're 58% ready."
    func answerSentence(_ answer: RetirementAnswer) -> String {
        var clauses: [String] = []
        if answer.canRetireNow {
            clauses.append("You could retire today")
        } else if let age = answer.earliestAge {
            clauses.append("You could retire at \(age)")
            if let move = moveSinceStartOfYear(age: age) { clauses.append(move) }
        } else {
            clauses.append("No retirement age works yet \(GlanceText.inFutures(answer.confidence))")
        }
        var sentence = clauses.joined(separator: ", ")
        if let figure = answer.readinessFigure.text(percent: { "\(Int(($0 * 100).rounded()))%" }) {
            sentence += ", and you're \(figure == "<5%" ? "under 5%" : figure) ready"
        }
        return sentence + "."
    }

    /// "2 years sooner than in January", "as in September": against the
    /// year's first check-in, or a year ago when the latest is the year's
    /// first; `nil` with nothing to compare.
    func moveSinceStartOfYear(age: Int) -> String? {
        guard let latest = journey.latest else { return nil }
        let firstThisYear = journey.checkIns.first { $0.date.year == latest.date.year }
        let reference: (point: JourneyPoint, words: String)?
        if let first = firstThisYear, first.date < latest.date {
            reference = (first, "in \(monthName(first.date))")
        } else if let yearAgo = journey.checkIn(onOrBefore: latest.date.adding(years: -1)) {
            reference = (yearAgo, "a year ago")
        } else {
            reference = nil
        }
        if let reference, let from = reference.point.earliestAge, from != age {
            return Self.yearsMoved(from: from, to: age) + " than \(reference.words)"
        }
        if let previous = journey.previous, previous.earliestAge == age {
            return "as in \(monthName(previous.date))"
        }
        return nil
    }

    /// "2 years sooner", "a year later".
    static func yearsMoved(from: Int, to: Int) -> String {
        let years = abs(to - from)
        let count = years == 1 ? "a year" : "\(years) years"
        return count + (to < from ? " sooner" : " later")
    }

    /// "5 years of spending is 80% there.", when the next milestone is that close.
    func milestoneSentence() -> String? {
        guard let milestone = snapshot.milestone, milestone.progress >= NotePlanner.milestoneShare,
              milestone.progress < 1
        else { return nil }
        let name = GlanceText.milestoneName(milestone) { _ in nil }
        return "\(name) is \(Int((milestone.progress * 100 + 1e-9).rounded(.down)))% there."
    }

    /// "At your August check-in you could retire at 54 and were 58% ready."
    func lastCheckInSentence() -> String? {
        guard let month = lastCheckInMonth, let point = journey.latest else { return nil }
        var sentence = "At your \(monthName(month)) check-in "
        if let age = point.earliestAge {
            sentence += "you could retire at \(age)"
            if let percent = point.readinessPercent { sentence += " and were \(percent)% ready" }
        } else if let percent = point.readinessPercent {
            sentence += "you were \(percent)% ready"
        } else {
            return nil
        }
        return sentence + "."
    }

    // MARK: Yearly

    /// *Your year* on the next 3 January: with the year's answer, what it
    /// saved and the milestones it passed once its December is checked in.
    func yourYear(after now: NoteTime) -> EngagementNote? {
        var date = CalendarDate(year: now.date.year, month: 1, day: NotePlanner.yourYearDay) ?? now.date
        if NoteTime(date: date, hour: NotePlanner.yearlyHour, minute: 0) <= now { date = date.adding(years: 1) }
        let time = NoteTime(date: date, hour: NotePlanner.yearlyHour, minute: 0)
        let year = date.year - 1
        guard journey.firstRecord.map({ $0.year <= year }) ?? false else { return nil }
        let title = "Your \(year)"
        guard let summary = journey.year(year), summary.isComplete else {
            return EngagementNote(kind: .yourYear, time: time, title: title,
                                  body: "Import December's files, then see how your \(year) went.",
                                  link: .checkIn)
        }
        var sentences: [String] = []
        if let end = journey.checkIn(onOrBefore: summary.to), let age = end.earliestAge {
            var sentence = "You could retire at \(age)"
            if let start = journey.checkIn(onOrBefore: summary.from), start.date < end.date,
               let from = start.earliestAge {
                sentence += from == age ? ", as a year ago" : ", " + Self.yearsMoved(from: from, to: age)
                    + " than a year ago"
            }
            sentences.append(sentence + ".")
        }
        let saved = SpendingTime(amount: summary.saved, yearlySpending: journey.yearlySpending ?? 0)
            .map { "saved \($0.text) of the life you plan" }
        let reached = journey.reachedCount(in: year)
        let passed = reached == 0 ? nil : reached == 1 ? "passed a milestone" : "passed \(reached) milestones"
        let done = [saved, passed].compactMap(\.self)
        if !done.isEmpty { sentences.append("You \(done.joined(separator: " and ")).") }
        sentences.append("See your year.")
        return EngagementNote(kind: .yourYear, time: time, title: title, body: sentences.joined(separator: " "),
                              link: .yourYear)
    }

    /// On your next birthday, how far away retiring is.
    func birthday(after now: NoteTime) -> EngagementNote? {
        guard let birthDate = journey.birthDate, let answer, !answer.canRetireNow,
              let age = answer.earliestAge, let date = answer.earliestDate
        else { return nil }
        let next = NotePlanner.anniversary(of: birthDate, hour: NotePlanner.yearlyHour, after: now)
        guard let countdown = RetirementCountdown(from: next.time.date, to: date) else { return nil }
        let body = "Your last Monday is \(countdown.awayText): you could retire at \(age), in "
            + "\(monthAndYear(date)), \(GlanceText.inFutures(answer.confidence))."
        return EngagementNote(kind: .birthday, time: next.time, title: "\(next.years) today", body: body,
                              link: .plan)
    }

    /// On the anniversary of the first record, how far you've come.
    func recordsAnniversary(after now: NoteTime) -> EngagementNote? {
        guard let first = journey.firstRecord else { return nil }
        let next = NotePlanner.anniversary(of: first, hour: NotePlanner.yearlyHour, after: now)
        let title = Self.years(next.years) + " of records"
        let body: String
        if let start = journey.firstWithAge, let latest = journey.latest, start.date < latest.date,
           let from = start.earliestAge, let to = latest.earliestAge {
            var sentence = "Since \(monthAndYear(start.date)) the age you could retire at "
            sentence += from == to ? "stayed at \(to)" : "went from \(from) to \(to)"
            if let fromPercent = start.readinessPercent, let toPercent = latest.readinessPercent {
                sentence += ", and you went from \(fromPercent)% to \(toPercent)% of what retiring today needs"
            }
            body = sentence + "."
        } else {
            body = "Your first record was in \(monthAndYear(first)). Every check-in since is part of the way there."
        }
        return EngagementNote(kind: .recordsAnniversary, time: next.time, title: title, body: body,
                              link: .overview)
    }

    /// A year after the main plan last changed, a nudge to look it over.
    func planCheckUp(after now: NoteTime) -> EngagementNote? {
        guard let changed = journey.planChanged, let name = journey.planName else { return nil }
        let next = NotePlanner.anniversary(of: changed, hour: NotePlanner.yearlyHour, after: now)
        let on = next.years == 1 ? "a year on" : "\(next.years) years on"
        let body = "Your plan last changed in \(monthAndYear(changed)). Do its pay, spending and retirement age "
            + "still fit your life? A few minutes keeps the answer honest."
        return EngagementNote(kind: .planCheckUp, time: next.time, title: "\(name), \(on)", body: body, link: .plan)
    }

    /// "A year", "Five years", "12 years".
    static func years(_ count: Int) -> String {
        let words = ["A year", "Two years", "Three years", "Four years", "Five years", "Six years", "Seven years",
                     "Eight years", "Nine years", "Ten years"]
        return count >= 1 && count <= words.count ? words[count - 1] : "\(count) years"
    }
}
