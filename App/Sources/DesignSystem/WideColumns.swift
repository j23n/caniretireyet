import SwiftUI

/// A page's main column with a narrower column beside it, as Timeline
/// draws on the Mac and iPad: side by side when the page is wide enough
/// for both, else the side column's cards under the main column's, so a
/// narrow window never squeezes a chart or a table.
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

    /// The page's width; `nil` until it's known, when the columns start
    /// side by side.
    @State private var width: CGFloat?

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

    private var besides: Bool {
        guard let width else { return true }
        return width >= mainMinWidth + Metrics.l + sideWidth
    }

    var body: some View {
        Group {
            if besides {
                HStack(alignment: .top, spacing: Metrics.l) {
                    VStack(alignment: .leading, spacing: Metrics.l) { main }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: Metrics.l) { side }
                        .frame(width: sideWidth)
                }
            } else {
                VStack(alignment: .leading, spacing: Metrics.l) {
                    main
                    side
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
    }
}
