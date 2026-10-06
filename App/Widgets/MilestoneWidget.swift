import Glance
import Model
import SwiftUI
import WidgetKit

// The main plan's next milestone (UI.md, "Widgets" and "Milestones"): what
// it is, how far there, and when it typically comes. It opens the plan.

struct MilestoneWidget: Widget {
    static let kind = "NextMilestone"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: GlanceProvider()) { entry in
            MilestoneView(entry: entry)
        }
        .configurationDisplayName("Next milestone")
        .description("The next point on the way to retiring, and how far there you are.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .accessoryRectangular]
        #else
        return [.systemSmall]
        #endif
    }
}

/// The milestone in words: its name, "88% there", "Typically by mid 2027".
struct MilestoneWords {
    var milestone: MilestoneGlance
    var money: WidgetMoney
    var hidesAmounts: Bool

    var name: String {
        GlanceText.milestoneName(milestone, amount: { hidesAmounts ? nil : money.amount($0) })
    }

    var progress: Double { min(max(milestone.progress, 0), 1) }

    var there: String { money.percent(progress) + " there" }

    var typically: String? { milestone.typically.map(GlanceText.typically) }
}

struct MilestoneView: View {
    var entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(GlanceLink.plan.url)
    }

    @ViewBuilder
    private var content: some View {
        #if os(iOS)
        if family == .accessoryRectangular {
            MilestoneRectangular(entry: entry)
        } else {
            MilestoneSmall(entry: entry)
        }
        #else
        MilestoneSmall(entry: entry)
        #endif
    }
}

struct MilestoneSmall: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let milestone = snapshot.milestone {
                content(MilestoneWords(milestone: milestone,
                                       money: WidgetMoney(currency: snapshot.currency, locale: locale),
                                       hidesAmounts: redactionReasons.hidesAmounts))
            } else {
                WidgetMessage(title: "Next milestone", systemImage: "flag",
                              message: entry.snapshot == nil ? WidgetEmpty.noSnapshot
                                  : "Your next milestone appears here after your first check-in.")
            }
        }
        .cardBackground()
    }

    private func content(_ words: MilestoneWords) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetLabel(title: "Next milestone", systemImage: "flag", iconColor: WidgetPalette.accent)
            Spacer(minLength: 0)
            Text(words.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WidgetPalette.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .privacySensitive(!words.hidesAmounts)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(WidgetPalette.track)
                    Capsule()
                        .fill(WidgetPalette.accent)
                        .frame(width: proxy.size.width * words.progress)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            Text(words.there)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetPalette.accent)
            if let typically = words.typically {
                Text(typically)
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

#if os(iOS)
/// The next milestone on the lock screen: its name and how far there. Lock
/// screen widgets never show amounts, so a round amount reads "A round amount".
struct MilestoneRectangular: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let milestone = snapshot.milestone {
                let words = MilestoneWords(milestone: milestone,
                                           money: WidgetMoney(currency: snapshot.currency, locale: locale),
                                           hidesAmounts: true)
                VStack(alignment: .leading, spacing: 2) {
                    Label("Next milestone", systemImage: "flag")
                        .font(.caption2.weight(.semibold))
                    Text(words.name)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Gauge(value: words.progress) {
                        Text(words.there)
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                }
                .widgetAccentable()
            } else {
                Label("Next milestone", systemImage: "flag")
                    .font(.headline)
            }
        }
        .clearBackground()
    }
}
#endif
