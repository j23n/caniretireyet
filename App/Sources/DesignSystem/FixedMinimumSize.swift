import SwiftUI

/// Its content at the size it's offered, never smaller than a fixed minimum:
/// the Mac window's root.
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
    /// minimum when nothing (or no finite size) is offered.
    private static func dimension(_ offered: CGFloat?, minimum: CGFloat) -> CGFloat {
        guard let offered, offered.isFinite else { return minimum }
        return max(minimum, offered)
    }
}
