import Charts
import SwiftUI

/// A row of buttons under a chart, each under its band on the time axis
/// (``ChartBandLayout``): the plan's chapters on the map (UI.md,
/// "Chapters"), the years of Progress. The selected band's button is
/// filled; choosing a button selects its band. Each shows the longest of
/// its band's titles that fits: "Self-employed", "Work", or its number.
struct ChartBandStrip: View {
    let bands: [ChartBand]
    let layout: ChartBandLayout
    /// The plot's leading edge from the strip's, in points.
    var plotX: Double = 0
    @Binding var selection: Int?

    static let height: CGFloat = 30

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.slots) { slot in
                if let band = bands.first(where: { $0.id == slot.id }) {
                    button(band, slot: slot)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: Self.height)
    }

    private func button(_ band: ChartBand, slot: ChartBandLayout.Slot) -> some View {
        let isSelected = selection == band.id
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Button {
            selection = band.id
        } label: {
            ViewThatFits(in: .horizontal) {
                Text(band.title)
                Text(band.shortTitle)
                Text(band.tinyTitle ?? String(band.id + 1))
            }
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(isSelected ? Color.white : Palette.secondaryInk)
            .padding(.horizontal, 3)
            .frame(width: max(1, CGFloat(slot.width) - 2), height: Self.height)
            .background(isSelected ? Palette.accent : Palette.card, in: shape)
            .overlay { shape.strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: 1) }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .offset(x: CGFloat(plotX + slot.x) + 1)
        .accessibilityLabel(Text(band.title))
        .accessibilityValue(Text(band.detail))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension ChartBand {
    /// Its shade behind a chart: the selected band in the hue, the others
    /// in two alternating greys, so neighbours stay apart.
    func tint(selected: Int?) -> Color {
        if id == selected { return Palette.accent.opacity(0.14) }
        return Palette.gridline.opacity(id.isMultiple(of: 2) ? 0.25 : 0.55)
    }
}

extension View {
    /// Keeps `area` in step with where the chart's plot is, in whole
    /// points, so a ``ChartBandStrip`` under it lines up. Apply to a `Chart`.
    func measuringPlot(_ area: Binding<ChartPlotArea?>) -> some View {
        chartOverlay { proxy in
            GeometryReader { geometry in
                let frame = proxy.plotFrame.map { geometry[$0] } ?? .zero
                Color.clear
                    .onAppear { ChartPlotArea.update(area, to: frame) }
                    .onChange(of: frame) { _, newFrame in ChartPlotArea.update(area, to: newFrame) }
            }
            .allowsHitTesting(false)
        }
    }
}

extension ChartPlotArea {
    /// Sets `area` to `frame` when it moved by a whole point.
    @MainActor
    static func update(_ area: Binding<ChartPlotArea?>, to frame: CGRect) {
        guard frame.width > 0 else { return }
        let measured = ChartPlotArea(x: Double(frame.minX.rounded()), width: Double(frame.width.rounded()))
        if measured != area.wrappedValue { area.wrappedValue = measured }
    }
}

#Preview("Band strip") {
    @Previewable @State var selection: Int? = 1
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let year = 365.25 * 86_400
    let bands = [
        ChartBand(id: 0, start: start, end: start + 3 * year, title: "Employee", shortTitle: "Work",
                  detail: "3 years"),
        ChartBand(id: 1, start: start + 3 * year, end: start + 17 * year, title: "Self-employed",
                  shortTitle: "Work", detail: "14 years"),
        ChartBand(id: 2, start: start + 17 * year, end: start + 29 * year, title: "Retired, before pensions",
                  shortTitle: "Retired", detail: "12 years"),
        ChartBand(id: 3, start: start + 29 * year, end: start + 57 * year, title: "Pensions",
                  shortTitle: "Pensions", detail: "28 years"),
    ]
    ChartBandStrip(bands: bands,
                   layout: ChartBandLayout(bands: bands, domain: start...(start + 57 * year), plotWidth: 320),
                   selection: $selection)
        .padding()
}
