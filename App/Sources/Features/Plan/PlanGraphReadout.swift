import SwiftUI

// Reading the strips' graphs at a point (UI.md, "Plan" and "Progress"): on
// the Mac and an iPad with a pointer, wherever the pointer is over a card;
// on iPhone, touch and hold a card, then drag, until the finger lifts. A
// rule marks the point, and a small label says what the graph shows there.
// A click or a tap still chooses the card.

/// Where the pointer is over one of a strip's cards, or the finger on one:
/// the card's index and the point along it, in its coordinates.
struct PlanGraphPointer: Equatable {
    var index: Int
    var x: CGFloat
    /// A finger, touched and held: the strip doesn't scroll until it lifts.
    var byTouch = false
}

extension View {
    /// Follows the pointer over a strip's card, or a finger touched and
    /// held on it, into `pointer`.
    func planGraphPointer(_ pointer: Binding<PlanGraphPointer?>, index: Int) -> some View {
        modifier(PlanGraphPointerModifier(pointer: pointer, index: index))
    }
}

/// The pointer over a card (`onContinuousHover`), and on iOS a touch and
/// hold, then a drag: a long press sequenced before a drag, alongside the
/// card's own tap. The finger's place is gesture state, so it's gone when
/// the finger lifts or the touch is cancelled, and the read-out with it.
struct PlanGraphPointerModifier: ViewModifier {
    @Binding var pointer: PlanGraphPointer?
    let index: Int

    #if os(iOS)
    /// Where the finger is along the card while it's touched and held.
    @GestureState private var finger: CGFloat?
    #endif

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    // Only a move redraws the card.
                    let moved = PlanGraphPointer(index: index, x: location.x.rounded())
                    if pointer != moved { pointer = moved }
                } else if pointer?.index == index, pointer?.byTouch != true {
                    pointer = nil
                }
            }
            #if os(iOS)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .updating($finger) { value, state, _ in
                        if case .second(true, let drag?) = value { state = drag.location.x }
                    }
            )
            .onChange(of: finger) { _, x in
                if let x {
                    pointer = PlanGraphPointer(index: index, x: x, byTouch: true)
                } else if pointer?.index == index, pointer?.byTouch == true {
                    pointer = nil
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: finger != nil) { old, new in !old && new }
            #endif
    }
}

extension DynamicTypeSize {
    /// The largest text size a strip's cards show (``stripCardScale``):
    /// their words sit in fixed places on the graph, so past it they stop
    /// growing; the chosen chapter's or year's details below, and VoiceOver,
    /// carry them at any size.
    static let stripCardLimit = DynamicTypeSize.xxxLarge

    /// How much a strip card's words, and the room above and below its
    /// graph, grow at this text size, up to ``stripCardLimit``.
    var stripCardScale: CGFloat {
        switch min(self, Self.stripCardLimit) {
        case .xSmall: 0.85
        case .small: 0.9
        case .medium: 0.95
        case .large: 1
        case .xLarge: 1.1
        case .xxLarge: 1.2
        default: 1.3
        }
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
