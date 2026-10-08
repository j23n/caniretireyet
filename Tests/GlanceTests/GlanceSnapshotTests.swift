import Foundation
import Glance
import Model
import Testing
import TestSupport
import Tracker

private let checkIn = CheckInGlance(last: "2026-09-30", next: "2026-10-31")

/// The snapshot of the example library, as of its latest check-in.
struct ExampleLibraryGlanceTests {
    let library: Library
    let valuator: Valuator
    let snapshot: GlanceSnapshot

    init() throws {
        library = try Fixtures.exampleLibrary()
        valuator = Valuator(library: library)
        snapshot = GlanceSnapshot(library: library, valuator: valuator, asOf: "2026-09-30", answer: nil,
                                  checkIn: checkIn)
    }

    @Test func netWorthIsTheOverviews() throws {
        #expect(snapshot.version == GlanceSnapshot.currentVersion)
        #expect(snapshot.currency == .eur)
        let netWorth = try #require(snapshot.netWorth)
        #expect(netWorth.date == "2026-09-30")
        #expect(netWorth.total == valuator.netWorth(on: "2026-09-30").total)
        #expect(netWorth.isComplete)
    }

    @Test func theChangeSinceTheLastCheckInIsSplit() throws {
        // As in ExampleLibraryChangeTests.
        let change = try #require(snapshot.netWorth?.sinceLastCheckIn)
        #expect(change.from == "2026-08-31")
        #expect(change.to == "2026-09-30")
        #expect(change.start.rounded(2) == d("327037.83"))
        #expect(change.end.rounded(2) == d("332455.49"))
        #expect(change.newMoney == d("2181.65"))
        #expect(change.markets.rounded(6) == d("3236.011765"))
        #expect(change.other == 0)
        #expect(change.end == snapshot.netWorth?.total)
        let fraction = try #require(change.fraction)
        #expect(abs(fraction - (332455.49 - 327037.83) / 327037.83) < 1e-7)
    }

    @Test func netWorthIsTodaysAfterTheLatestCheckIn() throws {
        let later = GlanceSnapshot(library: library, valuator: valuator, asOf: "2026-10-08", answer: nil,
                                   checkIn: checkIn)
        let netWorth = try #require(later.netWorth)
        #expect(netWorth.date == "2026-10-08")
        #expect(netWorth.total == valuator.netWorth(on: "2026-10-08").total)
        #expect(netWorth.history.last?.date == "2026-10-08")
        // The change is still the last check-in's.
        #expect(netWorth.sinceLastCheckIn?.from == "2026-08-31")
        #expect(netWorth.sinceLastCheckIn?.to == "2026-09-30")
        #expect(netWorth.sinceLastCheckIn == snapshot.netWorth?.sinceLastCheckIn)
    }

    @Test func aChangeWithoutItsEndStillReads() throws {
        let json = #"{"from":"2026-08-31","start":"100","markets":"1","newMoney":"2","other":"0","end":"103"}"#
        let change = try JSONDecoder().decode(NetWorthChange.self, from: Data(json.utf8))
        #expect(change.to == nil)
        #expect(change.change == 3)
    }

    @Test func theHistoryIsTheYearsMonthEnds() throws {
        let history = try #require(snapshot.netWorth?.history)
        #expect(history.last?.date == "2026-09-30")
        #expect(history.allSatisfy { $0.date >= "2025-09-30" && $0.date.isEndOfMonth })
        #expect(history.map(\.date) == history.map(\.date).sorted())
        #expect(history.count <= 13)
        for point in history {
            #expect(point.value == valuator.total(on: point.date, in: .netWorth).total)
        }
    }

    @Test func thisYearIsSinceTheEndOfLastYear() throws {
        let thisYear = try #require(snapshot.netWorth?.thisYear)
        let start = valuator.total(on: "2025-12-31", in: .netWorth).total
        let now = valuator.total(on: "2026-09-30", in: .netWorth).total
        let expected = NSDecimalNumber(decimal: (now - start) / abs(start)).doubleValue
        #expect(abs(thisYear - expected) < 1e-12)
    }

