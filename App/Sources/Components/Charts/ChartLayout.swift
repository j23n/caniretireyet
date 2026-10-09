import Foundation

// Where the charts put their ticks and labels (UI.md, "Charts"), worked out
// from the data and the width the chart has, without SwiftUI, so it can be
// tested on Linux: time and number ticks that never crowd, marker labels
// staggered so they never collide, room for a line's label at its end, and
// headroom above the data for those labels.

/// Rough sizes of chart text, for laying labels out before they're drawn.
/// Caption 2 in the system font: about 6 points a character, 15 a line.
enum ChartText {
    /// The width of one character of a caption 2 label, on average.
    static let characterWidth = 6.2
    /// The height of a row of caption 2 labels, with a little air.
    static let rowHeight = 15.0
    /// The width of an SF Symbol in a caption 2 label, with its spacing.
    static let iconWidth = 15.0
    /// The width the leading value axis takes from a chart (labels like `312k`).
    static let valueAxisWidth = 36.0
    /// The height of the time axis under a chart.
    static let timeAxisHeight = 20.0

    /// The estimated width of `text` as a caption 2 label.
    static func width(of text: String) -> Double {
        Double(text.count) * characterWidth
    }

    /// The plot's width in a chart `width` wide with a leading value axis.
    static func plotWidth(chartWidth width: Double) -> Double {
        max(60, width - valueAxisWidth)
    }
}

// MARK: - Time ticks

/// Where a time axis has its labels: years every 1, 2, 5, 10, 20… or, for
/// spans under about two and a half years, months every 1, 2, 3 or 6. The
/// step is the smallest that keeps labels `spacing` points apart, so they
/// never collide, and ticks fall on round years (2030, 2040) or quarter starts.
struct TimeTicks: Hashable, Sendable {
    enum Unit: Hashable, Sendable {
        case months
        case years
    }

    /// The tick dates: the first day of a year or month, inside the domain.
    var dates: [Date]
    var unit: Unit

    static let yearSteps = [1, 2, 5, 10, 20, 25, 50, 100]
    static let monthSteps = [1, 2, 3, 6]
    /// The distance between year labels ("2045" and some air).
    static let yearSpacing = 40.0
    /// The distance between month labels ("Sep" and some air).
    static let monthSpacing = 40.0

    init(domain: ClosedRange<Date>, plotWidth: Double, calendar: Calendar = .current) {
        let days = domain.upperBound.timeIntervalSince(domain.lowerBound) / 86_400
        if days < 365 * 2.5 {
            let fit = max(1, Int(plotWidth / Self.monthSpacing))
            for step in Self.monthSteps {
                let dates = Self.monthStarts(in: domain, every: step, calendar: calendar)
                if dates.count <= fit || step == Self.monthSteps.last {
                    self.init(dates: dates.isEmpty ? [domain.lowerBound] : dates, unit: .months)
                    return
                }
            }
        }
        let fit = max(1, Int(plotWidth / Self.yearSpacing))
        for step in Self.yearSteps {
            let dates = Self.yearStarts(in: domain, every: step, calendar: calendar)
            if dates.count <= fit || step == Self.yearSteps.last {
                self.init(dates: dates.isEmpty ? [domain.lowerBound] : dates, unit: .years)
                return
            }
        }
        self.init(dates: [domain.lowerBound], unit: .years)
    }

    init(dates: [Date], unit: Unit) {
        self.dates = dates
        self.unit = unit
    }

    /// A tick's label: the year ("2045"), or the month ("Sep"), with the
    /// year instead in January so month ticks say which year they're in.
    func label(for date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let year = calendar.component(.year, from: date)
        switch unit {
        case .years:
            return String(year)
        case .months:
            if calendar.component(.month, from: date) == 1 { return String(year) }
            let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            return date.formatted(style.month(.abbreviated))
        }
    }

    /// 1 January of the years divisible by `step`, inside `domain`.
    static func yearStarts(in domain: ClosedRange<Date>, every step: Int, calendar: Calendar) -> [Date] {
        let first = calendar.component(.year, from: domain.lowerBound)
        let last = calendar.component(.year, from: domain.upperBound)
        var dates: [Date] = []
        var year = Int((Double(first) / Double(step)).rounded(.up)) * step
        while year <= last {
            if let date = calendar.date(from: DateComponents(year: year, month: 1, day: 1)), domain.contains(date) {
                dates.append(date)
            }
            year += step
        }
        return dates
    }

    /// The first day of the months whose number (from January, 0) is
    /// divisible by `step`, inside `domain`.
    static func monthStarts(in domain: ClosedRange<Date>, every step: Int, calendar: Calendar) -> [Date] {
        let start = calendar.dateComponents([.year, .month], from: domain.lowerBound)
        guard var year = start.year, var month = start.month else { return [] }
        var dates: [Date] = []
        while let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              date <= domain.upperBound {
            if (month - 1) % step == 0, date >= domain.lowerBound { dates.append(date) }
            month += 1
            if month > 12 {
                month = 1
                year += 1
            }
        }
        return dates
    }
}

