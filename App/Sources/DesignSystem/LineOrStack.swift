import SwiftUI

/// Two parts on one line, or the second under the first when the line is
/// too narrow, so neither is cut short: "▲ +43.265 € in a year" on a wide
/// tile, the change over "in a year" on a narrow one. With `spread`, the
/// second part sits at the line's trailing edge.
///
///     LineOrStack(DeltaText(change), Text("in a year"))
struct LineOrStack<First: View, Second: View>: View {
    let first: First
    let second: Second
    var spread = false

    init(_ first: First, _ second: Second, spread: Bool = false) {
        self.first = first
        self.second = second
        self.spread = spread
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                first
                if spread {
                    Spacer(minLength: Metrics.s)
                }
                second
            }
            VStack(alignment: .leading, spacing: 2) {
                first
                second
            }
        }
    }
}
