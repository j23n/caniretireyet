import Glance
import Model
import Planner
import SwiftUI

/// The answer, inside the tour (UI.md, "Empty states and first launch"):
/// the main plan runs here, with its progress, as a check-in's does, and
/// records the first answer. Then the calendar page of the last Monday at
/// work, the answer in words, how ready (the ring) and how sure (a small
/// fan of futures), each explained once, the one lever worked out, and
/// "First sketch": it stands on round numbers until files replace them.
///
/// When there's nothing to answer from, it says what's missing: a birth
/// date (with a picker, which saves it and runs the plan), amounts, or a
/// plan.
struct OnboardingAnswerStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(\.locale) private var locale
    @State private var birthDate = YouSettings.suggestedBirthDate().dateValue
    @State private var savingBirthDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            if model.openedExistingLibrary {
                OnboardingTitle("Your library is here",
                                detail: "It was already in iCloud Drive, so it opened with its own accounts and plans.")
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
            Text("Playing out thousands of futures…")
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
            Text("You can carry on: the Overview has your plan, with *Calculate*.")
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
                            detail: "Without spending, there's no plan to answer from yet. Create one on the Plan "
                                + "screen: it asks what you spend.")
        } else if library.settings.person?.birthDate == nil {
            VStack(alignment: .leading, spacing: Metrics.m) {
                OnboardingTitle("Your answer is an age",
                                detail: "Add your birth date to see it. It stays on your devices.")
                DatePicker("Born", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    .personalControl()
                    .onboardingCard()
                Button("See My Answer") { Task { await saveBirthDate() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(savingBirthDate || !library.canEdit)
            }
        } else {
            OnboardingTitle("Your library is ready",
                            detail: "Your answer comes once there's something to stand on: import your statements "
                                + "next, or add round amounts as estimates by importing the starter spreadsheet.")
        }
    }

    /// Saves the birth date picked here, then records the answer.
    private func saveBirthDate() async {
        savingBirthDate = true
        defer { savingBirthDate = false }
        let date = CalendarDate(birthDate, in: .current)
        do {
            try library.updateSettings { settings in
                var person = settings.person ?? Person()
                person.birthDate = date
                settings.person = person
            }
            await library.waitForPendingWrites()
            model.birthDate = birthDate
            model.retryAnswer(library: library, plans: plans)
        } catch {
            model.error = LibraryStore.describe(error)
        }
    }

    // MARK: The answer

    private func reveal(_ headline: RetirementAnswer) -> some View {
        let today = library.asOfDate
        let results = library.mainPlan.flatMap { plans.results(of: $0.id) }
        return VStack(alignment: .leading, spacing: Metrics.l) {
            Text("Played out thousands of futures")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Palette.secondaryInk)
            HStack(alignment: .center, spacing: Metrics.l) {
                if !headline.canRetireNow, let date = headline.earliestDate {
                    OnboardingCalendarPage(date: StarterSetup.lastMonday(onOrBefore: date))
                }
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text(OnboardingText.revealTitle(headline))
                        .font(.largeTitle.bold())
                        .foregroundStyle(Palette.ink)
                    Text(OnboardingText.revealLine(headline, today: today))
                        .font(.title3)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .privacySensitiveInFeedback()
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            readiness(headline, endAge: library.mainPlan?.effectiveEndAge ?? 95)
            if let results, !results.portfolio.isEmpty {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    FanChart(fan: results.portfolio, markers: results.markers)
                        .privacySensitiveInFeedback()
                    Text(OnboardingText.fanLine(confidence: headline.confidence))
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

    /// The ring, with what it compares in a sentence beside it.
    @ViewBuilder
    private func readiness(_ headline: RetirementAnswer, endAge: Int) -> some View {
        let figure = headline.readinessFigure
        HStack(alignment: .center, spacing: Metrics.l) {
            if let percent = figure.text({ AmountFormat.percent($0, digits: 0, locale: locale) }) {
                ZStack {
                    ReadinessRing(fraction: figure.lappingFill, lineWidth: 10, laps: true)
                        .privacySensitiveInFeedback()
                    VStack(spacing: 0) {
                        Text(verbatim: percent)
                            .font(.title2.bold())
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .privacySensitiveInFeedback()
                        Text("ready")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    .padding(Metrics.l)
                }
                .frame(width: 104, height: 104)
                .accessibilityHidden(true)
            }
            Text(OnboardingText.readinessLine(headline, endAge: endAge, locale: locale))
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .privacySensitiveInFeedback()
        }
    }

    /// "Save 340 € more a month · about 2 years sooner": what the plan can
    /// do, worked out already. The What if on the Plan screen tries more.
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
                Text("Try more on your plan's What if.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .onboardingCard()
        .accessibilityElement(children: .combine)
    }
}

/// "First sketch": the answer stands on round numbers. The tour shows it
/// under the answer, the Overview beside "Can I retire yet?" while any
/// starting estimate is open, with a tap explaining it.
struct OnboardingSketchChip: View {
    var showsDisclaimer = true
    @State private var explains = false

    var body: some View {
        HStack(spacing: Metrics.s) {
            Button {
                explains = true
            } label: {
                Label("First sketch", systemImage: "pencil.and.scribble")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, Metrics.s)
                    .padding(.vertical, Metrics.xs)
                    .background(Palette.warning.opacity(0.15), in: Capsule())
                    .foregroundStyle(Palette.ink)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Explains what the answer stands on"))
            .popover(isPresented: $explains) {
                Text(Self.explanation)
                    .font(.callout)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Metrics.l)
                    .frame(idealWidth: 320, maxWidth: 360, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
            }
            if showsDisclaimer {
                Text("From round numbers. Estimates, not advice.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    static let explanation = "This answer stands on the round amounts you gave at first launch, kept as accounts "
        + "named \"(estimate)\". Import your statements and the starter spreadsheet: after each import you can "
        + "replace the estimates with your real accounts, and the answer is calculated again."
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
            ?? "A calendar page, blank until your answer"))
    }

    private var weekday: String {
        guard let date else { return "MONDAY" }
        return date.dateValue.formatted(Date.FormatStyle().weekday(.wide).locale(locale)).uppercased()
    }
}
