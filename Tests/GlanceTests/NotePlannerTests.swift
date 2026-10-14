import Foundation
import Glance
import Model
import Testing

private let english = Locale(identifier: "en_US")

/// A snapshot after check-ins at the given month ends, with their answers.
private func snapshot(checkIns: [JourneyPoint], answer: RetirementAnswer?, milestone: MilestoneGlance? = nil,
                      journey: (inout JourneyGlance) -> Void = { _ in }) -> GlanceSnapshot {
    let last = checkIns.last?.date
    var trip = JourneyGlance(birthDate: "1987-10-20", firstRecord: checkIns.first?.date, checkIns: checkIns,
                             planName: "Base case", planChanged: checkIns.first?.date, yearlySpending: 36525)
    journey(&trip)
    return GlanceSnapshot(currency: .eur, netWorth: nil, allocation: [],
                          retirement: answer.map { RetirementGlance(answer: $0, history: []) },
                          checkIn: CheckInGlance(last: last, today: last ?? "2026-10-14"), milestone: milestone,
                          journey: trip)
}

private func answer(age: Int?, readiness: Double?, date: CalendarDate? = "2042-03-12") -> RetirementAnswer {
    RetirementAnswer(confidence: 0.9, earliestAge: age, earliestDate: date, readiness: readiness)
}

private let year: [JourneyPoint] = [
    JourneyPoint(date: "2025-12-31", earliestAge: 56, readiness: 0.46),
    JourneyPoint(date: "2026-01-31", earliestAge: 56, readiness: 0.47),
    JourneyPoint(date: "2026-04-30", earliestAge: 55, readiness: 0.51),
    JourneyPoint(date: "2026-08-31", earliestAge: 54, readiness: 0.56),
    JourneyPoint(date: "2026-09-30", earliestAge: 54, readiness: 0.58),
]

private let now = NoteTime(date: "2026-10-14", hour: 9, minute: 0)

