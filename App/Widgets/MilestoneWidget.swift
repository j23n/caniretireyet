import Glance
import Model
import SwiftUI
import WidgetKit

// The main plan's next milestone (UI.md, "Widgets" and "Milestones"): what
// it is, how far there, and when it typically comes. It opens the plan.

struct MilestoneWidget: Widget {
    static let kind = "NextMilestone"

    var body: some WidgetConfiguration {
        glance(kind: Self.kind, name: "Next milestone",
               description: "The next point on the way to retiring, and how far there you are.",
               families: [.small, .rectangular], link: .plan) { entry, family in
            if family == .rectangular {
                MilestoneRectangular(entry: entry)
            } else {
                MilestoneSmall(entry: entry)
            }
        }
    }
}

/// The milestone in words: its name, "88% there", "Typically by mid 2027".
struct MilestoneWords {
    var milestone: MilestoneGlance
    var money: WidgetMoney

    /// "300.000 €", an amount that hides while the device is locked, or
    /// "10 years of spending".
    var name: AmountSentence {
        var amount: String?
        let name = GlanceText.milestoneName(milestone, amount: { value in
            amount = money.amount(value)
            return amount
        })
        return amount.map { AmountSentence.amount($0) } ?? AmountSentence(name)
    }

    /// The name without an amount, for the lock screen: "A round amount".
    var nameWithoutAmount: String {
        GlanceText.milestoneName(milestone, amount: { _ in nil })
    }

    var progress: Double { min(max(milestone.progress, 0), 1) }

    var there: String { money.percent(progress) + " there" }

    var typically: String? { milestone.typically.map(GlanceText.typically) }
}

struct MilestoneSmall: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let milestone = snapshot.milestone {
                content(MilestoneWords(milestone: milestone,
                                       money: WidgetMoney(currency: snapshot.currency, locale: locale)))
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
            WidgetLabel(title: "Next milestone", systemImage: "flag", iconColor: Palette.accent)
            Spacer(minLength: 0)
            AmountSentenceText(words.name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            WidgetProgressBar(fraction: words.progress, height: 6)
                .accessibilityHidden(true)
            Text(words.there)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.accent)
            if let typically = words.typically {
                Text(typically)
                    .font(.caption2)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// The next milestone on the lock screen: its name and how far there. Lock
/// screen widgets never show amounts, so a round amount reads "A round amount".
struct MilestoneRectangular: View {
    var entry: GlanceEntry
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, let milestone = snapshot.milestone {
                let words = MilestoneWords(milestone: milestone,
                                           money: WidgetMoney(currency: snapshot.currency, locale: locale))
                VStack(alignment: .leading, spacing: 2) {
                    Label("Next milestone", systemImage: "flag")
                        .font(.caption2.weight(.semibold))
                    Text(words.nameWithoutAmount)
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
