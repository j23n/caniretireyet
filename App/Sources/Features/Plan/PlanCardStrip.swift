import Model
import SwiftUI

// What the plan's chapters and Progress's years share (UI.md, "Plan" and
// "Progress"): a strip of cards that scrolls sideways, each card's graph on
// the money scale the cards on screen share, and the parts of the graph
// both draw alike.

// MARK: - The strip

/// Cards side by side on a strip that scrolls sideways. The cards on screen
/// share one money scale fitted to their money (``PlanStripScale``): at once
/// the first time, then whenever the strip comes to rest after scrolling,
/// the graphs fading to their new places, and when a card is chosen, to
/// those on screen once it's scrolled to the middle. Choosing a card selects it,
/// outlined in the accent; selecting one elsewhere scrolls it to the middle.
/// The pointer over a card's graph, or a finger touched and held on it,
/// reads the graph there (``PlanGraphPointer``), and the strip stays put
/// until the finger lifts.
struct PlanCardStrip<Leading: View, Graph: View, Footer: View>: View {
    /// The cards laid out, by index, in order.
    let indices: [Int]
    /// The index of the selected card.
    @Binding var selection: Int
    /// The strip's inset at both ends, so its cards line up with the page.
    let inset: CGFloat
    /// Whether it opens at its last card (today's year) rather than its first.
    let opensAtEnd: Bool
    /// The strip's accessibility identifier, for the UI tests.
    let identifier: String
    /// The money scale fitted to the cards at the indices given, of those
    /// there are.
    let scale: (Set<Int>) -> PlanStripScale?
    /// What VoiceOver reads for a card.
    let spokenLabel: (Int) -> String
    /// A card's audio graph and chart details.
    let chart: (Int) -> ChartSummary
    /// Before the cards: the years folded into one card.
    let leading: () -> Leading
    /// A card's graph on the scale, with the read-out at the pointer, if
    /// it's over the card: choosing it selects the card.
    let graph: (_ index: Int, _ scale: PlanStripScale?, _ pointerX: CGFloat?) -> Graph
    /// Under a card's graph: a year's figures, on the Mac and iPad.
    let footer: (Int) -> Footer

    /// Where the pointer is over a card, or where one was tapped.
    @State private var pointer: PlanGraphPointer?
    /// The cards the money scale is fitted to: those on screen when the
    /// strip last came to rest, or once the chosen card is in the middle;
    /// the chosen one and those beside it before the strip has said where
    /// its cards are.
    @State private var fitted: Set<Int> = []
    @State private var onScreen = PlanCardsOnScreen()

    init(indices: [Int], selection: Binding<Int>, inset: CGFloat, opensAtEnd: Bool = false, identifier: String,
         scale: @escaping (Set<Int>) -> PlanStripScale?, spokenLabel: @escaping (Int) -> String,
         chart: @escaping (Int) -> ChartSummary, @ViewBuilder leading: @escaping () -> Leading,
         @ViewBuilder graph: @escaping (_ index: Int, _ scale: PlanStripScale?, _ pointerX: CGFloat?) -> Graph,
         @ViewBuilder footer: @escaping (Int) -> Footer) {
        self.indices = indices
        _selection = selection
        self.inset = inset
        self.opensAtEnd = opensAtEnd
        self.identifier = identifier
        self.scale = scale
        self.spokenLabel = spokenLabel
        self.chart = chart
        self.leading = leading
        self.graph = graph
        self.footer = footer
    }

    /// A card's id, which the strip scrolls to: a type of its own, as a
    /// plain number would also be the id of something inside a card (a
    /// month's initial, an age), and the strip scrolled to that instead.
    private struct CardID: Hashable {
        let index: Int
    }

