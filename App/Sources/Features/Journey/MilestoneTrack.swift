import Glance
import Model
import Planner
import SwiftUI

/// The way from your first record to the day you could retire, as a line
/// with the milestones on it (UI.md, "Your way to retirement"): solid up
/// to today with the milestones reached as dots, dashed after it with those
/// ahead as rings where the plan's median future typically reaches them,
/// the next one larger and named, and a flag at your last Monday. Its ends
/// are labeled with their years ("2018", "2031").
struct MilestoneTrack: View {
    let start: CalendarDate
    let today: CalendarDate
    /// The day you could retire; `nil` without one, when the line ends at
    /// the last milestone ahead and has no flag.
    let retirement: CalendarDate?
    let reached: [ReachedMilestone]
    let ahead: [ProjectedMilestone]
    /// The next milestone and when it's typically reached.
    let next: (id: String, name: AmountSentence, date: CalendarDate)?

    @Environment(\.locale) private var locale
    /// The labels above the line, measured, so they can be kept apart.
    @State private var labelWidths = MilestoneTrackLabels.Widths()

    private static let height: CGFloat = 122
    private static let lineY: CGFloat = 60
    private static let inset: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    draw(in: &context, width: size.width)
                }
                labels(width: width)
            }
        }
        .frame(height: Self.height)
        .privacySensitiveInFeedback()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: summary))
    }

    /// The day the line ends at.
    private var end: CalendarDate {
        let last = ahead.last?.date ?? today.adding(years: 10)
        return max(retirement ?? last, today.adding(months: 6))
    }

    /// The milestones ahead that the line has room for: those by its end.
    var drawnAhead: [ProjectedMilestone] {
        ahead.filter { $0.date <= end }
    }

    private func x(_ date: CalendarDate, width: CGFloat) -> CGFloat {
        let span = Double(max(start.days(to: end), 1))
        let share = min(max(Double(start.days(to: date)) / span, 0), 1)
        return Self.inset + (width - 2 * Self.inset) * share
    }

    private func draw(in context: inout GraphicsContext, width: CGFloat) {
        let y = Self.lineY
        let now = x(today, width: width)
        let right = x(end, width: width)
        var past = Path()
        past.move(to: CGPoint(x: Self.inset, y: y))
        past.addLine(to: CGPoint(x: now, y: y))
        context.stroke(past, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        var future = Path()
        future.move(to: CGPoint(x: now, y: y))
        future.addLine(to: CGPoint(x: right, y: y))
        context.stroke(future, with: .color(Palette.mutedInk), style: StrokeStyle(lineWidth: 2, dash: [4, 5]))
        var tick = Path()
        tick.move(to: CGPoint(x: now, y: y - 22))
        tick.addLine(to: CGPoint(x: now, y: y + 14))
        context.stroke(tick, with: .color(Palette.ink), lineWidth: 1.5)

        for milestone in reached {
            dot(in: &context, at: CGPoint(x: x(milestone.date, width: width), y: y), radius: 4.5, filled: true)
        }
        for milestone in drawnAhead {
            let isNext = milestone.id == next?.id
            dot(in: &context, at: CGPoint(x: x(milestone.date, width: width), y: y), radius: isNext ? 6.5 : 4.5,
                filled: false)
        }
        if let next {
            let nx = x(next.date, width: width)
            var pointer = Path()
            pointer.move(to: CGPoint(x: nx, y: y + 8))
            pointer.addLine(to: CGPoint(x: nx, y: y + 20))
            context.stroke(pointer, with: .color(Palette.accent), lineWidth: 1.5)
        }
        if retirement != nil {
            var pole = Path()
            pole.move(to: CGPoint(x: right, y: y))
            pole.addLine(to: CGPoint(x: right, y: y - 22))
            context.stroke(pole, with: .color(Palette.ink), lineWidth: 1.5)
            var flag = Path()
            flag.move(to: CGPoint(x: right, y: y - 22))
            flag.addLine(to: CGPoint(x: right - 11, y: y - 18))
            flag.addLine(to: CGPoint(x: right, y: y - 14))
            flag.closeSubpath()
            context.fill(flag, with: .color(Palette.ink))
            context.fill(Path(ellipseIn: CGRect(x: right - 5.5, y: y - 5.5, width: 11, height: 11)),
                         with: .color(Palette.ink))
        }
    }

    private func dot(in context: inout GraphicsContext, at point: CGPoint, radius: CGFloat, filled: Bool) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        let circle = Path(ellipseIn: rect)
        if filled {
            context.fill(circle, with: .color(Palette.accent))
            context.stroke(circle, with: .color(Palette.card), lineWidth: 2)
        } else {
            context.fill(circle, with: .color(Palette.card))
            context.stroke(circle, with: .color(Palette.accent), lineWidth: 2)
        }
    }

    @ViewBuilder
    private func labels(width: CGFloat) -> some View {
        let now = x(today, width: width)
        let right = x(end, width: width)
        let row = MilestoneTrackLabels(width: width, start: Self.inset, now: now,
                                       flag: retirement == nil ? nil : right,
                                       hasReached: !reached.isEmpty, widths: labelWidths)
        if !reached.isEmpty {
            // Both forms are laid out, so both are measured; one is shown.
            caption(Wording.count(reached.count, "milestone") + " reached")
                .measuringWidth($labelWidths.reached)
                .position(x: (row.reached ?? 0) + labelWidths.reached / 2, y: 24)
                .opacity(row.reached != nil && !row.reachedIsShort ? 1 : 0)
            caption("\(reached.count) reached")
                .measuringWidth($labelWidths.reachedShort)
                .position(x: (row.reached ?? 0) + labelWidths.reachedShort / 2, y: 24)
                .opacity(row.reached != nil && row.reachedIsShort ? 1 : 0)
        }
        mark("Today")
            .measuringWidth($labelWidths.today)
            .position(x: row.today + labelWidths.today / 2, y: 24)
        if retirement != nil {
            mark("Last Monday")
                .measuringWidth($labelWidths.lastMonday)
                .position(x: (row.lastMonday ?? 0) + labelWidths.lastMonday / 2, y: 24)
                .opacity(row.lastMonday == nil ? 0 : 1)
        }
        if let next {
            let nx = min(max(x(next.date, width: width), 70), width - 70)
            VStack(spacing: 1) {
                AmountSentenceText(next.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                caption(PlanMilestoneText.when(next.date))
            }
            .fixedSize()
            .position(x: nx, y: 100)
        }
        caption(String(start.year))
            .position(x: Self.inset + 14, y: 100)
            .opacity(next.map { x($0.date, width: width) < 110 } == true ? 0 : 1)
        caption(String(end.year))
            .position(x: right - 14, y: 100)
            .opacity(next.map { x($0.date, width: width) > width - 110 } == true ? 0 : 1)
    }

    /// "Today" and "Last Monday" above the line.
    private func mark(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.ink)
            .fixedSize()
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(Palette.secondaryInk)
            .fixedSize()
    }

    /// "Your milestones from October 2021 to your last Monday in 2042: 7
    /// reached so far, the next is 5 years of spending, typically by late 2028."
    private var summary: String {
        var text = "Your milestones from \(GlanceText.monthAndYear(start, locale: locale))"
        if let retirement { text += " to your last Monday in \(retirement.year)" }
        text += ": \(Wording.count(reached.count, "milestone")) reached so far"
        if let next {
            text += ", the next is \(next.name.spoken(hidesAmounts: true)), typically by "
                + PlanMilestoneText.when(next.date)
        }
        return text + "."
    }
}
