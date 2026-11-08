import SwiftUI
import Testing
@testable import CanIRetireYet

/// The app's type scale on the Mac (UI.md, "Type"): the iPad's sizes at
/// about 90%, each style no smaller than the one below it, and nothing
/// under 11 points.
@MainActor
struct AppTypeTests {
    private let styles: [Font.TextStyle] = [.caption2, .caption, .footnote, .subheadline, .callout, .body,
                                            .title3, .title2, .title, .largeTitle]

    @Test func theMacSizesAreThoseOfTheScale() {
        #expect(AppType.macSize(of: .caption) == 11)
        #expect(AppType.macSize(of: .footnote) == 12)
        #expect(AppType.macSize(of: .subheadline) == 13)
        #expect(AppType.macSize(of: .body) == 15)
        #expect(AppType.macSize(of: .headline) == 15)
        #expect(AppType.macSize(of: .title2) == 20)
        #expect(AppType.macSize(of: .largeTitle) == 30)
    }

    @Test func eachStyleIsAtLeastAsLargeAsTheOneBelow() {
        let sizes = styles.map(AppType.macSize(of:))
        #expect(sizes == sizes.sorted())
    }

    @Test func nothingIsSmallerThanElevenPoints() {
        #expect(styles.allSatisfy { AppType.macSize(of: $0) >= 11 })
    }
}
