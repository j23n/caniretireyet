import Glance
import Model
import Planner
import SwiftUI

// Milestones on screen (UI.md, "Milestones"): a flag on a line where one
// was reached or is reached ahead, tiles for the next one and the coast
// age, and the list of those reached and ahead. A little color and an
// emoji for each kind; no badges, confetti or streaks.

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

/// *All Milestones* (UI.md, "Milestones"), as wide tiles (``TileGrid``):
/// the next milestone, or those passed at the latest check-in
/// (``MilestoneTile``), and saving nothing more (``CoastAgeTile``); *What
/// they mean*, a tile for each kind the plan has (``MilestoneKindTile``);
/// then those reached, newest first, and those ahead, soonest first, as
/// rows on a card.
struct PlanAllMilestones: View {
    let milestones: PlanMilestones
    let text: PlanMilestoneText
    let planName: String
    let asOf: CalendarDate
    /// Whether the plan has results: without them nothing is ahead yet.
    var hasResults = true

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @State private var showsAllReached = false
    @State private var showsAllAhead = false

    private static let shown = 5

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            TileGrid {
                MilestoneTile(content: MilestoneTileContent(milestones, hasResults: hasResults, library: library),
                              size: .wide, planName: planName, today: asOf)
                    .tileSize(.wide)
                if milestones.knowsCoastAge {
                    CoastAgeTile(age: milestones.coastAge, target: milestones.ladder.coastTarget, size: .wide)
                        .tileSize(.wide)
                }
            }
            VStack(alignment: .leading, spacing: Metrics.s) {
                SectionHeader("What they mean")
                TileGrid {
                    ForEach(milestones.kinds, id: \.self) { kind in
                        MilestoneKindTile(kind: kind, milestones: milestones, text: text, hasResults: hasResults)
                            .tileSize(.wide)
                    }
                }
            }
            Card("Reached") {
                reachedList
            }
            Card("Ahead, typically") {
                aheadList
            }
        }
    }

    private var reachedList: some View {
        let reached = Array(milestones.reached.reversed())
        let shown = showsAllReached ? reached : Array(reached.prefix(Self.shown))
        let more: String = showsAllReached ? "Show Fewer" : "Show All \(reached.count)"
        return VStack(alignment: .leading, spacing: Metrics.s) {
            if reached.isEmpty {
                Text("None yet since your first check-in. The next one shows above.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(shown) { item in
                PlanMilestoneRow(title: text.name(item.milestone),
                                 when: GlanceText.shortMonthAndYear(item.date, locale: locale), isReached: true,
                                 emoji: item.milestone.tileEmoji)
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
            if ahead.isEmpty {
                Text(hasResults ? "No more before the plan's end in its median future."
                                : "Calculate the plan to see when the rest typically come.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(shown) { item in
                PlanMilestoneRow(title: text.name(item.milestone), when: PlanMilestoneText.when(item.date),
                                 isReached: false, emoji: item.milestone.tileEmoji)
            }
            if ahead.count > Self.shown {
                Button(more) { showsAllAhead.toggle() }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
            }
        }
    }
}

/// A milestone in a list: its kind's emoji, else a flag (filled once
/// reached), its name, and when.
struct PlanMilestoneRow: View {
    let title: AmountSentence
    let when: String
    let isReached: Bool
    var emoji: String?

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        let name = title.spoken(hidesAmounts: redactionReasons.hidesAmounts)
        let label: String = isReached ? "\(name), reached \(when)" : "\(name), typically \(when)"
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Group {
                if let emoji {
                    Text(verbatim: emoji)
                        .font(.subheadline)
                } else {
                    Image(systemName: isReached ? "flag.fill" : "flag")
                        .font(.caption)
                        .foregroundStyle(isReached ? Palette.accent : Palette.secondaryInk)
                }
            }
            .accessibilityHidden(true)
            AmountSentenceText(title)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Metrics.s)
            Text(when)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
    }
}
