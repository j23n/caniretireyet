import Model
import Planner
import SwiftUI

// The plan's chapters (UI.md, "The plan"): on iPhone a card with a row per
// chapter, each opening the chapter in a sheet; on the Mac and iPad a table,
// a row per chapter, the chosen one's words and settings under it.

/// A chapter as its row or table line says it.
struct PlanChapterLine: Identifiable {
    let index: Int
    let style: PlanChaptersModel.Style
    /// "Self-employed".
    let title: String
    /// "41 to 55", "now to 41", "67 on".
    let ages: String
    /// A month's money; `nil` without pay to show.
    let bar: PlanChapterStory.Bar?
    /// "5.100 € take-home, 3.000 € spent, 2.100 € saved a month".
    let summary: AmountSentence
    /// The one-offs in it: "New car 2031, 25.000 €"; empty without any.
    let oneOffs: [AmountSentence]

    var id: Int { index }

    static func lines(model: PlanChaptersModel, results: PlanResults?, words: PlanWords) -> [PlanChapterLine] {
        let plan = model.plan
        return model.chapters.chapters.indices.map { index in
            let chapter = model.chapters.chapters[index]
            let bar = PlanChapterStory.bar(chapter, model: model, results: results, words: words)
            let oneOffs = chapter.items.compactMap { item -> AmountSentence? in
                guard case .event(let event) = item, plan.events.indices.contains(event) else { return nil }
                let planned = plan.events[event]
                let when: String = switch planned.timing {
                case .year(let year): String(year)
                case .age(let age): "at \(age)"
                }
                let sentence: AmountSentence = "\(planned.name) \(when), \(words.amount(abs(planned.amount)))"
                return sentence
            }
            let summary = bar?.summary
                ?? (chapter.isRetired ? AmountSentence() : AmountSentence("Take-home pay not set yet"))
            return PlanChapterLine(index: index, style: model.style(of: chapter), title: model.title(of: chapter),
                                   ages: model.ages(ofChapterAt: index), bar: bar, summary: summary,
                                   oneOffs: oneOffs)
        }
    }
}

// MARK: - iPhone

/// The chapters on one card (iPhone): a row each, its number in the colour
/// of its kind of life, its name, its ages on the right, a thin bar of where
/// its money goes and a line of figures under it. A row opens the chapter.
struct PlanChapterRows: View {
    let lines: [PlanChapterLine]
    var onOpen: (Int) -> Void = { _ in }