// MARK: - Number ticks

/// Ticks on a whole-number axis (ages, years): multiples of 1, 2, 5, 10…,
/// the smallest step whose labels stay `spacing` points apart.
enum IntegerTicks {
    static let steps = [1, 2, 5, 10, 20, 25, 50, 100]
    /// The distance between age labels ("45" and some air).
    static let ageSpacing = 30.0
    /// The distance between year labels ("2045" and some air).
    static let yearSpacing = TimeTicks.yearSpacing

    static func values(in range: ClosedRange<Int>, plotWidth: Double, spacing: Double,
                       steps: [Int] = IntegerTicks.steps) -> [Int] {
        let fit = max(1, Int(plotWidth / spacing))
        var last: [Int] = []
        for step in steps {
            let first = Int((Double(range.lowerBound) / Double(step)).rounded(.up)) * step
            let values = Array(stride(from: first, through: range.upperBound, by: step))
            last = values
            if values.count <= fit { return values.isEmpty ? [range.lowerBound] : values }
        }
        return last.isEmpty ? [range.lowerBound] : last
    }
}

// MARK: - Room for a label at a line's end

/// How far a chart's x domain reaches past its data so a line's label fits
/// at its end, outside the data: `labelWidth` points in a plot
/// `plotWidth` wide whose data spans `span` (in the domain's units).
func endLabelPadding(span: Double, labelWidth: Double, plotWidth: Double) -> Double {
    guard span > 0, plotWidth > labelWidth + 20 else { return 0 }
    // The label takes labelWidth of the plot; the data the rest.
    return span * labelWidth / (plotWidth - labelWidth)
}

// MARK: - Marker labels

/// Where each marker's label goes along a time axis (UI.md, "Charts"):
/// labels never collide. Each sits right of its rule (or left, at the
/// chart's right edge), in the lowest of ``maxRows`` rows where it fits; a
/// marker whose label fits in no row shows only its icon, and its label
/// moves to the callout. A rule never runs through another row's label:
/// rules stop below the rows, and labels in an upper row are raised by
/// their row's height.
struct MarkerLabelLayout: Hashable, Sendable {
    struct Placement: Hashable, Sendable, Identifiable {
        var marker: ChartMarker
        /// 0 is the row nearest the data.
        var row: Int
        /// `false`: only the icon shows; the label is in the callout.
        var showsLabel: Bool
        /// The label sits left of the rule, ending at it.
        var endsAtRule: Bool

        var id: String { marker.id }
    }

    var placements: [Placement]
    /// How many rows of labels the chart needs above its data (0 without markers).
    var rows: Int

    /// The gap kept between two labels in a row.
    static let gap = 8.0
    /// The most rows of labels above the data.
    static let maxRows = 2

    /// The width of a marker's label: its icon and text.
    static func labelWidth(_ marker: ChartMarker) -> Double {
        ChartText.iconWidth + ChartText.width(of: marker.label)
    }

    init(markers: [ChartMarker], domain: ClosedRange<Date>, plotWidth: Double) {
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        let shown = markers.filter { domain.contains($0.date) }.sorted { $0.date < $1.date }
        guard !shown.isEmpty, span > 0 else {
            placements = []
            rows = 0
            return
        }
        func x(_ date: Date) -> Double { date.timeIntervalSince(domain.lowerBound) / span * plotWidth }
        var rowEnds = [Double](repeating: -.infinity, count: Self.maxRows)
        var placed: [Placement] = []
        for marker in shown {
            let position = x(marker.date)
            let width = Self.labelWidth(marker)
            let endsAtRule = position + width > plotWidth
            let start = endsAtRule ? max(0, position - width) : position
            let end = endsAtRule ? position : position + width
            if let row = rowEnds.indices.first(where: { start >= rowEnds[$0] + Self.gap }) {
                rowEnds[row] = end
                placed.append(Placement(marker: marker, row: row, showsLabel: true, endsAtRule: endsAtRule))
            } else {
                // Only the icon, centred on the rule, in the row with the most room.
                let row = rowEnds.indices.min { rowEnds[$0] < rowEnds[$1] } ?? 0
                rowEnds[row] = max(rowEnds[row], position + ChartText.iconWidth / 2)
                placed.append(Placement(marker: marker, row: row, showsLabel: false, endsAtRule: false))
            }
        }
        placements = placed
        rows = (placed.map(\.row).max() ?? -1) + 1
    }

    /// The markers within 200 days of `date` that show only their icon,
    /// for a callout: what happens around the date being read, whose labels
    /// aren't on the chart.
    func iconOnly(near date: Date) -> [ChartMarker] {
        placements.filter { !$0.showsLabel && abs($0.marker.date.timeIntervalSince(date)) <= 200 * 86_400 }
            .map(\.marker)
    }

    /// The points of headroom the rows need above the data.
    var headroom: Double {
        Double(rows) * ChartText.rowHeight + (rows > 0 ? 4 : 0)
    }
}