    var body: some View {
        let shared = scale(fitted.isEmpty ? [selection - 1, selection, selection + 1] : fitted)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Metrics.s) {
                    leading()
                    ForEach(indices, id: \.self) { index in
                        card(index, scale: shared)
                            .id(CardID(index: index))
                            .onGeometryChange(for: CGRect.self) { geometry in
                                geometry.frame(in: .named(stripContent))
                            } action: { frame in
                                onScreen.frames[index] = frame
                                if !onScreen.isScrolling { fitScale() }
                            }
                    }
                }
                .padding(.horizontal, inset)
                .padding(.vertical, 2)
                .dynamicTypeSize(...DynamicTypeSize.stripCardLimit)
                .coordinateSpace(.named(stripContent))
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(opensAtEnd ? .trailing : nil)
            // A finger reading a graph moves the read-out, not the strip.
            .scrollDisabled(pointer?.byTouch == true)
            .onScrollGeometryChange(for: PlanStripViewport.self) { geometry in
                PlanStripViewport(geometry)
            } action: { _, viewport in
                onScreen.viewport = viewport
                if !onScreen.isScrolling { fitScale() }
            }
            .onScrollPhaseChange { _, phase in
                onScreen.isScrolling = phase != .idle
                if phase == .idle { fitScale() }
            }
            .accessibilityIdentifier(identifier)
            .onChange(of: selection) { _, index in
                // The strip centres the chosen card: the scale is fitted at
                // once to the cards on screen once it's there.
                fitScale(to: onScreen.cards(among: indices, centring: index))
                withAnimation(.snappy) { proxy.scrollTo(CardID(index: index), anchor: .center) }
            }
        }
    }

    /// A card: its graph, which chooses it, and what goes under it.
    private func card(_ index: Int, scale: PlanStripScale?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let isSelected = selection == index
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                selection = index
            } label: {
                graph(index, scale, pointer?.index == index ? pointer?.x : nil)
                    .planGraphPointer($pointer, index: index)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(spokenLabel(index)))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityChartDescriptor(chart(index))
            footer(index)
        }
        .background(Palette.card, in: shape)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: isSelected ? 2 : 1)
        }
    }

    /// Fits the money scale to `shown`, by default the cards on screen: at
    /// once the first time, then with the graphs fading to their new places.
    private func fitScale(to shown: Set<Int>? = nil) {
        let shown = shown ?? onScreen.cards(among: indices)
        guard !shown.isEmpty, shown != fitted else { return }
        if fitted.isEmpty {
            fitted = shown
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { fitted = shown }
        }
    }
}

extension PlanCardStrip where Leading == EmptyView, Footer == EmptyView {
    /// A strip with nothing before its cards or under their graphs.
    init(indices: [Int], selection: Binding<Int>, inset: CGFloat, opensAtEnd: Bool = false, identifier: String,
         scale: @escaping (Set<Int>) -> PlanStripScale?, spokenLabel: @escaping (Int) -> String,
         chart: @escaping (Int) -> ChartSummary,
         @ViewBuilder graph: @escaping (_ index: Int, _ scale: PlanStripScale?, _ pointerX: CGFloat?) -> Graph) {
        self.init(indices: indices, selection: selection, inset: inset, opensAtEnd: opensAtEnd,
                  identifier: identifier, scale: scale, spokenLabel: spokenLabel, chart: chart,
                  leading: { EmptyView() }, graph: graph, footer: { _ in EmptyView() })
    }
}

/// The coordinate space of a strip's content, where its cards' frames are.
private let stripContent = "PlanCardStrip.content"

/// Where a strip's cards are along its content and what part of it is on
/// screen, as the strip reports them while it lays out and scrolls, and
/// whether it's scrolling. Nothing observes it: following them doesn't draw
/// the strip again.
@MainActor
final class PlanCardsOnScreen {
    /// Each card's frame in the strip's content, by index.
    var frames: [Int: CGRect] = [:]
    /// `nil` until the strip reports it.
    var viewport: PlanStripViewport?
    var isScrolling = false

    /// The cards, among those laid out, at least a tenth on screen.
    func cards(among laidOut: [Int]) -> Set<Int> {
        guard let viewport else { return [] }
        return cards(among: laidOut, from: viewport.start, width: viewport.width)
    }

    /// The cards, among those laid out, on screen once the strip has
    /// scrolled the card at `index` to its middle, or as far as it can.
    func cards(among laidOut: [Int], centring index: Int) -> Set<Int> {
        guard let viewport, let frame = frames[index] else { return [index] }
        let start = min(max(frame.midX - viewport.width / 2, viewport.starts.lowerBound), viewport.starts.upperBound)
        return cards(among: laidOut, from: start, width: viewport.width)
    }

    private func cards(among laidOut: [Int], from start: CGFloat, width: CGFloat) -> Set<Int> {
        Set(laidOut.filter { index in
            guard let frame = frames[index], frame.width > 0 else { return false }
            let shown = min(frame.maxX, start + width) - max(frame.minX, start)
            return shown >= frame.width * 0.1
        })
    }
}

/// The part of a strip's content on screen, and how far it can scroll.
struct PlanStripViewport: Equatable, Sendable {
    /// Where the part on screen starts along the content, and its width.
    var start: CGFloat
    var width: CGFloat
    /// Where it can start, scrolled to either end.
    var starts: ClosedRange<CGFloat>

