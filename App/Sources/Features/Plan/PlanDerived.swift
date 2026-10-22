import Foundation
import Model
import Planner
import Tracker

/// What the plan's pages show that's worked out from the plan as shown, the
/// library and the results shown: its chapters, the strip of them, the
/// milestones ahead and where the latest check-in stands. `PlanSession`
/// works it out once for each change of those (``PlanSession/derived(locale:)``),
/// not each time a page draws.
struct PlanDerived {
    /// The plan's chapters (UI.md, "The plan"), cut at the age the charts
    /// are for, with where the money stands from the results shown; `nil`
    /// without a plan or a birth date.
    let chapters: PlanChaptersModel?
    /// The chapters as cards on a strip; `nil` without chapters.
    let timeline: PlanTimeline?
    /// The largest month among the chapters, so their bars compare.
    let barMaximum: Double
    /// The milestones from the results shown, with those reached; `nil`
    /// without a plan.
    let milestones: PlanMilestones?
    /// Where the latest check-in stands against its year's baseline, and
    /// the coast point line, as the Overview's *On track?* has them; `nil`
    /// without a plan.
    let onTrack: OverviewOnTrack?

    /// - Parameter reached: the milestones reached (``PlanSession/progress``),
    ///   which are neither next nor ahead again.
    init(plan: PlanDocument?, library: Library, valuator: Valuator, results: PlanResults?, chosenAge: Int?,
         whatIfAge: Int?, asOf: CalendarDate, reached: [ReachedMilestone], locale: Locale) {
        let currency = library.settings.baseCurrency
        let milestones = plan.map {
            PlanMilestones(plan: $0, library: library, valuator: valuator, asOf: asOf, results: results,
                           reached: reached)
        }
        let chapters = plan.flatMap {
            PlanChaptersModel(plan: $0, library: library, results: results, chosenAge: chosenAge,
                              whatIfAge: whatIfAge, recordedAge: library.headlines(for: $0.id).last?.earliestAge,
                              today: asOf)
        }
        self.milestones = milestones
        self.chapters = chapters
        timeline = chapters.flatMap { model in
            library.settings.person?.birthDate.map { birthDate in
                PlanTimeline(model: model, results: results, birthDate: birthDate, currency: currency,
                             milestones: milestones?.ahead ?? [], locale: locale)
            }
        }
        let words = PlanWords(currency: currency, locale: locale)
        barMaximum = chapters.map { model in
            model.chapters.chapters
                .compactMap { PlanChapterStory.bar($0, model: model, results: results, words: words)?.total }
                .max() ?? 0
        } ?? 0
        onTrack = plan.map {
            OverviewOnTrack(plan: $0, library: library, valuator: valuator, asOf: asOf, results: results,
                            canRetireNow: results?.headline.canRetireNow ?? false, locale: locale)
        }
    }
}
