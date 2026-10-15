import Charts
import Glance
import Model
import Planner
import SwiftUI
import Tracker

/// *Your year* (UI.md, "Your year"): a year of the main plan looked back
/// on. Last year in January (the note on 3 January opens it), else this
/// year so far. Readiness from the year's start to its end as a ring, how
/// the answer moved, what you saved and markets did as time of the life you
/// plan, the age at each check-in, your money against what January's plan
/// expected with the milestones passed, month by month, and the year ahead.
/// Present it inside a `NavigationStack`.
struct YourYearScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.baseCurrency) private var currency
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            if let plan = library.mainPlan, let review = review(of: plan) {
                content(review, plan: plan)
                    .padding(Metrics.l)
                    .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView(
                    "No year to look back on yet", systemImage: "calendar",
                    description: Text("Your year shows once the main plan has an answer from a check-in."))
            }
        }
        .background(Palette.page)
        .navigationTitle("Your Year")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func review(of plan: PlanDocument) -> YearReview? {
        let progress = plans.planProgress(of: plan.id, document: plan)
        guard let year = YearReview.year(on: .today(), progress: progress) else { return nil }
        return YearReview(progress: progress, year: year, valuator: library.valuator)
    }

    private func content(_ review: YearReview, plan: PlanDocument) -> some View {
        let text = PlanMilestoneText(currency: currency, locale: locale)
        let spending = MilestoneLadder.spending(of: plan)
        return VStack(alignment: .leading, spacing: Metrics.xl) {
            hero(review)
            tiles(review, spending: spending)
            let points = review.answers.map {
                JourneyPoint(date: $0.date, earliestAge: $0.earliestAge, readiness: $0.readiness?.doubleValue)
            }
            if points.filter({ $0.earliestAge != nil }).count >= 2 {
                Card("The age you could retire at") {
                    AgeStepChart(points: points, height: 130)
                }
            }
            if let chart = review.chart, chart.actual.count >= 2 {
                Card("Your money through the year") {
                    VStack(alignment: .leading, spacing: Metrics.m) {
                        YearMoneyChart(chart: chart)
                        ForEach(review.reached) { reached in
                            Label {
                                let month = GlanceText.month(reached.date, relativeTo: review.year.to,
                                                             locale: locale)
                                AmountSentenceText(AmountSentence(month + ": ") + text.reached(reached.milestone))
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: "flag.fill")
                                    .foregroundStyle(Palette.accent)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            if review.months.count >= 2 {
                Card("Month by month") {
                    MonthlyMovesChart(months: review.months)
                }
            }
            yearAhead(plan: plan, text: text)
            Button("Open \(String(review.year.year)) on Progress") {
                navigation.sheet = nil
                navigation.showPlan(at: PlanRoute(part: .progress))
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: The year in a line

    /// "12 check-ins · January to December", "Your 2026", the ring with
    /// readiness and where it started, the answer and your last Monday.
    private func hero(_ review: YearReview) -> some View {
        let year = review.year
        return VStack(alignment: .leading, spacing: Metrics.m) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(verbatim: Wording.count(year.checkIns, "check-in") + " · " + span(year))
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.secondaryInk)
                Text(verbatim: "Your \(year.year)")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.ink)
            }
            HStack(alignment: .center, spacing: Metrics.l) {
                if let to = review.readinessTo {
                    ZStack {
                        ReadinessRing(fraction: to, lineWidth: 12, laps: true)
                        VStack(spacing: 0) {
                            Text(verbatim: percent(to))
                                .font(.title.bold())
                                .monospacedDigit()
                            Text(verbatim: review.readinessFrom.map { "ready, from \(percent($0))" } ?? "ready")
                                .font(.caption)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                    .frame(width: 132, height: 132)
                }
                VStack(alignment: .leading, spacing: Metrics.s) {
                    if let answer = answerSentence(review) {
                        Text(verbatim: answer)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                    }
                    if let lastMonday = lastMondaySentence {
                        Text(verbatim: lastMonday)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .privacySensitiveInFeedback()
        .accessibilityElement(children: .combine)
    }

    /// "January to December", "January to September" for a year so far.
    private func span(_ year: PlanProgressYear) -> String {
        let from = year.from.year < year.year ? CalendarDate.firstDay(ofYear: year.year) : year.from
        let to = year.lastCheckIn ?? year.to
        return "\(AmountFormat.monthName(from, locale: locale)) to \(AmountFormat.monthName(to, locale: locale))"
    }

    /// "You could retire at 54, 2 years sooner than a year ago."
    private func answerSentence(_ review: YearReview) -> String? {
        guard let age = review.year.answerTo?.earliestAge else { return nil }
        var sentence = "You could retire at \(age)"
        if let change = review.year.ageChange {
            let years = abs(change)
            let span = years == 1 ? "a year" : "\(years) years"
            sentence += change == 0 ? ", as a year ago"
                : ", \(span) \(change < 0 ? "sooner" : "later") than a year ago"
        }
        return sentence + "."
    }

    /// "Your last Monday: about 15 years away, in March 2042".
    private var lastMondaySentence: String? {
        guard let answer = plans.mainHeadline, !answer.canRetireNow, let date = answer.earliestDate,
              let countdown = RetirementCountdown(from: .today(), to: date)
        else { return nil }
        return "Your last Monday: \(countdown.awayText), in \(GlanceText.monthAndYear(date, locale: locale))"
    }

    private func percent(_ readiness: Double) -> String {
        AmountFormat.percent(Readiness.shown(readiness), digits: 0, locale: locale)
    }

    // MARK: Tiles

    /// "You saved 8 months of the life you plan" and what markets did, as time.
    @ViewBuilder
    private func tiles(_ review: YearReview, spending: Decimal?) -> some View {
        let saved = spending.flatMap { SpendingTime(amount: review.saved, yearlySpending: $0) }
        let markets = spending.flatMap { SpendingTime(amount: abs(review.markets), yearlySpending: $0) }
        if saved != nil || markets != nil {
            HStack(alignment: .top, spacing: Metrics.m) {
                if let saved {
                    tile("You saved", value: saved.text.replacingOccurrences(of: "about ", with: ""),
                         detail: "of the life you plan", color: Palette.accent)
                }
                if let markets {
                    tile("Markets", value: markets.text.replacingOccurrences(of: "about ", with: ""),
                         detail: review.markets >= 0 ? "added" : "took", color: Palette.orange)
                }
            }
        }
    }

    private func tile(_ title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(title)
            } icon: {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            Text(verbatim: value)
                .font(.title2.bold())
                .foregroundStyle(Palette.ink)
                .privacySensitiveInFeedback()
            Text(verbatim: detail)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: The year ahead

    /// The next milestone and how far there, and when it's typically reached.
    @ViewBuilder
    private func yearAhead(plan: PlanDocument, text: PlanMilestoneText) -> some View {
        let milestones = PlanMilestones(plan: plan, library: library.library, valuator: library.valuator,
                                        asOf: library.asOfDate, results: plans.latestResults(of: plan.id))
        if let next = milestones.next {
            Card("The year ahead") {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    HStack {
                        Label {
                            AmountSentenceText(text.name(next.milestone))
                        } icon: {
                            Image(systemName: "flag")
                                .foregroundStyle(Palette.accent)
                        }
                        .font(.headline)
                        Spacer(minLength: Metrics.s)
                        Text(verbatim: text.progress(next))
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                            .privacySensitiveInFeedback()
                    }
                    ShareBarTrack(share: next.progress)
                    if let caption = text.caption(next, date: milestones.nextDate) {
                        AmountSentenceText(caption)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
            }
        }
    }
}

/// Plan assets through the year against what its baseline expected (the
/// same lines as the year's card on Progress), with the milestones passed
/// as flags. No amount axis: the lines compare, the amounts stay hidden.
private struct YearMoneyChart: View {
    let chart: PlanYearChart

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            HStack(spacing: Metrics.m) {
                legend("Plan assets", Palette.accent, dashed: false)
                if !chart.expected.isEmpty {
                    legend("January expected", Palette.mutedInk, dashed: true)
                }
            }
            .font(.caption)
            .foregroundStyle(Palette.secondaryInk)
            Chart {
                ForEach(chart.expected) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Expected", point.value),
                             series: .value("Line", "Expected"))
                        .foregroundStyle(Palette.mutedInk)
                        .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, dash: [4, 4]))
                }
                ForEach(chart.actual) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Plan assets", point.value),
                             series: .value("Line", "Plan assets"))
                        .foregroundStyle(Palette.accent)
                        .lineStyle(StrokeStyle(lineWidth: Metrics.lineWidth, lineCap: .round, lineJoin: .round))
                }
                ForEach(chart.milestones) { milestone in
                    if let level = assets(on: milestone.date.dateValue) {
                        PointMark(x: .value("Date", milestone.date.dateValue), y: .value("Plan assets", level))
                            .symbol {
                                Image(systemName: "flag.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Palette.accent)
                            }
                    }
                }
            }
            .chartXScale(domain: chart.start...chart.end)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 3)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.month(.abbreviated))
                                .font(.caption2)
                                .foregroundStyle(Palette.mutedInk)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 160)
            .privacySensitiveInFeedback()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: summary))
    }

    /// Plan assets on `date`, between the line's points.
    private func assets(on date: Date) -> Double? {
        guard let after = chart.actual.firstIndex(where: { $0.date >= date }) else { return chart.actual.last?.value }
        guard after > 0 else { return chart.actual[after].value }
        let from = chart.actual[after - 1]
        let to = chart.actual[after]
        let span = to.date.timeIntervalSince(from.date)
        let t = span > 0 ? date.timeIntervalSince(from.date) / span : 1
        return from.value + (to.value - from.value) * t
    }

    private var summary: String {
        let ahead = chart.gaps.allSatisfy(\.ahead)
        let behind = chart.gaps.allSatisfy { !$0.ahead }
        var text = "Plan assets through the year"
        if !chart.gaps.isEmpty {
            text += ahead ? ", above what January expected all year"
                : behind ? ", below what January expected all year" : ", around what January expected"
        }
        if !chart.milestones.isEmpty {
            text += "; " + Wording.count(chart.milestones.count, "milestone") + " passed"
        }
        return text + "."
    }

    private func legend(_ title: String, _ color: Color, dashed: Bool) -> some View {
        HStack(spacing: Metrics.xs) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 5))
                path.addLine(to: CGPoint(x: 16, y: 5))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [4, 3] : []))
            .frame(width: 16, height: 10)
            Text(title)
        }
    }
}
