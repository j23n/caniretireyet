import SwiftUI

// Reading the strips' graphs at a point (UI.md, "Plan" and "Progress"): on
// the Mac and an iPad with a pointer, wherever the pointer is over a card;
// on iPhone, where a card was tapped, until it's tapped there again. A rule
// marks the point, and a small label says what the graph shows there.

/// Where the pointer is over one of a strip's cards, or where one was
/// tapped: the card's index and the point along it, in its coordinates.
struct PlanGraphPointer: Equatable {
    var index: Int
    var x: CGFloat
    /// Set by a tap: a second tap there puts it away.
    var byTouch = false

    /// After a tap at `x` on the card at `index`: the read-out there, or
    /// none when the tap lands where a tapped one already is.
    static func tapped(at x: CGFloat, on index: Int, current: PlanGraphPointer?) -> PlanGraphPointer? {
        if let current, current.byTouch, current.index == index, abs(current.x - x) < 12 { return nil }
        return PlanGraphPointer(index: index, x: x, byTouch: true)
    }
}

extension View {
    /// Follows the pointer over a strip's card, and a tap on it, into
    /// `pointer`. A tap still chooses the card.
    func planGraphPointer(_ pointer: Binding<PlanGraphPointer?>, index: Int) -> some View {
        onContinuousHover { phase in
            if case .active(let location) = phase {
                pointer.wrappedValue = PlanGraphPointer(index: index, x: location.x)
            } else if pointer.wrappedValue?.index == index {
                pointer.wrappedValue = nil
            }
        }
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            pointer.wrappedValue = PlanGraphPointer.tapped(at: value.location.x, on: index,
                                                           current: pointer.wrappedValue)
        })
    }
}

/// The label over a graph at the pointer: what the point is (an age and a
/// year, a date), a milestone or an event there, and the money.
struct PlanGraphCallout: View {
    struct Line: Hashable {
        enum Style: Hashable {
            /// "48 · 2034", "31 Mar 2026".
            case context
            /// A milestone, with its flag.
            case milestone
            /// What happens there: "New car, 25.000 €".
            case title
            /// The money: "Typically 640.000 €".
            case value
            /// "Bad 410k €, good 980k €".
            case detail
        }

        var text: String
        var style: Style
    }

    let lines: [Line]

    static let width: CGFloat = 160

    /// Where a label at `x` starts on a card `total` wide: centred on it,
    /// kept inside the card.
    static func leading(at x: CGFloat, in total: CGFloat) -> CGFloat {
        min(max(6, x - width / 2), max(6, total - width - 6))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                text(line)
                    .lineLimit(line.style == .milestone || line.style == .title ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: Self.width, alignment: .leading)
        .background(Palette.card, in: shape)
        .overlay { shape.strokeBorder(Palette.border, lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    @ViewBuilder
    private func text(_ line: Line) -> some View {
        switch line.style {
        case .context:
            Text(line.text)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
        case .milestone:
            Label(line.text, systemImage: "flag.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.accent)
        case .title:
            Text(line.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.ink)
        case .value:
            Text(line.text)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
        case .detail:
            Text(line.text)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
        }
    }
}

/// The rule at the pointer, down the plot.
struct PlanGraphRule: View {
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(Palette.secondaryInk.opacity(0.5))
            .frame(width: 1, height: height)
    }
}

/// A dot on a line at the pointer.
struct PlanGraphDot: View {
    var color: Color = Palette.accent

    var body: some View {
        Circle()
            .fill(color)
            .overlay { Circle().strokeBorder(Palette.card, lineWidth: 1.5) }
            .frame(width: 9, height: 9)
    }
}
