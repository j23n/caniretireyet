import Model
import SwiftUI

/// Progress (UI.md, "Progress"; PROGRESS.md): how the answer moved from one
/// check-in to the next, then year by year, newest first, what you saved,
/// what markets did, how the answer moved and where you stand against the
/// year's baseline, and your actual numbers against a baseline you choose.
struct PlanProgressView: View {
    let session: PlanSession
    var isWide = false
    /// Asks for a label and saves a baseline (the screen owns the alert).
    let onSaveBaseline: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @State private var selectedBaseline: BaselineID?
    /// The year chosen under the answer chart.
    @State private var selectedYear: Int?

    private var answerHistory: PlanAnswerHistory {
        PlanAnswerHistory(library.library.headlines(for: session.planID))
    }

    private var baselines: [PlanBaselineEntry] {
        PlanBaselineComparison.baselines(for: session.planID, in: library.library)
    }

    private var years: [PlanProgressYear] {
        PlanProgressYear.years(for: session.planID, library: library.library, valuator: library.valuator,
                               asOf: library.asOfDate)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content(proxy)
                    .padding(Metrics.l)
                    .frame(maxWidth: isWide ? 1_000 : Metrics.readableWidth)
                    .frame(maxWidth: .infinity)
            }
            .onChange(of: selectedYear) { _, year in
                guard let year else { return }
                withAnimation(.snappy) { proxy.scrollTo(year, anchor: .top) }
            }
        }
        .background(Palette.page)
        .onAppear {
            if selectedBaseline == nil { selectedBaseline = baselines.first?.id }
        }
    }

    private func content(_ proxy: ScrollViewProxy) -> some View {
        let years = self.years
        return VStack(alignment: .leading, spacing: Metrics.l) {
            answerCard(years: years)
            if !years.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Year by year")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("What you saved, what markets did, and how the answer moved.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .padding(.horizontal, Metrics.xs)
                ForEach(years) { year in
                    PlanProgressYearCard(year: year, isSelected: selectedYear == year.year) {
                        guard let baseline = year.baseline else { return }
                        selectedBaseline = baseline.id
                        withAnimation(.snappy) { proxy.scrollTo(Self.baselineAnchor, anchor: .top) }
                    }
                    .id(year.year)
                }
            }
            baselineCard
                .id(Self.baselineAnchor)
        }
    }

    /// Where "Show on the chart" scrolls to.
    private static let baselineAnchor = "baseline"

    // MARK: Your answer over time

    /// The years as bands on the answer chart: each from 1 January to the
    /// next, so they meet.
    private static func bands(for years: [PlanProgressYear]) -> [ChartBand] {
        years.compactMap { year in
            guard let start = CalendarDate(year: year.year, month: 1, day: 1),
                  let end = CalendarDate(year: year.year + 1, month: 1, day: 1) else { return nil }
            let short = "’" + String(String(year.year).suffix(2))
            return ChartBand(id: year.year, start: start.dateValue, end: end.dateValue, title: year.title,
                             shortTitle: String(year.year), detail: "The year \(year.year)", tinyTitle: short)
        }
    }

    private func answerCard(years: [PlanProgressYear]) -> some View {
        let history = answerHistory
        return Card {
            Text("Earliest retirement age at each check-in")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            PlanAnswerHistoryChart(history: history, bands: Self.bands(for: years),
                                   selectedBand: years.count > 1 ? $selectedYear : nil)
            if let latest = history.latestAge {
                HStack(spacing: Metrics.s) {
                    Text("\(latest) now")
                        .font(.subheadline.weight(.semibold))
                    if let change = history.change, change.years != 0 {
                        Text(changeText(change.years))
                            .font(.subheadline)
                            .monospacedDigit()
                            // An earlier age is good news.
                            .foregroundStyle(change.years < 0 ? Palette.positive : Palette.negative)
                        Text("since \(PlanResultsText.monthYear(change.since, locale: locale))")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
            if !history.markers.isEmpty {
                HStack(spacing: Metrics.m) {
                    ForEach(PlanAnswerHistory.Change.allCases, id: \.self) { change in
                        if history.markers.contains(where: { $0.changes.contains(change) }) {
                            Label(change.label, systemImage: change.systemImage)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            }
        } header: {
            SectionHeader("Your answer over time")
        }
    }

    /// "ahead of the median" or "behind the median".
    private static func side(of gap: Decimal) -> String {
        gap >= 0 ? "ahead of the median" : "behind the median"
    }

    /// "The same accounts as the baseline, in EUR of 31 Dec 2025."
    private func unitsNote(_ comparison: PlanBaselineComparison) -> String {
        comparison.unitsNote(baseCurrency: library.baseCurrency, locale: locale)
    }

    /// "▼ −3 years".
    private func changeText(_ years: Int) -> String {
        let arrow = years < 0 ? "▼" : "▲"
        let sign = years < 0 ? AmountFormat.minus : "+"
        let count = abs(years)
        return "\(arrow) \(sign)\(count) \(count == 1 ? "year" : "years")"
    }

    // MARK: Actual vs baseline

    private var shownBaseline: PlanBaselineEntry? {
        baselines.first { $0.id == selectedBaseline } ?? baselines.first
    }

    private var baselineCard: some View {
        Card {
            if let shown = shownBaseline {
                let comparison = PlanBaselineComparison(baseline: shown.baseline, library: library.library,
                                                        asOf: library.asOfDate)
                PlanFanLegend(showsActual: true)
                FanChart(fan: comparison.fan, actual: comparison.actual, currency: comparison.currency)
                if let position = comparison.position {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Metrics.xs) {
                            DeltaText(position.gap, currency: comparison.currency)
                                .font(.subheadline.weight(.semibold))
                            Text(Self.side(of: position.gap))
                                .font(.subheadline)
                        }
                        Text(PlanBaselineComparison.percentileText(position))
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                } else {
                    Text("Your actual numbers appear here after the next check-in.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Text(unitsNote(comparison))
                    .font(.caption)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("A baseline remembers what you expected. Save one now, and later see how reality compares. "
                    + "One is also saved at the first check-in of each year.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                onSaveBaseline()
            } label: {
                Label("Save baseline…", systemImage: "bookmark")
            }
            .buttonStyle(.bordered)
            .disabled(!library.canEdit)
        } header: {
            SectionHeader("Actual vs baseline") {
                if !baselines.isEmpty {
                    // Never nil while there are baselines: a nil selection has no tag.
                    Picker("Baseline", selection: Binding(get: { selectedBaseline ?? baselines.first?.id },
                                                          set: { selectedBaseline = $0 })) {
                        ForEach(baselines) { entry in
                            Text(PlanBaselineComparison.label(for: entry.baseline, locale: locale))
                                .tag(Optional(entry.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }
        }
    }
}

/// One year of progress: plan assets from the check-in before it to its
/// last one, what you saved (against what the year's baseline expected)
/// and what markets did; how the earliest age moved, and what changed
/// besides your money; and where you ended against the year's baseline.
struct PlanProgressYearCard: View {
    let year: PlanProgressYear
    /// Chosen under the answer chart: outlined.
    var isSelected = false
    /// Shows the year's baseline in "Actual vs baseline".
    var onShowBaseline: () -> Void = {}

    @Environment(\.locale) private var locale

    /// "31 Dec 2025 – 30 Sep · 4 check-ins", "30 Sep · 1 check-in".
    private var span: String {
        let from = AmountFormat.shortDate(year.from, relativeTo: year.to, locale: locale)
        let to = AmountFormat.shortDate(year.to, locale: locale)
        let count = year.checkIns == 1 ? "1 check-in" : "\(year.checkIns) check-ins"
        return year.from == year.to ? "\(to) · \(count)" : "\(from) – \(to) · \(count)"
    }

    var body: some View {
        Card {
            money
            if year.answerTo != nil {
                answerRow
            }
            if let position = year.position, let baseline = year.baseline {
                baselineRow(position, baseline: baseline)
            }
        } header: {
            SectionHeader(year.title) {
                Text(span)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.accent, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        }
    }

    // MARK: Money

    private var money: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                Text("Plan assets")
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: Metrics.s)
                if year.from != year.to {
                    AmountText(year.change.start)
                        .foregroundStyle(Palette.secondaryInk)
                    Text(verbatim: "→")
                        .foregroundStyle(Palette.mutedInk)
                        .accessibilityLabel("to")
                }
                AmountText(year.change.end)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
            }
            .font(.subheadline)
            if year.from != year.to {
                changeRow("Saved", year.change.newMoney, planned: year.expectedSavings)
                changeRow("Markets", year.change.market)
                if year.change.other != 0 {
                    changeRow("Not explained", year.change.other)
                }
            }
            if !year.isComplete {
                Text("Some prices or exchange rates were missing: those holdings count as zero.")
                    .font(.caption)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Saved · planned 15.000 €   ▲ +12.400 €": a part of the change, with
    /// what the year's baseline planned for it.
    private func changeRow(_ title: String, _ amount: Decimal, planned: Decimal? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
            Text(title)
                .foregroundStyle(Palette.secondaryInk)
            if let planned {
                HStack(spacing: 2) {
                    Text("· planned")
                    AmountText(planned, tabular: false)
                }
                .font(.caption)
                .foregroundStyle(Palette.mutedInk)
            }
            Spacer(minLength: Metrics.s)
            DeltaText(amount)
        }
        .font(.subheadline)
    }

    // MARK: The answer

    private var answerRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                Text("Earliest age")
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: Metrics.s)
                Text(verbatim: ageText)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                if let change = year.ageChange, change != 0 {
                    Text(verbatim: Self.yearsText(change))
                        .monospacedDigit()
                        // An earlier age is good news.
                        .foregroundStyle(change < 0 ? Palette.positive : Palette.negative)
                }
            }
            .font(.subheadline)
            if !year.answerChanges.isEmpty {
                HStack(spacing: Metrics.m) {
                    ForEach(year.answerChanges, id: \.self) { change in
                        Label(change.label, systemImage: change.systemImage)
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    /// "55 → 54", "54", "none → 58".
    private var ageText: String {
        func age(_ point: PlanAnswerHistory.Point?) -> String { point?.earliestAge.map { String($0) } ?? "none" }
        guard let from = year.answerFrom, from != year.answerTo else { return age(year.answerTo) }
        return "\(age(from)) → \(age(year.answerTo))"
    }

    /// "▼ −1 year", "▲ +2 years".
    static func yearsText(_ years: Int) -> String {
        let arrow = years < 0 ? "▼" : "▲"
        let sign = years < 0 ? AmountFormat.minus : "+"
        let count = abs(years)
        return "\(arrow) \(sign)\(count) \(count == 1 ? "year" : "years")"
    }

    // MARK: Against the baseline

    private func baselineRow(_ position: PlanBaselineComparison.Position, baseline: PlanBaselineEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                Text("Against \(PlanBaselineComparison.label(for: baseline.baseline, locale: locale))")
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Metrics.s)
                DeltaText(position.gap, currency: year.positionCurrency)
                Text(position.gap >= 0 ? "ahead" : "behind")
                    .foregroundStyle(Palette.secondaryInk)
            }
            .font(.subheadline)
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text(PlanBaselineComparison.percentileText(position))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Metrics.s)
                Button("Show on the chart", action: onShowBaseline)
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }
        }
    }
}

#Preview("Progress") {
    PlanPreviewHost(model: AppModel.preview(planEngine: PlanPreviewEngine())) { session in
        PlanProgressView(session: session, onSaveBaseline: {})
    }
}