    init(_ geometry: ScrollGeometry) {
        start = geometry.contentOffset.x
        width = geometry.containerSize.width
        let first = -geometry.contentInsets.leading
        let last = geometry.contentSize.width - geometry.containerSize.width + geometry.contentInsets.trailing
        starts = first...max(first, last)
    }
}

// MARK: - A card's graph

/// Where a strip card's graph is: its dates across, from `left` to `right`,
/// and its money up, on the scale the cards on screen share, from the
/// plot's bottom up ``height`` points. What runs off the scale is cut at
/// the plot's edge.
struct PlanStripPlot {
    /// The plot's height on every card.
    static let height: CGFloat = 150

    let start: Date
    let end: Date
    let left: CGFloat
    let right: CGFloat
    /// Where the plot starts down the card.
    let top: CGFloat

    var bottom: CGFloat { top + Self.height }

    /// Where `date` falls across, kept inside the plot.
    func x(_ date: Date) -> CGFloat {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return left }
        let share = min(1, max(0, date.timeIntervalSince(start) / span))
        return left + CGFloat(share) * (right - left)
    }

    /// The date at `x` across the plot.
    func date(at x: CGFloat) -> Date {
        let share = right > left ? Double(min(1, max(0, (x - left) / (right - left)))) : 0
        return start.addingTimeInterval(end.timeIntervalSince(start) * share)
    }

    /// Where `value` falls up the plot on `scale`, kept inside it.
    func y(_ value: Double, _ scale: PlanStripScale) -> CGFloat {
        let low = scale.domain.lowerBound
        let high = scale.domain.upperBound
        let share = high > low ? (value - low) / (high - low) : 0
        return bottom - CGFloat(min(1, max(0, share))) * Self.height
    }

    func point(_ date: Date, _ value: Double, _ scale: PlanStripScale) -> CGPoint {
        CGPoint(x: x(date), y: y(value, scale))
    }

    /// The scale's gridlines across a card `width` wide, but the lowest:
    /// the plot's bottom has a line of its own.
    func drawGridlines(_ scale: PlanStripScale, width: CGFloat, in context: inout GraphicsContext) {
        for tick in scale.ticks where tick > scale.domain.lowerBound {
            var gridline = Path()
            gridline.move(to: CGPoint(x: 0, y: y(tick, scale)))
            gridline.addLine(to: CGPoint(x: width, y: y(tick, scale)))
            context.stroke(gridline, with: .color(Palette.gridline), lineWidth: 0.5)
        }
    }
}

/// The amounts of a card's gridlines, above them inside the plot at the
/// card's edge where its line doesn't pass under them: the right when it's
/// clear there, else the left when that is. None while amounts are hidden.
struct PlanStripAmountLabels: View {
    let scale: PlanStripScale
    let plot: PlanStripPlot
    /// The card's width.
    let width: CGFloat
    /// The line the amounts keep off, as drawn.
    let line: [CGPoint]
    let currency: CurrencyCode

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    /// How far in from the card's edge an amount reaches, about.
    private static let reach: CGFloat = 52

    var body: some View {
        ForEach(hidesAmounts ? [] : scale.ticks.filter { $0 > scale.domain.lowerBound }, id: \.self) { tick in
            let y = plot.y(tick, scale)
            Text(scale.label(tick, currency: currency, locale: locale))
                .font(.caption2)
                .foregroundStyle(Palette.mutedInk)
                .planGraphLabel()
                .frame(width: max(0, width - 8), alignment: isOnRight(y) ? .trailing : .leading)
                .offset(x: 4, y: y - 16)
        }
    }

    /// Whether the amount of the gridline at `y` goes at the right edge.
    private func isOnRight(_ y: CGFloat) -> Bool {
        let band = (y - 17)...(y + 1)
        func isClear(_ zone: ClosedRange<CGFloat>) -> Bool {
            !zip(line, line.dropFirst()).contains { from, to in
                (min(from.x, to.x)...max(from.x, to.x)).overlaps(zone)
                    && (min(from.y, to.y)...max(from.y, to.y)).overlaps(band)
            }
        }
        return isClear(max(0, width - Self.reach)...max(0, width)) || !isClear(0...Self.reach)
    }
}

extension View {
    /// A label on a strip card's graph: one line, small, on the card's
    /// colour, so a line under it doesn't cross it.
    func planGraphLabel() -> some View {
        lineLimit(1)
            .padding(.horizontal, 2)
            .background(Palette.card.opacity(0.85), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .fixedSize()
    }
}