    @Test func allocationIsByAssetClassInStackingOrder() throws {
        let keys = snapshot.allocation.map(\.key)
        #expect(!keys.isEmpty)
        #expect(keys.last == AllocationSlice.debts)
        let order = BreakdownKey.assetClassOrder.map(\.rawValue)
        let classes = keys.dropLast().map { order.firstIndex(of: $0) ?? order.count }
        #expect(classes == classes.sorted())
        let total = snapshot.allocation.reduce(Decimal(0)) { $0 + $1.value }
        #expect(total.rounded(10) == snapshot.netWorth?.total.rounded(10))
        let debts = try #require(snapshot.allocation.last)
        #expect(debts.value < 0)
        #expect(debts.name == "Debts")
        let owned = snapshot.allocation.filter { $0.value > 0 }.compactMap(\.share).reduce(0, +)
        #expect(abs(owned - 1) < 1e-9)
    }

    @Test func withoutResultsTheAnswerIsTheLastOneRecorded() throws {
        let answer = try #require(snapshot.retirement).answer
        #expect(answer.earliestAge == 54)
        // Born 12 April 1988.
        #expect(answer.earliestDate == "2042-04-12")
        #expect(answer.confidence == 0.9)
        #expect(answer.readiness == 0.25)
        #expect(!answer.canRetireNow)
        #expect(answer.sustainableSpending == nil)
    }

    @Test func theHistoryHasTheYearsAnswers() throws {
        let retirement = try #require(snapshot.retirement)
        #expect(retirement.history.map(\.date) == [
            "2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31",
            "2026-06-30", "2026-07-31", "2026-08-31", "2026-09-30",
        ])
        #expect(retirement.history.map(\.earliestAge) == [55, 55, 55, 55, 55, 54, 54, 54, 54])
        let move = try #require(retirement.lastMove)
        #expect(move == AnswerMove(from: 55, to: 54, date: "2026-06-30"))
        #expect(move.isSooner)
    }

    @Test func resultsTakeThePlaceOfTheRecordedAnswer() throws {
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 54, earliestDate: "2042-04-12", targetAge: 55,
                                      sustainableSpending: 38_400, readiness: 0.58)
        let snapshot = GlanceSnapshot(library: library, valuator: valuator, asOf: "2026-09-30", answer: answer,
                                      checkIn: checkIn)
        #expect(snapshot.retirement?.answer == answer)
        #expect(snapshot.retirement?.history.count == 9)
        #expect(snapshot.retirement?.lastMove?.to == 54)
    }

    @Test func aMoveIsLeftOutWhenTheAnswerIsNoLongerTheRecordedOne() throws {
        // The plan was changed and calculated since the latest check-in.
        let answer = RetirementAnswer(confidence: 0.9, earliestAge: 53)
        let snapshot = GlanceSnapshot(library: library, valuator: valuator, asOf: "2026-09-30", answer: answer,
                                      checkIn: checkIn)
        #expect(snapshot.retirement?.answer.earliestAge == 53)
        #expect(snapshot.retirement?.lastMove == nil)
    }

    @Test func anEarlierAsOfLeavesOutLaterAnswers() throws {
        let snapshot = GlanceSnapshot(library: library, valuator: valuator, asOf: "2026-05-31", answer: nil,
                                      checkIn: checkIn)
        #expect(snapshot.retirement?.history.last?.date == "2026-05-31")
        #expect(snapshot.retirement?.lastMove == nil)
        #expect(snapshot.netWorth?.history.last?.date == "2026-05-31")
    }

    @Test func noMainPlanNoAnswer() throws {
        var library = library
        library.settings.mainPlan = nil
        let snapshot = GlanceSnapshot(library: library, valuator: Valuator(library: library), asOf: "2026-09-30",
                                      answer: RetirementAnswer(confidence: 0.9, earliestAge: 54), checkIn: checkIn)
        #expect(snapshot.retirement == nil)
        #expect(snapshot.netWorth != nil)
    }

    @Test func roundTripsThroughItsFile() throws {
        let data = try GlanceFile.data(for: snapshot)
        #expect(GlanceFile.snapshot(from: data) == snapshot)
        // Amounts are exact strings, as in the library's files.
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"newMoney\":\"2181.65\""))
        #expect(try GlanceFile.data(for: snapshot) == data)
    }

    @Test func writesAndReadsAFile() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Glance").appendingPathComponent(GlanceFile.name)
        #expect(GlanceFile.read(at: url) == nil)
        try GlanceFile.write(snapshot, to: url)
        #expect(GlanceFile.read(at: url) == snapshot)
    }
}