    var body: some View {
        CardRows {
            ForEach(lines) { line in
                Button {
                    onOpen(line.index)
                } label: {
                    row(line)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows what happens in it")
            }
        }
    }

    private func row(_ line: PlanChapterLine) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
            }
            VStack(alignment: .leading, spacing: 6) {
                if let bar = line.bar {
                    PlanChapterMoneyBar(bar: bar)
                }
                if !line.summary.isEmpty {
                    AmountSentenceText(line.summary)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 34)
            .padding(.top, Metrics.s)
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One chapter in a sheet (iPhone): its name and span as the title, then
/// what happens in it and where its money goes, the milestones along the
/// way, what can go wrong, and its settings. The sheet opens the settings'
/// own sheets itself.
struct PlanChapterSheet: View {
    let session: PlanSession

    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PlanEditTarget?
    @State private var showsTargetMix = false

    var body: some View {
        @Bindable var session = session
        let derived = session.derived(locale: locale)
        let words = PlanWords(currency: session.currency, locale: locale)
        let model = derived.chapters
        let index: Int? = model.flatMap { (model: PlanChaptersModel) -> Int? in
            let count = model.chapters.chapters.count
            return count == 0 ? nil : min(session.selectedChapter(in: model) ?? 0, count - 1)
        }
        NavigationStack {
            ScrollView {
                if let model, let index {
                    PlanChapterDetail(
                        model: model, index: index,
                        story: PlanChapterStory(chapterAt: index, in: model, results: session.state.results,
                                                words: words),
                        plan: $session.editablePlan, words: words, issues: session.inputIssues,
                        canEdit: session.canEdit, editing: $editing,
                        milestones: milestones(derived.timeline, index: index),
                        milestoneText: PlanMilestoneText(currency: session.currency, locale: locale),
                        onOpen: open, onUsePlanAge: { session.selectFocus(nil) })
                    .padding(.horizontal, Metrics.l)
                    .padding(.vertical, Metrics.s)
                }
            }
            .background(Palette.page)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let model, let index {
                        VStack(spacing: 0) {
                            Text(model.title(of: model.chapters.chapters[index]))
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text(model.agesAndYears(ofChapterAt: index))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(Palette.secondaryInk)
                                .lineLimit(1)
                        }
                        .privacySensitiveInFeedback()
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { target in
                PlanItemSheet(session: session, target: target, issues: session.inputIssues)
            }
            .sheet(isPresented: $showsTargetMix) {
                PlanTargetMixSheet(session: session)
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private func milestones(_ timeline: PlanTimeline?, index: Int) -> [ProjectedMilestone] {
        guard let timeline, timeline.cards.indices.contains(index) else { return [] }
        return timeline.cards[index].milestones
    }

    private func open(_ sheet: PlanSettingSheet) {
        guard let plan = session.plan else { return }
        if sheet.isTargetMix {
            showsTargetMix = true
        } else {
            editing = PlanEditTarget(sheet, in: plan)
        }
    }
}

// MARK: - A chapter

/// A chapter's words and settings, as cards (UI.md, "The plan"): what
/// happens in it, in words that only read, with a month's money as a bar;
/// the milestones the median future reaches in it; what can go wrong; and
/// *In this chapter*, its settings, where the plan changes: every input
/// that starts in it, once, then *Add to This Chapter*. Side by side on the
/// Mac and iPad (`columns`); on iPhone the settings follow.
struct PlanChapterDetail: View {
    let model: PlanChaptersModel
    let index: Int
    let story: PlanChapterStory
    @Binding var plan: PlanDocument
    let words: PlanWords
    let issues: PlanInputIssues
    var canEdit = true
    @Binding var editing: PlanEditTarget?
    /// The milestones the median future reaches in the chapter.
    var milestones: [ProjectedMilestone] = []
    let milestoneText: PlanMilestoneText
    /// The reading and the settings side by side.
    var columns = false
    /// Opens a setting's sheet.
    var onOpen: (PlanSettingSheet) -> Void = { _ in }
    var onUsePlanAge: () -> Void = {}

    /// The milestones listed before "And N more ahead."
    private static let shownMilestones = 4

    private var chapter: PlanChapter { model.chapters.chapters[index] }

    var body: some View {
        if columns {
            HStack(alignment: .top, spacing: Metrics.l) {
                reading
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                settings
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.l) {
                reading
                settings
            }
        }
    }

    /// What happens, the milestones along the way, and what can go wrong.
    private var reading: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            VStack(alignment: .leading, spacing: Metrics.m) {
                PlanStoryText(runs: story.story)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                if let bar = story.bar {
                    PlanMonthBarView(bar: bar)
                }
            }
            .padding(.horizontal, Metrics.l)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            if !milestones.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    PlanPartLabel("Along the way, typically")
                    CardRows {
                        ForEach(Array(milestones.prefix(Self.shownMilestones))) { item in
                            CardRow {
                                AmountSentenceText(milestoneText.name(item.milestone))
                            } value: {
                                Text(PlanMilestoneText.when(item.date))
                                    .monospacedDigit()
                                    .privacySensitiveInFeedback()
                            }
                        }
                    }
                    if milestones.count > Self.shownMilestones {
                        Text("And \(milestones.count - Self.shownMilestones) more ahead.")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                            .padding(.horizontal, Metrics.xs)
                    }
                }
            }
            if !story.risks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    PlanPartLabel("What can go wrong")
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        ForEach(story.risks, id: \.self) { risk in
                            Label {
                                Text(risk)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .privacySensitiveInFeedback()
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Palette.orangeStroke)
                            }
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                        }
                    }
                    .padding(Metrics.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
                }
            }
        }
    }

    /// Every input that starts in the chapter, once; what carries on into
    /// it; and *Add to This Chapter*.
    private var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                PlanPartLabel("In this chapter")
                Spacer(minLength: Metrics.s)
                Text("A month, in \(PlanMoney.todaysMoney(words.currency))")
                    .font(.caption)
                    .foregroundStyle(Palette.mutedInk)
                    .lineLimit(1)
            }
            let rows = PlanChapterSettings.rows(for: chapter.items, model: model, issues: issues, words: words)
            if rows.isEmpty {
                Text("Nothing starts in this chapter.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(Metrics.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
            } else {
                PlanSettingsList(rows: rows, plan: $plan, model: model, canEdit: canEdit, onSheet: onOpen,
                                 onUsePlanAge: onUsePlanAge)
            }
            if let continuing = model.continuing(in: chapter) {
                Text(continuing)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metrics.xs)
                    .privacySensitiveInFeedback()
            }
            PlanChapterAddMenu(chapter: chapter, model: model, plan: plan, editing: $editing)
                .disabled(!canEdit)
                .padding(.top, 6)
        }
    }
}

