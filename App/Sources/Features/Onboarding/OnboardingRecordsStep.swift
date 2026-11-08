import Model
import SwiftUI

/// What your records show (UI.md, "Empty states and first launch"): after
/// the answer, four example tiles of what recording what came in, what
/// you spent and what you added each month adds to it: where your pay
/// went, what moved your net worth, the savings rate by month, and the
/// year against its plan. Made-up numbers in the tour's currency
/// (``OnboardingRecordsExample``), each tile marked *Example*.
struct OnboardingRecordsStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            OnboardingTitle("What your records show",
                            detail: "Your answer works from balances alone. Each month you can also record what "
                                + "came in, what you spent and what you added, so the app can show you these. The "
                                + "numbers are an example.")
            payTile
            netWorthTile
            savingsRateTile
            yearTile
            Text("You get these whether you type your numbers or import your statements. The next step lets you "
                + "choose.")
                .font(.app(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var example: OnboardingRecordsExample { OnboardingRecordsExample(currency: model.currency) }

    // MARK: Tiles

    private var payTile: some View {
        ExampleTile("Your pay in September",
                    caption: "Where your pay went, and your savings rate.") {
            HStack(alignment: .center, spacing: Metrics.m) {
                VStack(spacing: Metrics.xs) {
                    ForEach(example.payLines) { line in
                        lineRow(line)
                    }
                }
                ExampleRing(saved: example.savingsRate, spent: example.spentShare, tax: example.taxShare)
                    .frame(width: 84, height: 84)
            }
        }
    }

    private var netWorthTile: some View {
        ExampleTile("Your net worth in September",
                    caption: "Whether your own saving or the markets moved your money this month.") {
            HStack(alignment: .bottom, spacing: Metrics.m) {
                VStack(spacing: Metrics.xs) {
                    ForEach(example.netWorthLines) { line in
                        lineRow(line)
                    }
                }
                HStack(alignment: .bottom, spacing: Metrics.s) {
                    ForEach(example.netWorthLines) { line in
                        RoundedRectangle(cornerRadius: Metrics.barRadius)
                            .fill(line.kind.color)
                            .frame(width: 24, height: CGFloat(truncating: (line.amount / example.netWorthChange)
                                    as NSDecimalNumber) * 72)
                    }
                }
                .frame(height: 72, alignment: .bottom)
                .accessibilityHidden(true)
            }
        }
    }

    private var savingsRateTile: some View {
        ExampleTile("Savings rate by month",
                    caption: "How much of your pay you keep, month by month, against what your plan expects.") {
            ExampleBars(rates: OnboardingRecordsExample.monthlyRates, planned: OnboardingRecordsExample.plannedRate,
                        locale: locale)
                .frame(height: 120)
        }
    }

    private var yearTile: some View {
        ExampleTile("\(String(CalendarDate.today().year)) so far",
                    caption: "Each year against the plan you had in January: ahead, on track or behind.") {
            VStack(alignment: .leading, spacing: Metrics.s) {
                Text("Ahead of what you planned in January")
                    .font(.app(.subheadline).weight(.semibold))
                    .foregroundStyle(Palette.accent)
                ExampleYearLine(values: OnboardingRecordsExample.yearValues)
                    .frame(height: 110)
            }
        }
    }

    private func lineRow(_ line: TodayMovedLine) -> some View {
        HStack(spacing: Metrics.s) {
            Circle()
                .fill(line.kind.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(line.title)
            Spacer(minLength: Metrics.s)
            Text(line.isSum || line.kind == .cameIn
                 ? AmountFormat.amount(line.amount, currency: model.currency, locale: locale)
                 : AmountFormat.signedAmount(line.amount, currency: model.currency, locale: locale))
                .monospacedDigit()
        }
        .font(line.isSum ? .app(.subheadline).weight(.semibold) : .app(.subheadline))
        .foregroundStyle(Palette.ink)
        .accessibilityElement(children: .combine)
    }
}

/// The made-up month of ``OnboardingRecordsStep``: 4.810 came in, 1.200 of
/// it tax, 2.110 spent, so 1.500 saved, 42% of the pay after tax; markets
/// added 2.950. Amounts round in the tour's currency, which may not be the
/// euro, so they're only examples.
struct OnboardingRecordsExample {
    let currency: CurrencyCode

    static let cameIn: Decimal = 4810
    static let tax: Decimal = 1200
    static let spent: Decimal = 2110
    static let markets: Decimal = 2950

    var saved: Decimal { Self.cameIn - Self.tax - Self.spent }
    var netWorthChange: Decimal { saved + Self.markets }

    /// What was saved over the pay after tax.
    var savingsRate: Double { share(saved, of: Self.cameIn - Self.tax) }
    var spentShare: Double { share(Self.spent, of: Self.cameIn) }
    var taxShare: Double { share(Self.tax, of: Self.cameIn) }

    var payLines: [TodayMovedLine] {
        [TodayMovedLine(kind: .cameIn, amount: Self.cameIn), TodayMovedLine(kind: .tax, amount: -Self.tax),
         TodayMovedLine(kind: .spent, amount: -Self.spent), TodayMovedLine(kind: .saved, amount: saved, isSum: true)]
    }

    var netWorthLines: [TodayMovedLine] {
        [TodayMovedLine(kind: .saved, amount: saved), TodayMovedLine(kind: .markets, amount: Self.markets),
         TodayMovedLine(kind: .total, amount: netWorthChange, isSum: true)]
    }

    /// The savings rate, January to September; September's month isn't
    /// over yet.
    static let monthlyRates: [Double] = [0.31, 0.28, 0.44, 0.35, 0.30, 0.38, 0.22, 0.41, 0.36]
    /// The rate the plan expects.
    static let plannedRate = 0.30

    /// Money through the year so far, as a share of the way to the plan's
    /// end of the year: January to October.
    static let yearValues: [Double] = [0, 0.11, 0.26, 0.19, 0.41, 0.52, 0.59, 0.70, 0.85, 1.0]

    private func share(_ part: Decimal, of whole: Decimal) -> Double {
        whole == 0 ? 0 : Double(truncating: (part / whole) as NSDecimalNumber)
    }
}

/// A white tile with its title, *Example* beside it, the content, and a
/// line on what it tells you.
private struct ExampleTile<Content: View>: View {
    let title: String
    let caption: String
    let content: Content

    init(_ title: String, caption: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack {
                Text(title)
                    .font(.app(.subheadline).weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("EXAMPLE")
                    .font(.app(.caption2).weight(.bold))
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Palette.page, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityLabel(Text("Example"))
            }
            content
            Text(caption)
                .font(.app(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onboardingCard()
        .accessibilityElement(children: .contain)
    }
}

/// The pay tile's ring: what was saved, spent and taxed, with the savings
/// rate in its middle.
private struct ExampleRing: View {
    let saved: Double
    let spent: Double
    let tax: Double

    @Environment(\.locale) private var locale

    var body: some View {
        ZStack {
            ring(from: 0, to: saved, color: TodayMovedLine.Kind.saved.color)
            ring(from: saved, to: saved + spent, color: TodayMovedLine.Kind.spent.color)
            ring(from: saved + spent, to: saved + spent + tax, color: TodayMovedLine.Kind.tax.color)
            VStack(spacing: 0) {
                Text(AmountFormat.percent(saved, digits: 0, locale: locale))
                    .font(.app(.headline))
                    .monospacedDigit()
                Text("saved")
                    .font(.app(.caption2))
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(AmountFormat.percent(saved, digits: 0, locale: locale)) of the pay saved"))
    }

    private func ring(from start: Double, to end: Double, color: Color) -> some View {
        Circle()
            .trim(from: start, to: min(end, 1))
            .stroke(color, style: StrokeStyle(lineWidth: 10))
            .rotationEffect(.degrees(-90))
            .padding(5)
    }
}

/// The savings rate's bars by month, the month still going lighter, with
/// the plan's rate dashed across them.
private struct ExampleBars: View {
    let rates: [Double]
    let planned: Double
    let locale: Locale

    var body: some View {
        GeometryReader { proxy in
            let top = 0.5
            let height = proxy.size.height - 14
            let step = proxy.size.width / CGFloat(max(rates.count, 1))
            ZStack(alignment: .topLeading) {
                ForEach(rates.indices, id: \.self) { index in
                    let barHeight = height * CGFloat(rates[index] / top)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(TodayMovedLine.Kind.saved.color.opacity(index == rates.count - 1 ? 0.5 : 1))
                        .frame(width: step * 0.66, height: barHeight)
                        .offset(x: step * CGFloat(index) + step * 0.17, y: height - barHeight)
                    Text(Self.monthLetter(index, locale: locale))
                        .font(.app(.caption2))
                        .foregroundStyle(Palette.secondaryInk)
                        .frame(width: step)
                        .offset(x: step * CGFloat(index), y: height + 1)
                }
                let planY = height * CGFloat(1 - planned / top)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: planY))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: planY))
                }
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                Text("your plan's \(AmountFormat.percent(planned, digits: 0, locale: locale))")
                    .font(.app(.caption2))
                    .foregroundStyle(Palette.accentDeep)
                    .frame(width: proxy.size.width, alignment: .trailing)
                    .offset(y: planY - 16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Bars of the savings rate each month, mostly above the plan's rate"))
    }

    /// "J", "F", "M": the first letter of January, February and so on.
    static func monthLetter(_ index: Int, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = calendar.veryShortStandaloneMonthSymbols
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
}

/// The year so far: money through the year above the plan's straight
/// dashed line to the year's end.
private struct ExampleYearLine: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            // The year's twelve months across; values run through October.
            let step = width / 11
            let point = { (index: Int, value: Double) in
                CGPoint(x: step * CGFloat(index), y: height * CGFloat(1 - value * 0.8))
            }
            ZStack {
                Path { path in
                    path.move(to: point(0, 0))
                    path.addLine(to: point(11, 1.1))
                }
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                Path { path in
                    for (index, value) in values.enumerated() {
                        if index == 0 {
                            path.move(to: point(index, value))
                        } else {
                            path.addLine(to: point(index, value))
                        }
                    }
                }
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                if let last = values.indices.last {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 10, height: 10)
                        .position(point(last, values[last]))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Your money this year, above the plan's dashed line"))
    }
}
