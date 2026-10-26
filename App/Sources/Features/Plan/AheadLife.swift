import Glance
import Model
import Planner
import SwiftUI

// *Your life ahead* on Ahead (UI.md, "Your life ahead"): the plan's
// chapters and what changes along the way, in order, down a line, with the
// day you stop working on it and the plan's end after the last chapter.

/// *Your life ahead*: its title with *Add*, a line on what it is, then the
/// chapters down a line. Each chapter is a card: its number and name, its
/// ages, its month's money in words, and the money typically there as it
/// starts ("Today" for the first). What changes in it (other income,
/// saving into an account, a one-off, later spending, a change of mix)
/// follows it on a card of its own, a row each. Before the first
/// retired chapter, *You stop working* (``AheadStopCard``); after the last,
/// the plan's end. A chapter opens in a sheet, a change in its own, the
/// stop and the end in their small editors. On the Mac and iPad
/// (`columns`) the cards flow in columns, in the same order.
struct AheadLifeSection: View {
    let session: PlanSession
    let model: PlanChaptersModel
    let results: PlanResults?
    let words: PlanWords
    var columns = false
    @Binding var editing: PlanEditTarget?
    var onChapter: (Int) -> Void = { _ in }
    var onSheet: (PlanSettingSheet) -> Void = { _ in }
    var onTargetMix: () -> Void = {}

    /// One stop down the line.
    enum Stop: Identifiable {
        case chapter(Int)
        /// What changes in the chapter at the index.
        case changes(Int, [PlanSettingRow])
        case stopWorking
        case end

        var id: String {
            switch self {
            case .chapter(let index): "chapter-\(index)"
            case .changes(let index, _): "changes-\(index)"
            case .stopWorking: "stop"
            case .end: "end"
            }
        }
    }

    private var stops: [Stop] {
        let chapters = model.chapters.chapters
        let firstRetired = chapters.firstIndex { $0.isRetired }
        var stops: [Stop] = []
        for index in chapters.indices {
            if index == firstRetired, index > 0 { stops.append(.stopWorking) }
            stops.append(.chapter(index))
            let rows = PlanChapterSettings.rows(for: chapters[index].items.filter(Self.isChange), model: model,
                                                issues: session.inputIssues, words: words, namesWork: true)
            if !rows.isEmpty { stops.append(.changes(index, rows)) }
        }
        stops.append(.end)
        return stops
    }

    /// Whether an input is a change along the way: other income,
    /// contributions, one-offs, later spending and changes of mix. Not
    /// work, nor pensions, which their chapters are (their sheets list
    /// them), nor what every chapter has.
    static func isChange(_ item: PlanChapter.Item) -> Bool {
        switch item {
        case .income, .contribution, .event, .spendingPhase, .targetMixStep: true
        case .work, .pension, .retirement, .workingSpending, .retiredSpending, .targetMix, .end: false
        }
    }

