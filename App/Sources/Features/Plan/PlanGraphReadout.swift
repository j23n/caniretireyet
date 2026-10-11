import SwiftUI
#if os(iOS)
import UIKit
#endif

// Reading the strips' graphs at a point (UI.md, "Plan" and "Progress"): on
// the Mac and an iPad with a pointer, wherever the pointer is over a card;
// on iPhone, touch and hold a card, then drag, until the finger lifts. A
// rule marks the point, and a callout like the net-worth chart's says what
// the graph shows there (``PlanGraphCallout``).
// A click or a tap still chooses the card, and a swipe scrolls the strip.

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
/// hold, then a drag (``PlanTouchAndHold``), alongside the card's own tap.
/// The read-out goes when the finger lifts or the touch is cancelled.
struct PlanGraphPointerModifier: ViewModifier {
    @Binding var pointer: PlanGraphPointer?
    let index: Int

    #if os(iOS)
    /// Whether a finger is held on the card, for the tap felt when it starts.
    @State private var isHeld = false
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
            .gesture(PlanTouchAndHold { x in
                isHeld = x != nil
                if let x {
                    let moved = PlanGraphPointer(index: index, x: x.rounded(), byTouch: true)
                    if pointer != moved { pointer = moved }
                } else if pointer?.index == index, pointer?.byTouch == true {
                    pointer = nil
                }
            })
            .sensoryFeedback(.impact(weight: .light), trigger: isHeld) { old, new in !old && new }
            #endif
    }
}

#if os(iOS)
/// Touch and hold, then drag: UIKit's long press, whose place along the view
/// `onChange` follows while the finger is held, then `nil` once it lifts or
/// the touch is cancelled.
///
/// Not SwiftUI's `LongPressGesture` sequenced before a `DragGesture`: inside
/// a scroll view, that drag kept the strip from scrolling at all. A swipe
/// moves the finger before the press is long enough, so the long press fails
/// and the strip's own pan scrolls it; once the long press begins, the pan
/// can't, and the strip stays put while the finger reads the graph.
struct PlanTouchAndHold: UIGestureRecognizerRepresentable {
    var minimumDuration: TimeInterval = 0.3
    let onChange: @MainActor (CGFloat?) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(context.converter.localLocation.x)
        default:
            onChange(nil)
        }
    }
}
#endif

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

/// Where the label over a card's graph at the pointer goes: a chart's
/// callout (``ChartCallout``), as the net-worth chart has it, as wide as
/// that one or the card less its margins, centred on the pointer and kept
/// inside the card.
enum PlanGraphCallout {
    /// The room it keeps from the card's edges.
    static let margin: CGFloat = 6

    /// Its width on a card `total` wide.
    static func width(in total: CGFloat) -> CGFloat {
        max(0, min(ChartStyle.calloutWidth, total - 2 * margin))
    }

    /// Where it starts at `x` on a card `total` wide: centred on it, kept
    /// inside the card.
    static func leading(at x: CGFloat, in total: CGFloat) -> CGFloat {
        let callout = width(in: total)
        return min(max(margin, x - callout / 2), max(margin, total - callout - margin))
    }
}

/// A milestone's flag in a read-out, in the accent, as on the graph.
struct PlanGraphFlag: View {
    var body: some View {
        Image(systemName: "flag.fill")
            .foregroundStyle(Palette.accent)
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
