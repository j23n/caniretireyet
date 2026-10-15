import Foundation
import Model
import Observation
import os
import Planner

/// First launch's answers and where the tour is (UI.md, "Empty states and
/// first launch"). Kept in the ``AppModel``, not in the screen: while *See
/// My Answer* opens the new library the root view shows the opening screen,
/// and the tour comes back where it was, with what was typed.
@Observable @MainActor
final class OnboardingModel {
    /// What the lever on the answer found.
    struct Lever: Hashable, Sendable {
        /// The extra saving a month it tried (`StarterSetup.leverStep`).
        var perMonth: Decimal
        /// How many years sooner the earliest age is with it.
        var yearsSooner: Int
    }

    /// The quick estimate beside the questions on the Mac and iPad.
    struct Estimate: Hashable, Sendable {
        var headline: RetirementAnswer
        /// What spending and saving a month it was for.
        var spendingPerMonth: Decimal?
        var savingPerMonth: Decimal?
    }

    var step: OnboardingStep = .welcome

    // MARK: About you

    /// The birth date picked; `nil` until one is, so none is made up.
    var birthDate: Date?
    /// What the birth-date picker shows before one is picked.
    var pickedBirthDate = YouSettings.suggestedBirthDate().dateValue
    /// The country you live in; the device's region to start with.
    private(set) var country: CountryCode?
    var currency: CurrencyCode
    /// Whether the library is kept in iCloud Drive, which is on whenever
    /// it's available.
    var keepsInICloud = true

    // MARK: Money and later in life

    /// The amounts, ages and rates typed, with the country's suggestions
    /// for the ages and the tax until they're changed.
    var answers: StarterAnswers
    /// Whether the plan retires at ``chosenAge`` rather than as early as works.
    var retiresAtChosenAge = false
    var chosenAge = 60
    /// Whether the tax rate is still the country's suggestion.
    private(set) var taxIsDefault: Bool

    // MARK: Keep it in view

    /// The monthly note and *Your year*, as the last step's switches have them.
    var monthlyNote = true
    var yourYearNote = true

    // MARK: Creating and answering

