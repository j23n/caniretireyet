import Glance
import Model
import Planner
import SwiftUI

/// The answer, inside the tour (UI.md, "Empty states and first launch"):
/// the main plan runs here, with its progress, as a check-in's does, and
/// records the first answer. Then the answer as a date, "Your last Monday
/// at work could be 14 May 2052", how sure ("At 64, in 9 of 10 futures.",
/// with a small fan of futures), the one lever worked out, and that it's a
/// first sketch: it stands on rough amounts until files replace them.
/// Once you've stopped working, the answer is whether your money lasts,
/// and what you could spend, with no calendar page and no lever.
///
/// When there's nothing to answer from, it says what's missing: an age
/// (with a picker; *See My Answer* saves it as a birth date and runs the
/// plan), amounts, or a plan.
struct OnboardingAnswerStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(\.locale) private var locale
    @State private var age: Int?
    @State private var savingAge = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            if model.openedExistingLibrary {
                OnboardingTitle("Your library is already set up",
                                detail: "It was already in iCloud Drive, so it opened with its existing accounts and "
                                    + "plans.")
            }
            if let headline = shownHeadline {
                reveal(headline)
            } else if let run = plans.checkInAnswer, run.isRunning, let main = library.mainPlan {
                running(main.id)
            } else if let error = plans.checkInAnswer?.error, model.startedAnswer {
                failed(error)
            } else if !model.openedExistingLibrary {
                missing
            }
        }
        .task(id: shownHeadline) {
            if let headline = shownHeadline {
                await model.findLever(for: headline, library: library, plans: plans)
            }
        }
    }

    /// The answer the tour recorded, else the main plan's latest (a library
    /// that was already there).
    private var shownHeadline: RetirementAnswer? {
        if let run = plans.checkInAnswer, model.startedAnswer, let headline = run.headline { return headline }
        return model.openedExistingLibrary ? plans.mainHeadline : nil
    }

    // MARK: Running

    private func running(_ plan: PlanID) -> some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            OnboardingCalendarPage(date: nil)
            Text("Calculating thousands of simulated futures…")
                .font(.title2.bold())
                .foregroundStyle(Palette.ink)
            if let progress = plans.progress(of: plan, .checkIn) {
                ProgressView(value: min(1, max(0, progress.fraction)), total: 1)
                    .tint(Palette.accent)
                Text(PlanRunText.overall(progress, locale: locale))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondaryInk)
            } else {
                ProgressView()
            }
        }
    }

    private func failed(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            OnboardingTitle("Your plan couldn't be calculated", detail: error)
            Button("Try Again") { model.retryAnswer(library: library, plans: plans) }
                .buttonStyle(.bordered)
            Text("You can continue: Today calculates your plan once it can.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
    }

    // MARK: Missing

    /// What the answer still needs, in the order the plan needs it.
    @ViewBuilder
    private var missing: some View {
        if library.mainPlan == nil {
            OnboardingTitle("Your library is ready",
                            detail: "There's no plan yet because no spending was entered. You can create one on the "
                                + "Plan screen.")
        } else if library.settings.person?.birthDate == nil {
            VStack(alignment: .leading, spacing: Metrics.m) {
                OnboardingTitle("Add your age",
                                detail: "The answer is an age, so the app needs yours. It stays on your devices.")
                OnboardingAgePicker(age: $age)
                    .onboardingCard()
                Button("See My Answer") { Task { await saveAge() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(age == nil || savingAge || !library.canEdit)
            }
        } else {
            OnboardingTitle("Your library is ready",
                            detail: "The answer needs your amounts. Import your statements next, or fill in the "
                                + "starter spreadsheet and import it.")
        }
    }

    /// Saves the age chosen here as a birth date, then records the answer.
    private func saveAge() async {
        guard let age else { return }
        savingAge = true
        defer { savingAge = false }
        let date = YouSettings.birthDate(forAge: age)
        do {
            try library.updateSettings { settings in
                var person = settings.person ?? Person()
                person.birthDate = date
                settings.person = person
            }
            await library.waitForPendingWrites()
            model.age = age
            model.retryAnswer(library: library, plans: plans)
        } catch {
            model.error = LibraryStore.describe(error)
        }
    }

    // MARK: The answer

    private func reveal(_ headline: RetirementAnswer) -> some View {
        let today = library.asOfDate
        let results = library.mainPlan.flatMap { plans.results(of: $0.id) }
        let endAge = library.mainPlan?.effectiveEndAge ?? 95
        let retired = model.hasStoppedWorking && !model.openedExistingLibrary
        return VStack(alignment: .leading, spacing: Metrics.l) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(retired ? (model.openedExistingLibrary ? "Your answer" : "Your first answer")
                     : OnboardingText.revealLead(headline, openedExistingLibrary: model.openedExistingLibrary))
                    .font(.headline)
                    .foregroundStyle(Palette.secondaryInk)
                Text(verbatim: retired ? OnboardingText.retiredTitle(headline)
                     : OnboardingText.revealTitle(headline, locale: locale))
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .privacySensitiveInFeedback()
                Text(retired ? OnboardingText.retiredLine(headline, endAge: endAge)
                     : OnboardingText.revealLine(headline))
                    .font(.title3)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if retired, let spending = OnboardingText.retiredSpendingLine(headline, currency: library.baseCurrency,
                                                                         locale: locale) {
                AmountSentenceText(spending)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let results, !results.portfolio.isEmpty {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    FanChart(fan: results.portfolio, markers: results.markers)
                        .privacySensitiveInFeedback()
                    Text(OnboardingText.fanLine(confidence: headline.confidence, hasStoppedWorking: retired))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .onboardingCard()
            }
            if let lever = model.lever {
                leverRow(lever)
            }
            OnboardingSketchChip()
        }
    }

    /// "Save 340 € more a month" over "and it could be 2 years sooner": what
    /// the plan can do, worked out already. The Plan's levers try more.
    private func leverRow(_ lever: OnboardingModel.Lever) -> some View {
        let words = OnboardingText.lever(perMonth: lever.perMonth, years: lever.yearsSooner,
                                         currency: library.baseCurrency, locale: locale)
        return HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
            Image(systemName: "arrow.left.circle")
                .foregroundStyle(Palette.positive)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                AmountSentenceText(words.action)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(words.effect)
                    .foregroundStyle(Palette.positive)
                Text("The Plan's levers try other changes.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .onboardingCard()
        .accessibilityElement(children: .combine)
    }
}

/// "It's a first sketch": the answer stands on rough amounts. The tour
/// shows it under the answer, with a tap on ⓘ explaining it.
struct OnboardingSketchChip: View {
    @State private var explains = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text("It's a first sketch from rough amounts, not advice. Add your accounts and it gets sharper.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                explains = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("What the answer stands on"))
            .popover(isPresented: $explains) {
                Text(Self.explanation)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Metrics.l)
                    .frame(idealWidth: 320, maxWidth: 360, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    static let explanation = "This answer is based on the rough amounts you entered at first launch, which are "
        + "kept as accounts named \"(estimate)\". After you import your statements or the starter spreadsheet, you "
        + "can replace the estimates with your real accounts, and the answer is calculated again."
}

/// A calendar page: the weekday over the day and the month, for the last
/// Monday at work; blank ("?") until there's an answer.
struct OnboardingCalendarPage: View {
    let date: CalendarDate?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            Text(weekday)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Metrics.xs)
                .background(Palette.red)
            Text(verbatim: date.map { "\($0.day)" } ?? "?")
                .font(.system(size: 40, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .padding(.top, Metrics.xs)
            Text(verbatim: date.map { GlanceText.monthAndYear($0, locale: locale) } ?? "····")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .padding(.bottom, Metrics.s)
        }
        .frame(width: 104)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        }
        .privacySensitiveInFeedback()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date.map { "Your last Monday at work: \(AmountFormat.longDate($0, locale: locale))" }
            ?? "A blank calendar page. It shows a date once you have an answer."))
    }

    private var weekday: String {
        guard let date else { return "MONDAY" }
        return date.dateValue.formatted(Date.FormatStyle().weekday(.wide).locale(locale)).uppercased()
    }
}