struct NotePlannerMonthlyTests {
    @Test func theNextMonthlyNoteTellsTheAnswerAndAsks() throws {
        let fiveYears = MilestoneGlance(kind: .yearsOfSpending, amount: 150_000, years: 5, progress: 0.8)
        let notes = NotePlanner.notes(for: snapshot(checkIns: year, answer: answer(age: 54, readiness: 0.58),
                                                    milestone: fiveYears),
                                      settings: .standard, now: now, locale: english)
        let first = try #require(notes.first)
        #expect(first.kind == .monthly)
        #expect(first.time == NoteTime(date: "2026-10-31", hour: 19, minute: 0))
        #expect(first.title == "October check-in")
        #expect(first.body == "You could retire at 54, 2 years sooner than in January, and you're 58% ready. "
            + "5 years of spending is 80% there. Import October's files to see where you stand.")
        #expect(first.link == .checkIn)
        #expect(first.showsChart)
    }

    @Test func aNoteEarlyInTheMonthAsksForTheMonthBefore() throws {
        var settings = NoteSettings.standard
        settings.day = 5
        let notes = NotePlanner.notes(for: snapshot(checkIns: year, answer: answer(age: 54, readiness: 0.58)),
                                      settings: settings, now: NoteTime(date: "2026-10-01", hour: 9, minute: 0),
                                      locale: english)
            .filter { $0.kind != .yourYear && $0.kind != .birthday && $0.kind != .recordsAnniversary }
        // After September's check-in nothing is due on 5 October.
        let first = try #require(notes.first)
        #expect(first.time.date == "2026-11-05")
        #expect(first.kind == .monthly)
        #expect(first.title == "October check-in")
        #expect(first.body.hasSuffix("Import October's files to see where you stand."))
        #expect(notes.dropFirst().first?.title == "November check-in")
    }

    @Test func anAnswerThatDidNotMoveSaysSo() throws {
        let still = [JourneyPoint(date: "2026-01-31", earliestAge: 54, readiness: 0.5),
                     JourneyPoint(date: "2026-09-30", earliestAge: 54, readiness: 0.58)]
        let notes = NotePlanner.notes(for: snapshot(checkIns: still, answer: answer(age: 54, readiness: 0.58)),
                                      settings: .standard, now: now, locale: english)
        #expect(notes.first?.body
            == "You could retire at 54, as in January, and you're 58% ready. Import October's files to see where you stand.")
    }

    @Test func withoutAnAnswerItAsksToCalculate() throws {
        let notes = NotePlanner.notes(for: snapshot(checkIns: year, answer: nil), settings: .standard, now: now,
                                      locale: english)
        #expect(notes.first?.body
            == "Import October's files, then calculate your plan to see when you could retire.")
        #expect(notes.first?.showsChart == false)
    }

    @Test func missedMonthsAskToCatchUpThenComeEveryThirdMonth() throws {
        let notes = NotePlanner.notes(for: snapshot(checkIns: Array(year.prefix(4)),
                                                    answer: answer(age: 54, readiness: 0.56)),
                                      settings: .standard, now: now, locale: english)
            .filter { $0.kind != .yourYear }
        // The last check-in was August's: September is owed.
        let october = try #require(notes.first)
        #expect(october.kind == .catchUp)
        #expect(october.title == "October check-in")
        #expect(october.body == "At your August check-in you could retire at 54 and were 56% ready. "
            + "Catch up by importing September's and October's files together.")
        #expect(notes[1].kind == .catchUp)
        #expect(notes[1].body.hasSuffix("importing September's, October's and November's files together."))
        // Three months missed: every third month from December.
        #expect(notes[2].kind == .quarterly)
        #expect(notes[2].title == "December check-in")
        #expect(notes[2].body == "At your August check-in you could retire at 54 and were 56% ready. "
            + "The months since then import together, whenever it suits you.")
        #expect(notes.dropFirst(2).map(\.time.date)
            == ["2026-12-31", "2027-03-31", "2027-06-30", "2027-09-30"])
        #expect(notes.allSatisfy { !$0.showsChart })
    }

    @Test func aMonthAlreadyCheckedInGetsNoNote() throws {
        let early = year + [JourneyPoint(date: "2026-10-28", earliestAge: 54, readiness: 0.6)]
        let notes = NotePlanner.notes(for: snapshot(checkIns: early, answer: answer(age: 54, readiness: 0.6)),
                                      settings: .standard, now: NoteTime(date: "2026-10-29", hour: 9, minute: 0),
                                      locale: english)
        #expect(notes.first?.title == "November check-in")
    }

    @Test func onlyTurningANoteOnAsksForPermission() {
        var fewer = NoteSettings.standard
        fewer.monthly = false
        #expect(!fewer.turnsOnNote(from: .standard))
        #expect(fewer.turnsOnNote(from: .off))
        var later = NoteSettings.standard
        later.hour = 21
        #expect(!later.turnsOnNote(from: .standard))
        #expect(!NoteSettings.off.turnsOnNote(from: .standard))
    }

    @Test func theChosenDayAndTimeHold() throws {
        var settings = NoteSettings.standard
        settings.day = 15
        settings.hour = 8
        settings.minute = 30
        let notes = NotePlanner.notes(for: snapshot(checkIns: year, answer: answer(age: 54, readiness: 0.58)),
                                      settings: settings, now: now, locale: english)
        // A check-in on 15 October is still September's, which is done.
        #expect(notes.first?.time == NoteTime(date: "2026-11-15", hour: 8, minute: 30))
        #expect(notes.first?.title == "October check-in")
        #expect(settings.date(in: "2027-02") == "2027-02-15")
        settings.day = 31
        #expect(settings.date(in: "2027-02") == "2027-02-28")
    }

    @Test func daysThatWouldSkipAMonthMoveTo25() {
        #expect(!NoteSettings.days.contains(22) && !NoteSettings.days.contains(24))
        var settings = NoteSettings.standard
        settings.day = 24
        #expect(settings.effectiveDay == 25)
        #expect(settings.date(in: "2026-10") == "2026-10-25")
        // On 25 October a check-in is October's, as on 25 November it's November's.
        #expect(NotePlanner.checkInMonth(on: "2026-10-25") == "2026-10")
        #expect(NotePlanner.checkInMonth(on: "2026-11-25") == "2026-11")
        #expect(NotePlanner.checkInMonth(on: "2026-10-21") == "2026-09")
    }

    @Test func offMeansNone() {
        #expect(NotePlanner.notes(for: snapshot(checkIns: year, answer: answer(age: 54, readiness: 0.58)),
                                  settings: .off, now: now).isEmpty)
    }
}