    private(set) var isCreating = false
    /// Why the library couldn't be created.
    var error: String?
    /// Whether *See My Answer* opened a library that was already in
    /// iCloud Drive (synced from another device), which keeps its own
    /// accounts and plans.
    private(set) var openedExistingLibrary = false
    /// Whether the answer is being recorded, or was, for the tour.
    private(set) var startedAnswer = false
    /// The lever on the answer, once it's worked out; `nil` before, and
    /// when saving more doesn't move the age.
    private(set) var lever: Lever?
    /// The latest quick estimate, and the one before it.
    private(set) var estimate: Estimate?
    private(set) var previousEstimate: Estimate?

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CanIRetireYet",
                                       category: "onboarding")

    init(locale: Locale = .current) {
        let region = locale.region.map { CountryCode($0.identifier) }
        country = region
        currency = CountryDefaults.currency(for: region)
            ?? CurrencyCode(locale.currency?.identifier ?? "EUR")
        let tax = CountryDefaults.investmentTax(for: region)
        answers = StarterAnswers(pensionFromAge: CountryDefaults.pensionPotAge(for: region),
                                 statePensionFromAge: CountryDefaults.statePensionAge(for: region),
                                 investmentTax: tax)
        taxIsDefault = tax != nil
    }

    /// Whether *Continue* can leave the step: *About you* needs a birth
    /// date, since the answer is an age, and no amount can be negative.
    var canContinue: Bool {
        switch step {
        case .you: birthDate != nil
        case .money, .later: !answers.hasNegativeAmount
        case .welcome, .answer, .files, .notes: true
        }
    }

    /// Chooses the country: its currency when there's one for it, and its
    /// suggested ages and tax rate for those not changed yet.
    func choose(country: CountryCode?) {
        let before = self.country
        self.country = country
        if let currency = CountryDefaults.currency(for: country) { self.currency = currency }
        if answers.pensionFromAge == CountryDefaults.pensionPotAge(for: before) {
            answers.pensionFromAge = CountryDefaults.pensionPotAge(for: country)
        }
        if answers.statePensionFromAge == CountryDefaults.statePensionAge(for: before) {
            answers.statePensionFromAge = CountryDefaults.statePensionAge(for: country)
        }
        if taxIsDefault || answers.investmentTax == nil {
            answers.investmentTax = CountryDefaults.investmentTax(for: country)
            taxIsDefault = answers.investmentTax != nil
        }
    }

    /// Sets the tax rate typed, which is no longer the country's suggestion.
    func setInvestmentTax(_ rate: Decimal?) {
        answers.investmentTax = rate
        taxIsDefault = false
    }

    /// The birth date as the library stores it.
    var birthCalendarDate: CalendarDate? {
        birthDate.map { CalendarDate($0, in: .current) }
    }

    /// The answers as the plan takes them: the age chosen, else as early as works.
    var finalAnswers: StarterAnswers {
        var final = answers
        final.retirementAge = retiresAtChosenAge ? chosenAge : nil
        return final
    }

    /// The settings of the library *See My Answer* creates.
    var settings: LibrarySettings {
        let person = Person(birthDate: birthCalendarDate)
        return LibrarySettings(baseCurrency: currency, person: person == Person() ? nil : person, taxResidence: country)
    }

    /// The age *At an age I choose* starts from: 60, or next year's age
    /// for someone 60 or older, within the plan's ages (30 to 85).
    var suggestedAge: Int {
        let age = birthCalendarDate.map { $0.wholeYears(to: .today()) } ?? 0
        return min(max(60, age + 1), OnboardingScreen.retirementAges.upperBound)
    }

    // MARK: See My Answer

    /// *See My Answer*: creates the library with the settings chosen, adds
    /// the starting estimates and the first plan (``addStarterRecords(library:)``),
    /// moves to the answer and starts recording it
    /// (`PlanStore.recordCheckInAnswer(on:)`), as a check-in does. When the
    /// library can't be created, it says why and stays on the step.
    func seeAnswer(library: LibraryStore, plans: PlanStore, navigation: AppNavigation,
                   preferences: AppPreferences) async {
        guard !isCreating else { return }
        isCreating = true
        error = nil
        defer { isCreating = false }
        let settings = settings
        // Keeps the tour on screen once the library is open, for its last steps.
        navigation.finishesOnboarding = true
        if library.phase != .ready {
            do {
                try await library.createLibrary(in: keepsInICloud && library.isICloudAvailable ? .iCloud : .local,
                                                settings: settings)
            } catch {
                navigation.finishesOnboarding = false
                self.error = LibraryStore.describe(error)
                return
            }
        }
        await addStarterRecords(library: library, currency: settings.baseCurrency)
        if !openedExistingLibrary {
            preferences.gettingStartedSince = preferences.gettingStartedSince ?? library.asOfDate
        }
        step = .answer
        startAnswer(library: library, plans: plans)
    }

    /// The starting estimates and the first plan, as the main plan, in a
    /// new library (one synced from another device keeps its own, as does
    /// one whose files didn't all load), and only in the `currency` the
    /// amounts were typed in: a library that appeared in iCloud Drive
    /// meanwhile is opened instead. No plan without spending outside the
    /// euro (`PlanEditing.starterPlan`). When they can't be saved, the
    /// Plan screen still offers to create a plan.
    private func addStarterRecords(library: LibraryStore, currency: CurrencyCode) async {
        let existing = library.library
        guard library.canEdit, existing.plans.isEmpty, existing.accounts.isEmpty, library.unloadedFiles.isEmpty,
              existing.settings.baseCurrency == currency
        else {
            openedExistingLibrary = !existing.plans.isEmpty || !existing.accounts.isEmpty
                || existing.settings.baseCurrency != currency
            return
        }
        let answers = finalAnswers
        let today = library.asOfDate
        var plan = PlanEditing.starterPlan(
            id: library.newPlanID(for: PlanEditing.starterPlanName), name: PlanEditing.starterPlanName,
            library: existing, asOf: today, payPerMonth: answers.payPerMonth,
            spendingPerMonth: answers.spendingPerMonth, retirementAge: answers.retirementAge)
        if var starter = plan {
            StarterSetup.complete(&starter, with: answers, asOf: today)
            plan = starter
        }
        do {
            try await library.addStartingEstimates(answers, plan: plan, on: today)
        } catch {
            Self.logger.error(
                "Couldn't save the starting estimates: \(LibraryStore.describe(error), privacy: .public)")
        }
    }

    /// Records the main plan's first answer on the estimates' day, once;
    /// nothing without a main plan, a birth date (the answer step asks for
    /// it, then retries) or values to stand on.
    func startAnswer(library: LibraryStore, plans: PlanStore) {
        guard !startedAnswer, library.mainPlan != nil, library.settings.person?.birthDate != nil,
              let date = library.latestCheckIn else { return }
        startedAnswer = true
        plans.recordCheckInAnswer(on: date)
    }

    /// *Try Again*, or after the birth date was added on the answer: records
    /// the answer again.
    func retryAnswer(library: LibraryStore, plans: PlanStore) {
        startedAnswer = false
        lever = nil
        startAnswer(library: library, plans: plans)
    }

    // MARK: The lever

    /// Works out the lever once the answer is there (UI.md, "Empty states
    /// and first launch"): the main plan with ``StarterAnswers`` saving
    /// `StarterSetup.leverStep` more a month, against the plan as it is,
    /// both as quick runs, so the two are alike. Nothing when you could
    /// retire today, no age works, or saving more doesn't move the age.
    func findLever(for headline: RetirementAnswer, library: LibraryStore, plans: PlanStore) async {
        guard lever == nil, !headline.canRetireNow, headline.earliestAge != nil,
              let step = StarterSetup.leverStep(for: finalAnswers), let plan = library.mainPlan else { return }
        let date = library.asOfDate
        let base = PlanRunRequest(plan: plan, library: library.library, mode: .fast, whatIf: nil, asOf: date)
        let more = PlanRunRequest(plan: StarterSetup.savingMore(plan, perMonth: step), library: library.library,
                                  mode: .fast, whatIf: nil, asOf: date)
        let engine = plans.engine
        do {
            async let baseResults = engine.run(base, progress: nil)
            async let moreResults = engine.run(more, progress: nil)
            let (asIs, savingMore) = try await (baseResults, moreResults)
            guard let then = asIs.headline.earliestAge, let sooner = savingMore.headline.earliestAge, sooner < then
            else { return }
            lever = Lever(perMonth: step, yearsSooner: then - sooner)
        } catch {
            // No lever: the answer stands on its own.
        }
    }

    // MARK: The quick estimate

    /// What the quick estimate runs: the library and plan *See My Answer*
    /// would create, in memory; `nil` without a birth date, an amount you
    /// have today, or a plan (outside the euro without spending).
    func estimateRequest(today: CalendarDate = .today()) -> PlanRunRequest? {
        guard birthDate != nil, answers.hasStartingAmounts, !answers.hasNegativeAmount else { return nil }
        let answers = finalAnswers
        var library = Library(settings: settings)
        StarterSetup.addEstimates(answers, to: &library, on: today)
        guard var plan = PlanEditing.starterPlan(
            id: "estimate", name: PlanEditing.starterPlanName, library: library, asOf: today,
            payPerMonth: answers.payPerMonth, spendingPerMonth: answers.spendingPerMonth,
            retirementAge: answers.retirementAge)
        else { return nil }
        StarterSetup.complete(&plan, with: answers, asOf: today)
        return PlanRunRequest(plan: plan, library: library, mode: .fast, whatIf: nil, asOf: today)
    }

    /// What the quick estimate depends on: it runs again when this changes.
    struct EstimateInputs: Hashable {
        var answers: StarterAnswers
        var birthDate: CalendarDate?
        var currency: CurrencyCode
        var country: CountryCode?
    }

    var estimateInputs: EstimateInputs {
        EstimateInputs(answers: finalAnswers, birthDate: birthCalendarDate, currency: currency, country: country)
    }

    /// Runs the quick estimate for the answers as they are, a moment after
    /// the last change, so typing doesn't start a run per key.
    func updateEstimate(plans: PlanStore) async {
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled, let request = estimateRequest() else { return }
        guard let results = try? await plans.engine.run(request, progress: nil), !Task.isCancelled else { return }
        let next = Estimate(headline: results.headline, spendingPerMonth: answers.spendingPerMonth,
                            savingPerMonth: answers.saving?.perMonth)
        guard next != estimate else { return }
        previousEstimate = estimate
        estimate = next
    }
}
