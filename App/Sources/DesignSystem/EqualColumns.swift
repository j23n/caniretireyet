import SwiftUI

/// Its children side by side in columns of equal width, each as tall as it
/// needs, the row as tall as the tallest, aligned at the top: the Mac's and
/// iPad's two columns of plan results.
///
/// Unlike `Grid` or `HStack`, the columns never depend on what the children
/// would like to be. Charts fit their ticks and legends to the width they
/// measure, which changes what they'd like to be; in a `Grid` that fed back
/// into the width of their column, and on the Mac the window, never
/// settling, stopped with "needing another Update Constraints in Window
/// pass". Offered no width (or an infinite one), it takes a fixed width
/// rather than asking the children.
struct EqualColumns: Layout {
    var spacing: CGFloat = Metrics.l
    /// The width of a column when the parent offers no width.
    private static let fallbackColumnWidth: CGFloat = 360

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = totalWidth(proposal.width, count: subviews.count)
        let column = columnWidth(width, count: subviews.count)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: column, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = columnWidth(bounds.width, count: subviews.count)
        for (index, subview) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(index) * (column + spacing)
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: column, height: nil))
        }
    }

    private func totalWidth(_ offered: CGFloat?, count: Int) -> CGFloat {
        if let offered, offered.isFinite { return max(0, offered) }
        return Self.fallbackColumnWidth * CGFloat(count) + spacing * CGFloat(count - 1)
    }

    private func columnWidth(_ width: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
    }
}
