import CoreGraphics

/// Where the labels above *Your way to retirement*'s line go (UI.md, "Your
/// way to retirement"), so none of them collide. "Today" sits right of
/// today's tick, or left of it when it would run into "Last Monday", which
/// ends at the flag; when neither side has room (today's tick is under
/// "Last Monday"), "Last Monday" is left out and the flag stands alone,
/// "Today" right of its tick. The count of milestones reached sits halfway
/// between the line's start and today, clear of "Today"; it's shortened
/// ("21 reached") when the full count doesn't fit, and left out when even
/// that doesn't.
struct MilestoneTrackLabels: Equatable {
    /// How wide each label is, measured; 0 for a label the line doesn't have.
    struct Widths: Equatable {
        var reached: CGFloat = 0
        /// The count's short form, "21 reached".
        var reachedShort: CGFloat = 0
        var today: CGFloat = 0
        var lastMonday: CGFloat = 0
    }

    /// Where each label starts; `nil` for a label left out.
    var reached: CGFloat?
    /// Whether the count of milestones reached is in its short form.
    var reachedIsShort = false
    var today: CGFloat
    var lastMonday: CGFloat?

    /// The gap kept between two labels.
    static let gap: CGFloat = 6
    /// The gap between "Today" and its tick.
    static let tickGap: CGFloat = 4

    /// The labels of a track `width` points wide whose line starts at
    /// `start`, with today's tick at `now` and the flag at `flag` (`nil`
    /// without one, and so without "Last Monday"). `hasReached`: whether
    /// any milestone was reached, and so whether the count is shown.
    init(width: CGFloat, start: CGFloat, now: CGFloat, flag: CGFloat?, hasReached: Bool, widths: Widths) {
        func clamped(_ leading: CGFloat, _ labelWidth: CGFloat) -> CGFloat {
            max(0, min(leading, width - labelWidth))
        }
        let right = clamped(now + Self.tickGap, widths.today)
        let left = clamped(now - Self.tickGap - widths.today, widths.today)
        let lastMondayStart = flag.map { clamped($0 - widths.lastMonday, widths.lastMonday) }
        func fitsBeforeLastMonday(_ leading: CGFloat) -> Bool {
            guard let lastMondayStart else { return true }
            return leading + widths.today + Self.gap <= lastMondayStart
        }
        if fitsBeforeLastMonday(right) {
            today = right
            lastMonday = lastMondayStart
        } else if fitsBeforeLastMonday(left) {
            today = left
            lastMonday = lastMondayStart
        } else {
            today = right
            lastMonday = nil
        }
        let room = today - Self.gap
        reachedIsShort = widths.reached > room
        let reachedWidth = reachedIsShort ? widths.reachedShort : widths.reached
        if hasReached, reachedWidth <= room {
            let centered = (start + now) / 2 - reachedWidth / 2
            reached = max(0, min(centered, room - reachedWidth))
        } else {
            reached = nil
        }
    }
}