struct NotePlannerYearlyTests {
    let settings = NoteSettings(monthly: true, yourYear: true, birthday: true, recordsAnniversary: true,
                                planCheckUp: true)

    func notes(_ snapshot: GlanceSnapshot, now: NoteTime = now) -> [EngagementNote.Kind: EngagementNote] {
        Dictionary(NotePlanner.notes(for: snapshot, settings: settings, now: now, locale: english)
            .filter { $0.kind != .monthly && $0.kind != .catchUp && $0.kind != .quarterly }
            .map { ($0.kind, $0) }) { first, _ in first }
    }

    @Test func yourYearLooksBackOnceDecemberIsIn() throws {
        let checkIns = year + [JourneyPoint(date: "2026-12-31", earliestAge: 54, readiness: 0.6)]
        let done = snapshot(checkIns: checkIns, answer: answer(age: 54, readiness: 0.6)) {
            $0.firstRecord = "2021-10-31"
            $0.reached = ["2026-03-31", "2026-08-31", "2025-06-30"]
            $0.years = [JourneyYear(year: 2026, from: "2025-12-31", to: "2026-12-31", saved: 24350, markets: 9000)]
        }
        let note = try #require(notes(done, now: NoteTime(date: "2027-01-02", hour: 9, minute: 0))[.yourYear])
        #expect(note.time == NoteTime(date: "2027-01-03", hour: 10, minute: 0))
        #expect(note.title == "Your 2026")
        #expect(note.body == "You could retire at 54, 2 years sooner than a year ago. "
            + "You saved about 8 months of the life you plan and passed 2 milestones. See your year.")
        #expect(note.link == .yourYear)
    }

    @Test func yourYearAsksForDecemberFirst() throws {
        let note = try #require(notes(snapshot(checkIns: year, answer: answer(age: 54, readiness: 0.58)))[.yourYear])
        #expect(note.title == "Your 2026")
        #expect(note.body == "Import December's files, then see how your 2026 went.")
    }

    @Test func theBirthdaySaysHowFarAwayRetiringIs() throws {
        let note = try #require(notes(snapshot(checkIns: year, answer: answer(age: 54, readiness: 0.58)))[.birthday])
        #expect(note.time == NoteTime(date: "2026-10-20", hour: 10, minute: 0))
        #expect(note.title == "39 today")
        #expect(note.body == "Your last Monday is about 15 years away: you could retire at 54, in March 2042, "
            + "in 9 of 10 futures.")
    }

    @Test func theRecordsAnniversaryTellsHowFarYouCame() throws {
        let note = try #require(notes(snapshot(checkIns: year, answer: answer(age: 54, readiness: 0.58)) {
            $0.firstRecord = "2021-10-31"
        })[.recordsAnniversary])
        // Its day has the monthly note: it moves to the next.
        #expect(note.time == NoteTime(date: "2026-11-01", hour: 10, minute: 0))
        #expect(note.title == "Five years of records")
        #expect(note.body == "Since December 2025 the age you could retire at went from 56 to 54, "
            + "and you went from 46% to 58% of what retiring today needs.")
    }

    @Test func thePlanCheckUpComesAYearAfterItChanged() throws {
        let note = try #require(notes(snapshot(checkIns: year, answer: answer(age: 54, readiness: 0.58)) {
            $0.planChanged = "2025-10-31"
        })[.planCheckUp])
        #expect(note.time == NoteTime(date: "2026-11-01", hour: 10, minute: 0))
        #expect(note.title == "Base case, a year on")
        #expect(note.body.hasPrefix("Your plan last changed in October 2025."))
        #expect(note.link == .plan)
    }

    @Test func atMostOneNoteADay() {
        let all = NotePlanner.notes(
            for: snapshot(checkIns: year, answer: answer(age: 54, readiness: 0.58)) {
                $0.firstRecord = "2021-10-31"
                $0.planChanged = "2025-10-31"
            },
            settings: settings, now: now, locale: english)
        #expect(Set(all.map(\.time.date)).count == all.count)
        #expect(all.map(\.time) == all.map(\.time).sorted())
    }
}