    var body: some View {
        let lines = PlanChapterLine.lines(model: model, results: results, words: words)
        let stops = self.stops
        VStack(alignment: .leading, spacing: Metrics.s) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text("Your life ahead")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Metrics.s)
                addMenu
            }
            .padding(.horizontal, Metrics.xs)
            .padding(.top, 6)
            Text("The chapters and what changes along the way, in order. Tap one to change it; the chart redraws.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metrics.xs)
            if columns {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Metrics.m, alignment: .top)],
                          alignment: .leading, spacing: Metrics.m) {
                    ForEach(stops) { stop in
                        card(stop, lines: lines)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { offset, stop in
                        HStack(alignment: .top, spacing: Metrics.m) {
                            rail(stop, lines: lines, isLast: offset == stops.count - 1)
                            card(stop, lines: lines)
                                .padding(.bottom, Metrics.s)
                        }
                        // As tall as the card, so the line reaches the next dot.
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// *Add*: a work phase, a pension, other income, a contribution, an
    /// event, later spending or a change of mix, each in the chapter it
    /// starts in.
    private var addMenu: some View {
        PlanAddMenu(model: model, plan: session.editablePlan, editing: $editing, onTargetMix: onTargetMix) {
            Text("Add")
                .font(.body)
                .foregroundStyle(Palette.accent)
                .padding(.vertical, Metrics.s)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(!session.canEdit)
    }

    // MARK: The line

    /// The line down the left: a dot in the chapter's colour, a small one
    /// for its changes, the accent for when you stop, a ring at the end.
    private func rail(_ stop: Stop, lines: [PlanChapterLine], isLast: Bool) -> some View {
        VStack(spacing: 0) {
            Group {
                switch stop {
                case .chapter(let index):
                    Circle()
                        .fill(lines.indices.contains(index) ? PlanChapterColors.color(lines[index].style)
                              : Palette.mutedInk)
                        .frame(width: 12, height: 12)
                case .changes:
                    Circle()
                        .strokeBorder(Palette.mutedInk, lineWidth: 1.5)
                        .frame(width: 8, height: 8)
                        .padding(2)
                case .stopWorking:
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 12, height: 12)
                case .end:
                    Circle()
                        .strokeBorder(Palette.ink, lineWidth: 2)
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.top, 18)
            if !isLast {
                Rectangle()
                    .fill(Palette.border)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 12)
        .accessibilityHidden(true)
    }

    // MARK: The cards

    @ViewBuilder
    private func card(_ stop: Stop, lines: [PlanChapterLine]) -> some View {
        @Bindable var session = session
        switch stop {
        case .chapter(let index):
            if lines.indices.contains(index) {
                AheadChapterCard(line: lines[index], money: money(atStartOf: index), currency: words.currency,
                                 onOpen: { onChapter(index) })
            }
        case .changes(_, let rows):
            PlanSettingsList(rows: rows, plan: $session.editablePlan, model: model, canEdit: session.canEdit,
                             onSheet: onSheet)
        case .stopWorking:
            AheadStopCard(session: session, model: model, results: results, words: words)
        case .end:
            AheadEndCard(session: session, model: model, results: results, words: words)
        }
    }

    /// The money typically there as the chapter at `index` starts: plan
    /// assets now for the first, else at the end of the one before.
    private func money(atStartOf index: Int) -> AheadChapterCard.Money? {
        if index == 0 {
            return results?.portfolio.first.map { AheadChapterCard.Money(label: "Today", value: $0.p50) }
        }
        guard let outcome = model.outcomes[index - 1] else { return nil }
        let age = model.chapters.chapters[index].ages.lowerBound
        return AheadChapterCard.Money(label: "At \(age), typically", value: outcome.median)
    }
}

/// A chapter on *Your life ahead*: its number in the colour of its kind of
/// life and its name, its ages with a chevron, its month's money in words,
/// and the money typically there as it starts. It opens the chapter.
struct AheadChapterCard: View {
    struct Money {
        /// "Today", "At 41, typically".
        var label: String
        var value: Double
    }

    let line: PlanChapterLine
    let money: Money?
    let currency: CurrencyCode
    var onOpen: () -> Void = {}

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Metrics.s) {
                HStack(alignment: .center, spacing: 10) {
                    PlanChapterBadge(number: line.index + 1, style: line.style)
                    Text(line.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .privacySensitiveInFeedback()
                    Spacer(minLength: Metrics.s)
                    Text(line.ages)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(1)
                        .fixedSize()
                        .privacySensitiveInFeedback()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.mutedInk)
                        .accessibilityHidden(true)
                }
                if !line.summary.isEmpty {
                    AmountSentenceText(line.summary)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(line.oneOffs.enumerated()), id: \.offset) { _, oneOff in
                    AmountSentenceText("🗓️ " + oneOff)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let money {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                        Text(verbatim: money.label)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                            .privacySensitiveInFeedback()
                        Spacer(minLength: Metrics.s)
                        AmountText(Decimal(wholeNumber: money.value), currency: currency)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            .padding(.horizontal, Metrics.l)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows what happens in it")
    }
}

/// *You stop working* on the line (UI.md, "Your life ahead"): the age and
/// the day, the money typically there then, where 8 in 10 futures are, and
/// a stepper to stop a year sooner or later, each side with how many of 10
/// futures last then ("‹ 62: 8 in 10", "64: 10 in 10 ›"). Stepping sets
/// the plan's own age, or the lever's while it's moved; the rest opens
/// when work stops in its small editor.
struct AheadStopCard: View {
    let session: PlanSession
    let model: PlanChaptersModel
    let results: PlanResults?
    let words: PlanWords

    @Environment(\.locale) private var locale
    @State private var showsEditor = false

    private var age: Int { model.retirementAge }

    /// The results' numbers for the age the chapters are cut at.
    private var focus: PlanFocusDetails? {
        guard let focus = results?.details.focus, focus.age == age else { return nil }
        return focus
    }

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: Metrics.s) {
            Button {
                showsEditor = true
            } label: {
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                        Text("You stop working")
                            .font(.headline)
                            .foregroundStyle(Palette.accent)
                        Spacer(minLength: Metrics.s)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.mutedInk)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: when)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .privacySensitiveInFeedback()
                    if let median = focus?.medianAtRetirement {
                        AmountSentenceText("\(words.amount(Decimal(wholeNumber: median))) when you stop, typically.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let range {
                        AmountSentenceText("8 in 10 futures: \(words.amount(Decimal(wholeNumber: range.lowerBound))) "
                                           + "to \(words.amount(Decimal(wholeNumber: range.upperBound)))")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!session.canEdit)
            .accessibilityHint("Changes when work stops")
            .popover(isPresented: $showsEditor) {
                PlanValueEditor(value: .retirementAge, plan: $session.editablePlan, model: model,
                                onUsePlanAge: { session.selectFocus(nil) })
            }
            stepper
        }
        .padding(Metrics.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accent.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.accent.opacity(0.35), lineWidth: 1)
        }
    }

    /// "At 63, 27 March 2051", or the year without a day.
    private var when: String {
        if let day = focus?.retirementDate {
            return "At \(age), \(GlanceText.lastMonday(day, locale: locale))"
        }
        return "At \(age), in \(model.retirementYear)"
    }

    /// Where 8 in 10 futures are as work stops: at the end of the last
    /// chapter you work in.
    private var range: ClosedRange<Double>? {
        let chapters = model.chapters.chapters
        guard let first = chapters.firstIndex(where: { $0.isRetired }), first > 0,
              let outcome = model.outcomes[first - 1] else { return nil }
        return outcome.low...max(outcome.low, outcome.high)
    }

    /// A year sooner and a year later, each with how many of 10 futures
    /// last then.
    private var stepper: some View {
        let points = results?.successByAge ?? []
        let sooner = points.first { $0.age == age - 1 }
        let later = points.first { $0.age == age + 1 }
        return HStack(spacing: Metrics.s) {
            stepButton(sooner, age: age - 1, label: { "‹ \($0)" })
            Spacer(minLength: Metrics.s)
            stepButton(later, age: age + 1, label: { "\($0) ›" })
        }
        .font(.subheadline.weight(.semibold))
        .privacySensitiveInFeedback()
    }

    /// Stops work at `age`: under a lever's age, the lever moves; else the
    /// plan's own age, after letting go of an age chosen on the tiles.
    private func step(to age: Int) {
        switch model.ageSource {
        case .whatIf:
            session.set(.retirementAge, to: Double(age))
        case .chosen:
            session.selectFocus(nil)
            session.edit { $0.retirement.age = .age(age) }
        default:
            session.edit { $0.retirement.age = .age(age) }
        }
    }

    /// Whether work can stop at `age`: from today's age to the year before
    /// the plan ends, and within the lever's range under a lever's age.
    private func canStep(to age: Int) -> Bool {
        guard session.canEdit, age >= (results?.details.currentAge ?? 0), age < model.plan.effectiveEndAge else {
            return false
        }
        guard model.ageSource == .whatIf, let range = session.whatIfModel?.range(.retirementAge) else { return true }
        return range.contains(Double(age))
    }

    private func stepButton(_ point: SuccessPoint?, age: Int, label: (String) -> String) -> some View {
        let text = point.map { "\(age): \(PlanTimelineText.tenths($0.success)) in 10" } ?? "\(age)"
        return Button {
            step(to: age)
        } label: {
            Text(verbatim: label(text))
                .monospacedDigit()
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .disabled(!canStep(to: age))
        .accessibilityLabel(Text(verbatim: "Stop at \(text)"))
    }
}

/// The plan's end on the line: "95 · The plan's end", what's typically
/// left, and how often money runs out first. It opens the end age's editor.
struct AheadEndCard: View {
    let session: PlanSession
    let model: PlanChaptersModel
    let results: PlanResults?
    let words: PlanWords

    @State private var showsEditor = false

    var body: some View {
        @Bindable var session = session
        let endAge = results?.details.endAge ?? model.plan.effectiveEndAge
        Button {
            showsEditor = true
        } label: {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                    Text(verbatim: "\(endAge) · The plan's end")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .privacySensitiveInFeedback()
                    Spacer(minLength: Metrics.s)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.mutedInk)
                        .accessibilityHidden(true)
                }
                if let sentence = sentence {
                    AmountSentenceText(sentence)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Metrics.l)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!session.canEdit)
        .accessibilityHint("Changes the age the plan ends at")
        .popover(isPresented: $showsEditor) {
            PlanValueEditor(value: .endAge, plan: $session.editablePlan, model: model)
        }
    }

    /// "350.000 € left, typically. Runs out first in 1 of 10 futures."
    private var sentence: AmountSentence? {
        guard let last = model.chapters.chapters.indices.last, let outcome = model.outcomes[last] else { return nil }
        var sentence: AmountSentence = "\(words.amount(Decimal(wholeNumber: outcome.median))) left, typically."
        if let success = results?.details.focus.success, success < 0.995 {
            sentence += " Runs out first in \(GlanceText.futures(((1 - success) * 100).rounded() / 100)) futures."
        }
        return sentence
    }
}
