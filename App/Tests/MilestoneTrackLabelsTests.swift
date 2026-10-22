import CoreGraphics
import Testing
@testable import CanIRetireYet

/// Where the labels above *Your way to retirement*'s line go (UI.md, "Your
/// way to retirement"): "Today", "Last Monday" and the count of milestones
/// reached never collide.
struct MilestoneTrackLabelsTests {
    /// About the labels' widths in English at the default text size.
    private let widths = MilestoneTrackLabels.Widths(reached: 118, reachedShort: 60, today: 37, lastMonday: 76)
    /// The track on a 393-point-wide iPhone, inside the card, and on the Mac.
    private let iPhone: CGFloat = 329
    private let mac: CGFloat = 640
    private let inset: CGFloat = 8

    private func labels(width: CGFloat, now: CGFloat, flag: CGFloat?, widths: MilestoneTrackLabels.Widths? = nil,
                        hasReached: Bool = true) -> MilestoneTrackLabels {
        MilestoneTrackLabels(width: width, start: inset, now: now, flag: flag, hasReached: hasReached,
                             widths: widths ?? self.widths)
    }

    /// The shown labels' spans, left to right.
    private func spans(_ row: MilestoneTrackLabels,
                       widths: MilestoneTrackLabels.Widths? = nil) -> [ClosedRange<CGFloat>] {
        let widths = widths ?? self.widths
        let reachedWidth = row.reachedIsShort ? widths.reachedShort : widths.reached
        return [row.reached.map { $0...($0 + reachedWidth) },
                row.today...(row.today + widths.today),
                row.lastMonday.map { $0...($0 + widths.lastMonday) }]
            .compactMap { $0 }
    }

    private func areApart(_ spans: [ClosedRange<CGFloat>], width: CGFloat) -> Bool {
        zip(spans, spans.dropFirst()).allSatisfy { $0.upperBound + MilestoneTrackLabels.gap <= $1.lowerBound }
            && spans.allSatisfy { $0.lowerBound >= 0 && $0.upperBound <= width }
    }

    @Test func todayIsRightOfItsTickFarFromTheEnd() {
        let row = labels(width: iPhone, now: 160, flag: iPhone - inset)
        #expect(row.today == 164)
        #expect(row.lastMonday == iPhone - inset - 76)
        #expect(row.reached == 25)
    }

    @Test func todayMovesLeftOfItsTickCloseToTheEnd() throws {
        let flag = iPhone - inset
        let row = labels(width: iPhone, now: flag - 90, flag: flag)
        #expect(row.today == flag - 90 - 4 - 37)
        let lastMonday = try #require(row.lastMonday)
        #expect(lastMonday == flag - 76)
        #expect(row.today + 37 + MilestoneTrackLabels.gap <= lastMonday)
    }

    @Test func theFlagStandsAloneWhenTodayIsUnderLastMonday() {
        let flag = iPhone - inset
        let row = labels(width: iPhone, now: flag - 30, flag: flag)
        #expect(row.lastMonday == nil)
        #expect(row.today == iPhone - 37)
    }

    @Test func todayAndLastMondayNeverOverlap() {
        for width in [iPhone, mac] {
            let flag = width - inset
            for now in stride(from: inset, through: flag, by: 1) {
                let row = labels(width: width, now: now, flag: flag)
                #expect(areApart(spans(row), width: width), "now \(now) of \(width)")
            }
            // "Last Monday" stays while today's tick is left of it.
            for now in stride(from: inset, to: flag - 76 - MilestoneTrackLabels.gap, by: 1) {
                #expect(labels(width: width, now: now, flag: flag).lastMonday != nil, "now \(now) of \(width)")
            }
        }
    }

    @Test func theFlagStandsAloneWithoutRoomForBoth() {
        let large = MilestoneTrackLabels.Widths(reached: 260, reachedShort: 130, today: 90, lastMonday: 190)
        let width: CGFloat = 250
        for now in stride(from: inset, through: width - inset, by: 1) {
            let row = labels(width: width, now: now, flag: width - inset, widths: large)
            #expect(areApart(spans(row, widths: large), width: width), "now \(now)")
        }
        #expect(labels(width: width, now: 100, flag: width - inset, widths: large).lastMonday == nil)
    }

    @Test func theCountOfMilestonesReachedStaysClearOfToday() {
        let row = labels(width: iPhone, now: 30, flag: iPhone - inset)
        #expect(row.reached == nil)
        #expect(labels(width: iPhone, now: 30, flag: iPhone - inset, hasReached: false).reached == nil)
        let later = labels(width: iPhone, now: 140, flag: iPhone - inset)
        #expect(later.reached == 15)
        #expect(!later.reachedIsShort)
        #expect(areApart(spans(later), width: iPhone))
    }

    /// 5 years of records with 15 to go puts today a quarter of the way
    /// along an iPhone's track: the full count doesn't fit, its short form does.
    @Test func theCountOfMilestonesReachedIsShortenedWhenTight() {
        let row = labels(width: iPhone, now: 86, flag: iPhone - inset)
        #expect(row.reachedIsShort)
        #expect(row.reached == 17)
        #expect(areApart(spans(row), width: iPhone))
    }

    @Test func theCountOfMilestonesReachedIsShownWheneverItsShortFormFits() {
        for width in [iPhone, mac] {
            let flag = width - inset
            for now in stride(from: inset, through: flag, by: 1) {
                let row = labels(width: width, now: now, flag: flag)
                #expect(areApart(spans(row), width: width), "now \(now) of \(width)")
                let room = row.today - MilestoneTrackLabels.gap
                #expect((row.reached != nil) == (widths.reachedShort <= room), "now \(now) of \(width)")
                if row.reached != nil {
                    #expect(row.reachedIsShort == (widths.reached > room), "now \(now) of \(width)")
                }
            }
        }
    }

    @Test func withoutAFlagTodayStaysOnTheTrack() {
        let row = labels(width: iPhone, now: iPhone - inset, flag: nil)
        #expect(row.lastMonday == nil)
        #expect(row.today == iPhone - 37)
    }
}
