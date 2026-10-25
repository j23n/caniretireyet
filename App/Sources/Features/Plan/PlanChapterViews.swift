import Model
import Planner
import SwiftUI

// The plan's chapters (UI.md, "Your life ahead"): a chapter as Ahead's
// line says it, and a chapter in a sheet, its settings and its words.

/// A chapter as *Your life ahead* says it.
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

/// One chapter in a sheet: its name and span as the title, then its
/// settings, where the plan changes, then what happens in it and where its
/// money goes, the milestones along the way and what can go wrong. The
/// sheet opens the settings' own sheets itself, each with *With this
/// change*.
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
/// that starts in it, once, then *Add to This Chapter*. Side by side with
/// `columns`; else the settings come first.
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
                settings
                reading
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
