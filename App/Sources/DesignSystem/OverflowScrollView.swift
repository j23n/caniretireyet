import SwiftUI

/// Content shown at its own height when there's room for it, and scrolling
/// when there isn't: a panel pinned above or below a scrolling area, such
/// as the Mac's What-if under the plan's inputs, or the import's column
/// settings above the table.
///
/// It takes at most `maxShare` of the height it's offered, and no more than
/// its content needs. Its minimum height is zero: on the Mac a window can't
/// be smaller than the minimum size of its content, so content that never
/// scrolls makes the window as tall as itself, even taller than the screen
/// (text that wraps, measured at the narrowest width, is very tall).
///
/// The content is always inside one scroll view, which only scrolls (and
/// bounces) when it's cut short. It used to switch between the content and
/// a scrolling copy of it, which on the Mac rebuilt the content's controls
/// in the middle of laying out the window, and with content near the limit
/// could keep switching: AppKit stops such a window with an exception.
///
///     VStack(spacing: 0) {
///         ScrollView { inputs }
///         Divider()
///         OverflowScrollView(maxShare: 0.6) { whatIf }
///             .layoutPriority(1)   // offered the whole column first
///     }
struct OverflowScrollView<Content: View>: View {
    /// The share of the height it's offered that it takes at most, from 0
    /// to 1; it scrolls beyond that.
    var maxShare: CGFloat
    private let content: Content

    init(maxShare: CGFloat = 1, @ViewBuilder content: () -> Content) {
        self.maxShare = min(1, max(0.1, maxShare))
        self.content = content()
    }

    var body: some View {
        HeightShareLayout(share: maxShare) {
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// Sizes its one child, a vertical scroll view, to the child's content
/// height (its ideal height), but no taller than a share of the height it's
/// offered; offered no height, it's none (its minimum).
private struct HeightShareLayout: Layout {
    var share: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        // A scroll view offered no height answers with its content's height.
        let ideal = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let height: CGFloat
        if let offered = proposal.height, offered.isFinite {
            height = min(ideal.height, offered * share)
        } else {
            height = ideal.height
        }
        return CGSize(width: proposal.width ?? ideal.width, height: max(0, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

#Preview("Fits, then scrolls") {
    VStack(spacing: 0) {
        ScrollView {
            Text("The inputs")
                .frame(maxWidth: .infinity, minHeight: 400)
        }
        Divider()
        OverflowScrollView(maxShare: 0.5) {
            VStack(alignment: .leading, spacing: Metrics.m) {
                ForEach(1..<12) { index in
                    Text("Line \(index)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Metrics.m)
        }
        .layoutPriority(1)
        .background(.bar)
    }
    .frame(width: 320, height: 480)
}
