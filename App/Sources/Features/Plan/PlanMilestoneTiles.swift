import Glance
import Model
import Planner
import SwiftUI
import Tracker

// Milestones as tiles (UI.md, "Milestones" and "Tiles"): the coast age,
// and each kind of milestone in *All Milestones*. The next milestone's
// tile is Today's (``MilestoneTile``).

extension MilestoneTileContent {
    /// The milestones as their tile shows them, at the library's latest
    /// check-in: those passed since the check-in before, else the next.
    @MainActor
    init(_ milestones: PlanMilestones, hasResults: Bool, library: LibraryStore) {
        let valuator = library.valuator
        let latest = library.latestCheckIn
        let previous = latest.flatMap { valuator.previousCheckIn(before: $0, in: .planAssets) }
        self.init(milestones, hasResults: hasResults, latestCheckIn: latest, previousCheckIn: previous,
                  assetsBefore: previous.map { valuator.total(on: $0, in: .planAssets).total })
    }
}

extension PlanMilestoneKind {
    /// Its tiles' tint, as its milestones' (``Milestone/tileTint``).
    var tileTint: TileTint {
        switch self {
        case .roundAmount: .butter
        case .yearsOfSpending: .mint
        case .shareOfNeeded: .lilac
        case .crossover: .peach
        case .coastPoint: .sky
        }
    }

    /// Its emoji, as its milestones' (``Milestone/tileEmoji``).
    var tileEmoji: String {
        switch self {
        case .roundAmount: "💰"
        case .yearsOfSpending: "🛋️"
        case .shareOfNeeded: "🧩"
        case .crossover: "⚖️"
        case .coastPoint: "⛵"
        }
    }
}

/// When you could still retire saving nothing more, as a tile (UI.md,
/// "Milestones"): ⛵ and the coast age large, mint once it's at or under
/// the coast point, else sky. The small tile names the coast point under
/// it; the wide one says it in full.
struct CoastAgeTile: View {
    let age: Int?
    var target: Int?
    var size: TileSize = .small

    @ScaledMetric(relativeTo: .largeTitle) private var ageSize: CGFloat = 44

    private var isPastCoastPoint: Bool {
        guard let age, let target else { return false }
        return age <= target
    }

    var body: some View {
        ColorTile(tint: isPastCoastPoint ? .mint : .sky) {
            TileLabel("Saving nothing more", emoji: "⛵")
            Spacer(minLength: Metrics.s)
            Group {
                if let age {
                    Text(verbatim: "\(age)")
                        .font(.system(size: ageSize, weight: .bold))
                        .monospacedDigit()
                } else {
                    Text("No age yet")
                        .font(.title3.bold())
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .privacySensitiveInFeedback()
            Text(verbatim: caption)
                .font(.caption)
                .opacity(0.85)
                .lineLimit(size == .wide ? 3 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
                .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }

    /// "The coast point is 67.", "Past the coast point, 67."; on a wide
    /// tile the sentence in full (``PlanMilestoneText/coast(_:target:)``).
    private var caption: String {
        if size == .wide { return PlanMilestoneText.coast(age, target: target) }
        guard age != nil else { return "If you stopped saving today." }
        guard let target else { return "The age you could still retire at." }
        return isPastCoastPoint ? "Past the coast point, \(target)." : "The coast point is \(target)."
    }
}

/// A kind of milestone as a wide tile in *All Milestones* (UI.md, "What
/// they mean"): in its tint, with its emoji and name, what it means, then
/// the latest of it reached and the soonest ahead.
struct MilestoneKindTile: View {
    let kind: PlanMilestoneKind
    let milestones: PlanMilestones
    let text: PlanMilestoneText
    /// Whether the plan has results: without them nothing is ahead yet.
    var hasResults = true

    @Environment(\.locale) private var locale

    var body: some View {
        ColorTile(tint: kind.tileTint) {
            TileLabel(PlanMilestoneText.title(kind), emoji: kind.tileEmoji)
                .accessibilityAddTraits(.isHeader)
            AmountSentenceText(text.meaning(of: kind, in: milestones))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Metrics.s)
            Spacer(minLength: Metrics.m)
            VStack(alignment: .leading, spacing: Metrics.xs) {
                if let reached = milestones.latestReached(kind) {
                    line(text.name(reached.milestone), when: GlanceText.shortMonthAndYear(reached.date, locale: locale),
                         isReached: true)
                } else {
                    Text("None yet.")
                        .font(.subheadline)
                        .opacity(0.8)
                }
                if let ahead = milestones.soonestAhead(kind) {
                    line(text.name(ahead.milestone), when: PlanMilestoneText.when(ahead.date), isReached: false)
                } else if hasResults && kind != .coastPoint {
                    Text("No more before the plan's end.")
                        .font(.subheadline)
                        .opacity(0.8)
                }
            }
        }
    }

    /// A milestone on the tile: a flag (filled once reached), its name and when.
    private func line(_ name: AmountSentence, when: String, isReached: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Image(systemName: isReached ? "flag.fill" : "flag")
                .font(.caption)
                .foregroundStyle(.tint)
                .accessibilityLabel(isReached ? "Reached" : "Ahead")
            AmountSentenceText(name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: Metrics.s)
            Text(verbatim: isReached ? when : "typically \(when)")
                .font(.subheadline)
                .monospacedDigit()
                .opacity(0.8)
                .lineLimit(1)
                .privacySensitiveInFeedback()
        }
        .accessibilityElement(children: .combine)
    }
}