/// Snapshots of libraries that have little in them, and of other formats.
struct GlanceSnapshotTests {
    @Test func aNewLibraryHasOnlyItsCheckIn() {
        let library = Library(settings: LibrarySettings(baseCurrency: .usd))
        let today: CalendarDate = "2026-10-05"
        let checkIn = CheckInGlance(last: nil, today: today)
        let snapshot = GlanceSnapshot(library: library, valuator: Valuator(library: library), asOf: today,
                                      answer: nil, checkIn: checkIn)
        #expect(snapshot.currency == .usd)
        #expect(snapshot.netWorth == nil)
        #expect(snapshot.allocation.isEmpty)
        #expect(snapshot.retirement == nil)
        #expect(snapshot.checkIn.isDue(on: today))
    }

    @Test func aNewerFormatIsSkipped() throws {
        var snapshot = GlanceSnapshot(currency: .eur, netWorth: nil, allocation: [], retirement: nil,
                                      checkIn: CheckInGlance(last: nil, next: "2026-10-31"))
        snapshot.version = GlanceSnapshot.currentVersion + 1
        #expect(GlanceFile.snapshot(from: try GlanceFile.data(for: snapshot)) == nil)
        #expect(GlanceFile.snapshot(from: Data("not json".utf8)) == nil)
    }

    @Test func missingListsReadAsEmpty() throws {
        let json = #"{"version":1,"currency":"EUR","checkIn":{"next":"2026-10-31"}}"#
        let snapshot = try #require(GlanceFile.snapshot(from: Data(json.utf8)))
        #expect(snapshot.allocation.isEmpty)
        #expect(snapshot.netWorth == nil)
    }

    @Test func theNextMilestoneRoundTripsAndOlderSnapshotsHaveNone() throws {
        let milestone = MilestoneGlance(kind: .shareOfNeeded, amount: 333_333, share: d("0.3333"), progress: 0.88,
                                        typically: "2028-02-29")
        let snapshot = GlanceSnapshot(currency: .eur, netWorth: nil, allocation: [], retirement: nil,
                                      checkIn: CheckInGlance(last: nil, next: "2026-10-31"),
                                      milestone: milestone)
        let data = try GlanceFile.data(for: snapshot)
        #expect(GlanceFile.snapshot(from: data)?.milestone == milestone)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"amount\":\"333333\""))

        let older = #"{"version":1,"currency":"EUR","checkIn":{"next":"2026-10-31"}}"#
        #expect(try #require(GlanceFile.snapshot(from: Data(older.utf8))).milestone == nil)
    }

    @Test func theNextMilestoneInWords() {
        func amount(_ value: Decimal) -> String? { "\(value) €" }
        #expect(GlanceText.milestoneName(MilestoneGlance(kind: .roundAmount, amount: 300_000, progress: 0.9),
                                         amount: amount) == "300000 €")
        #expect(GlanceText.milestoneName(MilestoneGlance(kind: .roundAmount, amount: 300_000, progress: 0.9),
                                         amount: { _ in nil }) == "A round amount")
        #expect(GlanceText.milestoneName(MilestoneGlance(kind: .yearsOfSpending, amount: 360_000, years: 10,
                                                         progress: 0.9), amount: amount) == "10 years of spending")
        #expect(GlanceText.milestoneName(MilestoneGlance(kind: .shareOfNeeded, amount: 500_000, share: d("0.5"),
                                                         progress: 0.9), amount: amount)
            == "Half of what retiring today needs")
        #expect(GlanceText.milestoneName(MilestoneGlance(kind: .crossover, amount: 400_000, progress: 0.9),
                                         amount: amount) == "The crossover")
        #expect(GlanceText.typically("2027-06-30") == "Typically by mid 2027")
        #expect(GlanceText.typically("2028-02-29") == "Typically by early 2028")
    }

    @Test func aRecordedAnswerNeverRetiresBeforeItsCheckIn() throws {
        let headline = Headline(date: "2026-09-30", confidence: d("0.9"), earliestAge: 38, engine: "0.1.0",
                                planHash: "x", readiness: d("1.02"))
        let answer = RetirementAnswer(recorded: headline, birthDate: "1988-04-12")
        // Turned 38 on 12 April 2026, before the check-in.
        #expect(answer.earliestDate == "2026-09-30")
        #expect(answer.canRetireNow)
        #expect(RetirementAnswer(recorded: headline, birthDate: nil).earliestDate == nil)
    }
}
