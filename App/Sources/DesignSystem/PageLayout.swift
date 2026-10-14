import SwiftUI

/// How a page is laid out: wide in the sidebar layout (the Mac and iPad),
/// narrow with tabs (iPhone). The root sets it from the navigation's layout
/// (`AppNavigation.layout`); the Plan screen narrows it while What if is a
/// column beside the plan. Views read it as `@Environment(\.pageLayout)`
/// instead of taking layout flags.
struct PageLayout: Hashable, Sendable {
    /// The sidebar layout (the Mac and iPad): wider cards, things side by
    /// side, ‹ › above the strips; else iPhone's tabs.
    var isWide = false
    /// Whether What if takes a column beside the page (the Mac and iPad),
    /// so the page is narrower.
    var besideWhatIf = false

    /// Whether the page has the width for things side by side: wide, unless
    /// What if takes a column beside it.
    var isRoomy: Bool { isWide && !besideWhatIf }

    /// The page's margin at its sides, and the strips' inset at both ends.
    var gutter: CGFloat { isWide ? Metrics.xl : Metrics.l }
}

extension EnvironmentValues {
    /// How the page is laid out (``PageLayout``); narrow until the root sets it.
    @Entry var pageLayout = PageLayout()
}
