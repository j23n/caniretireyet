import SwiftUI

/// Its content at the size it's offered, never smaller than a fixed minimum:
/// the Mac window's root, and the Plan screen's columns.
///
/// The window (`.windowResizability(.contentMinSize)`) can't be made smaller
/// than the minimum size of its content. Measured through the content, that
/// minimum moved while the window shrank: a `ViewThatFits` switching to
/// another layout, a chart fitting its ticks to the width it measured. Each
/// move changed the window's constraints in the middle of the resize, and
/// near the limit it never settled: AppKit stopped the app with "needing
/// another Update Constraints in Window pass" (see ``EqualColumns`` for the
/// same loop inside a page). This layout answers with its fixed minimum and
/// never asks its content, so the window's minimum can't move; the content
/// is laid out in whatever the window gives it, and pages scroll.
///
/// A column of the sidebar's split view (the page, an inspector) is the same:
/// the split view measures each column's minimum and maximum, and when one
/// moves it lays out the whole window again. Switching to a plan's Progress
/// while it calculated kept moving the page's minimum, and AppKit stopped
/// the app the same way. Use `fixedMinimumSize(width:height:)` there.
///
/// Offered an infinite size, it's as large (it has no maximum); offered no
/// size, it's its minimum.
struct FixedMinimumSize: Layout {
    var minWidth: CGFloat
    var minHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: Self.dimension(proposal.width, minimum: minWidth),
               height: Self.dimension(proposal.height, minimum: minHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }

    /// The size along one axis: what's offered, at least `minimum`; the
    /// minimum when nothing is offered.
    private static func dimension(_ offered: CGFloat?, minimum: CGFloat) -> CGFloat {
        guard let offered, !offered.isNaN else { return minimum }
        return max(minimum, offered)
    }
}

extension View {
    /// On the Mac, the view at the size it's offered and never smaller than
    /// `width` × `height`, without asking it (``FixedMinimumSize``): for a
    /// column of a split view, whose measured minimum must not move.
    /// Elsewhere the view as it is.
    @ViewBuilder
    func fixedMinimumSize(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        FixedMinimumSize(minWidth: width, minHeight: height) { self }
        #else
        self
        #endif
    }
}
