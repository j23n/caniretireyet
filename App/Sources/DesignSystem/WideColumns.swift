import SwiftUI

/// A page's main column with a narrower column beside it, as Timeline
/// draws on the Mac and iPad: side by side when the page is wide enough
/// for both, else the side column's cards under the main column's, so a
/// narrow window never squeezes a chart or a table. One layout for both,
/// so the cards keep their state when a window crosses the width.
///
///     WideColumns {
///         chartCard
///     } side: {
///         howSureCard
///     }
struct WideColumns<Main: View, Side: View>: View {
    private let sideWidth: CGFloat
    private let mainMinWidth: CGFloat
    private let main: Main
    private let side: Side

    /// - Parameters:
    ///   - sideWidth: The side column's width.
    ///   - mainMinWidth: The narrowest the main column may be beside it.
    init(sideWidth: CGFloat = 300, mainMinWidth: CGFloat = 560, @ViewBuilder _ main: () -> Main,
         @ViewBuilder side: () -> Side) {
        self.sideWidth = sideWidth
        self.mainMinWidth = mainMinWidth
        self.main = main()
        self.side = side()
    }

    var body: some View {
        WideColumnsLayout(sideWidth: sideWidth, mainMinWidth: mainMinWidth, spacing: Metrics.l) {
            VStack(alignment: .leading, spacing: Metrics.l) { main }
            VStack(alignment: .leading, spacing: Metrics.l) { side }
        }
    }
}

/// Places its first view as the main column and its second as the side
/// column: beside it while the main one keeps `mainMinWidth`, else under it.
private struct WideColumnsLayout: Layout {
    var sideWidth: CGFloat
    var mainMinWidth: CGFloat
    var spacing: CGFloat

    private func besides(_ width: CGFloat) -> Bool {
        width >= mainMinWidth + spacing + sideWidth
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let width = proposal.width ?? mainMinWidth + spacing + sideWidth
        if besides(width) {
            let main = subviews[0].sizeThatFits(ProposedViewSize(width: width - spacing - sideWidth, height: nil))
            let side = subviews[1].sizeThatFits(ProposedViewSize(width: sideWidth, height: nil))
            return CGSize(width: width, height: max(main.height, side.height))
        }
        let main = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let side = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: main.height + spacing + side.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        if besides(bounds.width) {
            let mainWidth = bounds.width - spacing - sideWidth
            subviews[0].place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: mainWidth, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX + mainWidth + spacing, y: bounds.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: sideWidth, height: nil))
        } else {
            let main = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subviews[0].place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + main.height + spacing),
                              anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}
