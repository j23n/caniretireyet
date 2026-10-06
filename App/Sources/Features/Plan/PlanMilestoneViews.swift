import Model
import Planner
import SwiftUI

// Milestones on screen (UI.md, "Milestones"): a flag on a line where one
// was reached or is reached ahead, the next one with how far there, and the
// list of those reached and ahead. Calm: no badges, confetti or streaks.

/// A small pennant on a line: filled where a check-in reached a milestone,
/// outlined where the median future reaches one.
enum PlanMilestoneFlag {
    /// A pennant whose pole stands on `point`.
    static func path(at point: CGPoint) -> Path {
        var path = Path()
        path.addRect(CGRect(x: point.x - 0.75, y: point.y - 14, width: 1.5, height: 14))
        path.move(to: CGPoint(x: point.x + 0.75, y: point.y - 14))
        path.addLine(to: CGPoint(x: point.x + 9, y: point.y - 10.5))
        path.addLine(to: CGPoint(x: point.x + 0.75, y: point.y - 7))
        path.closeSubpath()
        return path
    }
}

/// The next milestone: its name, how far there as a bar, and when the
/// median future typically reaches it.
struct PlanNextMilestoneView: View {
    let next: NextMilestone
    var date: CalendarDate?
    let text: PlanMilestoneText

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Label("Next milestone", systemImage: "flag")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: Metrics.s)
                Text(text.progress(next))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.accent)
            }
            Text(text.name(next.milestone))
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            PlanMilestoneBar(progress: next.progress)
            if let detail = text.detail(next.milestone) {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let date {
                Text("Typically by \(PlanMilestoneText.when(date)).")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The coast age: when you could still retire if you stopped saving today,
/// against the coast point (UI.md, "Milestones").
struct PlanCoastAgeView: View {
    let age: Int?
    var target: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Label("Saving nothing more", systemImage: "pause.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: Metrics.s)
                if let age {
                    Text(verbatim: "\(age)")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(target.map { age <= $0 } == true ? Palette.positive : Palette.ink)
                }
            }
            Text(PlanMilestoneText.coast(age, target: target))
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// How far to the next milestone, as a thin bar.
struct PlanMilestoneBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.gridline)
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, progress))))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// The milestones (UI.md, "Milestones"): the next with how far there, then
/// those reached, newest first, and those ahead, soonest first; side by
/// side on the Mac.
struct PlanMilestonesCard: View {
    let milestones: PlanMilestones
    let text: PlanMilestoneText
    var isWide = false
    /// Whether the plan has results: without them nothing is ahead yet.
    var hasResults = true

    @Environment(\.locale) private var locale
    @State private var showsAllReached = false
    @State private var showsAllAhead = false

    private static let shown = 5

    var body: some View {
        Card {
            if let next = milestones.next {
                PlanNextMilestoneView(next: next, date: milestones.nextDate, text: text)
                Divider()
            }
            if milestones.knowsCoastAge {
                PlanCoastAgeView(age: milestones.coastAge, target: milestones.ladder.coastTarget)
                Divider()
            }
            if isWide {
                HStack(alignment: .top, spacing: Metrics.xl) {
                    reachedList
                        .frame(maxWidth: .infinity, alignment: .leading)
                    aheadList
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                reachedList
                aheadList
            }
        } header: {
            SectionHeader("Milestones")
        }
    }

    private var reachedList: some View {
        let reached = Array(milestones.reached.reversed())
        let shown = showsAllReached ? reached : Array(reached.prefix(Self.shown))
        let more: String = showsAllReached ? "Show Fewer" : "Show All \(reached.count)"
        return VStack(alignment: .leading, spacing: Metrics.s) {
            Text("Reached")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            if reached.isEmpty {
                Text("None yet since your first check-in. The next one shows above.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(shown) { item in
                PlanMilestoneRow(title: text.name(item.milestone),
                                 when: PlanResultsText.shortMonthYear(item.date, locale: locale), isReached: true)
            }
            if reached.count > Self.shown {
                Button(more) { showsAllReached.toggle() }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }
        }
    }

    private var aheadList: some View {
        let ahead = milestones.ahead
        let shown = showsAllAhead ? ahead : Array(ahead.prefix(Self.shown))
        let more: String = showsAllAhead ? "Show Fewer" : "Show All \(ahead.count)"
        return VStack(alignment: .leading, spacing: Metrics.s) {
            Text("Ahead, typically")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityAddTraits(.isHeader)
            if ahead.isEmpty {
                Text(hasResults ? "No more before the plan's end in its median future."
                                : "Calculate the plan to see when the rest typically come.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(shown) { item in
                PlanMilestoneRow(title: text.name(item.milestone), when: PlanMilestoneText.when(item.date),
                                 isReached: false)
            }
            if ahead.count > Self.shown {
                Button(more) { showsAllAhead.toggle() }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }
        }
    }
}

/// A milestone in a list: a flag (filled once reached), its name, and when.
struct PlanMilestoneRow: View {
    let title: String
    let when: String
    let isReached: Bool

    var body: some View {
        let label: String = isReached ? "\(title), reached \(when)" : "\(title), typically \(when)"
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Image(systemName: isReached ? "flag.fill" : "flag")
                .font(.caption)
                .foregroundStyle(isReached ? Palette.accent : Palette.secondaryInk)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Metrics.s)
            Text(when)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
    }
}