// MARK: - Mac and iPad

/// The chapters as a table (the Mac and iPad): a line each with its number,
/// name and ages, a month's take-home pay, spending and saving (what comes
/// from savings below zero, in orange), where its money goes as a bar, and
/// its one-offs when there's room. Clicking a line chooses the chapter,
/// whose words and settings follow the table.
struct PlanChapterTable<Footer: View>: View {
    let lines: [PlanChapterLine]
    let selection: Int
    let words: PlanWords
    /// Whether the one-offs have a column.
    var showsOneOffs = true
    var onSelect: (Int) -> Void = { _ in }
    @ViewBuilder var footer: Footer

    private static var moneyWidth: CGFloat { 84 }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                ForEach(lines) { line in
                    if line.index > 0 {
                        Divider()
                    }
                    Button {
                        onSelect(line.index)
                    } label: {
                        row(line)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(line.index == selection ? .isSelected : [])
                }
            }
            HStack(spacing: Metrics.s) {
                footer
            }
            .controlSize(.small)
        } header: {
            SectionHeader("Chapters") {
                Text("A month, in today's money")
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.s) {
            Color.clear.frame(width: 18, height: 1)
            Text("Chapter").frame(minWidth: 70, maxWidth: .infinity, alignment: .leading)
            Text("Ages").frame(width: 72, alignment: .leading)
            Text("Take-home").frame(width: Self.moneyWidth, alignment: .trailing)
            Text("Spending").frame(width: Self.moneyWidth, alignment: .trailing)
            Text("Saved").frame(width: Self.moneyWidth, alignment: .trailing)
            Text("Where it goes").frame(width: 100, alignment: .leading)
            if showsOneOffs {
                Text("One-offs").frame(minWidth: 70, maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.caption)
        .foregroundStyle(Palette.mutedInk)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, Metrics.xs)
        .accessibilityHidden(true)
    }

    private func row(_ line: PlanChapterLine) -> some View {
        let isSelected = line.index == selection
        return HStack(spacing: Metrics.s) {
            Text(verbatim: "\(line.index + 1)")
                .monospacedDigit()
                .foregroundStyle(Palette.mutedInk)
                .frame(width: 18, alignment: .leading)
            Text(line.title)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 70, maxWidth: .infinity, alignment: .leading)
                .privacySensitiveInFeedback()
            Text(line.ages)
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .frame(width: 72, alignment: .leading)
                .privacySensitiveInFeedback()
            money(line.bar?.takeHome)
                .frame(width: Self.moneyWidth, alignment: .trailing)
            money(line.bar?.spending)
                .frame(width: Self.moneyWidth, alignment: .trailing)
            money(line.bar?.saved)
                .frame(width: Self.moneyWidth, alignment: .trailing)
            Group {
                if let bar = line.bar {
                    PlanChapterMoneyBar(bar: bar, height: 6)
                } else {
                    Color.clear.frame(height: 6)
                }
            }
            .frame(width: 100)
            if showsOneOffs {
                Group {
                    if line.oneOffs.isEmpty {
                        Text("none")
                            .foregroundStyle(Palette.mutedInk)
                    } else {
                        AmountSentenceText(line.oneOffs.joined(separator: "; "))
                            .foregroundStyle(Palette.ink)
                    }
                }
                .frame(minWidth: 70, maxWidth: .infinity, alignment: .leading)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(isSelected ? Palette.accent.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// A month's amount: "1.200 €", or "−3.000 €" in orange when it comes
    /// from savings; "none" when there's nothing.
    @ViewBuilder
    private func money(_ value: Double?) -> some View {
        if let value, abs(value) >= 0.5 {
            let amount = Decimal(wholeNumber: value)
            AmountSentenceText(value < 0 ? words.signedAmount(amount) : words.amount(amount))
                .monospacedDigit()
                .foregroundStyle(value < 0 ? Palette.orangeStroke : Palette.ink)
        } else {
            Text(verbatim: value == nil ? "—" : "none")
                .foregroundStyle(Palette.mutedInk)
        }
    }
}
