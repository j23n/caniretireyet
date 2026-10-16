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

    /// What *See My Answer* added to the library it created: the starting
    /// estimates, their values and the first plan.
    struct TourRecords: Hashable, Sendable {
        var estimates: [AccountID]
        var values: Set<Valuation>
        var plan: PlanID?
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

    // MARK: Money, pension and retirement

    /// The amounts, ages and rates typed, with the country's suggestions
    /// for the ages and the tax until they're changed.
    var answers: StarterAnswers
    /// Whether you've already stopped working: there's no pay, the plan
    /// retires at your age today, and the answer says whether your money
    /// lasts (``OnboardingText/retiredTitle(_:)``).
    var hasStoppedWorking = false
    /// Whether the plan retires at ``chosenAge`` rather than as early as works.
    var retiresAtChosenAge = false
    var chosenAge = 60
    /// Whether the tax rate is still the country's suggestion.
    private(set) var taxIsDefault: Bool

    // MARK: Reminders

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
    /// What *See My Answer* added to a library it created; `nil` before, and
    /// for a library that was already in iCloud Drive.
    private(set) var tourRecords: TourRecords?
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
    /// date, since the answer is an age, and no amount it shows can be
    /// negative.
    var canContinue: Bool {
        switch step {
        case .you: birthDate != nil
        case .money: !moneyHasNegativeAmount
        case .later: !finalAnswers.hasNegativeAmount
        case .welcome, .answer, .files, .notes: true
        }
    }

    /// The step *Back* goes to: none from the welcome, and from the answer
    /// only while the library holds just what the tour added (no import yet)
    /// and no answer is being calculated, so *See My Answer* can replace
    /// it with what's changed.
    func previousStep(in library: Library, answerIsRunning: Bool) -> OnboardingStep? {
        guard let previous = step.previous else { return nil }
        guard step == .answer else { return previous }
        return !answerIsRunning && holdsOnlyTourRecords(library) ? previous : nil
    }

    /// Whether `library` holds just ``tourRecords``: no other accounts,
    /// values or plans, and nothing else an import adds (trades,
    /// instruments, import profiles). An import into an estimate, such as
    /// the starter spreadsheet's *Home*, changes its values.
    func holdsOnlyTourRecords(_ library: Library) -> Bool {
        guard let records = tourRecords else { return false }
        let months = library.months.values
        return Set(library.accounts.keys) == Set(records.estimates)
            && Set(months.flatMap(\.valuations)) == records.values
            && months.allSatisfy(\.trades.isEmpty)
            && Set(library.plans.keys) == Set(records.plan.map { [$0] } ?? [])
            && library.instruments.isEmpty && library.importProfiles.isEmpty
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

    /// The answers as the plan takes them: the age chosen, else as early as
    /// works. Once you've stopped working: no pay, one spending, and your
    /// age today. No mortgage without a home.
    var finalAnswers: StarterAnswers {
        var final = answers
        if !final.asksForMortgage { final.mortgage = nil }
        if hasStoppedWorking {
            final.payPerMonth = nil
            final.retiredSpendingPerMonth = nil
            final.retirementAge = currentAge
        } else {
            final.retirementAge = retiresAtChosenAge ? chosenAge : nil
        }
        return final
    }

    /// Whether an amount the money step shows is negative: not the
    /// fields it hides, nor spending in retirement, which the next step asks.
    var moneyHasNegativeAmount: Bool {
        let shown = finalAnswers
        return [shown.cash, shown.investments, shown.pension, shown.home, shown.mortgage, shown.payPerMonth,
                shown.spendingPerMonth].contains { ($0 ?? 0) < 0 }
    }

    /// Your age today, from the birth date picked.
    var currentAge: Int? {
        birthCalendarDate.map { $0.wholeYears(to: .today()) }
    }

    /// The settings of the library *See My Answer* creates.
    var settings: LibrarySettings {
        let person = Person(birthDate: birthCalendarDate)
        return LibrarySettings(baseCurrency: currency, person: person == Person() ? nil : person, taxResidence: country)
    }

    /// The age *At an age I choose* starts from: 60, or next year's age
    /// for someone 60 or older, within the plan's ages (30 to 85).
    var suggestedAge: Int {
        let age = currentAge ?? 0
        return min(max(60, age + 1), OnboardingScreen.retirementAges.upperBound)
    }

    // MARK: See My Answer

    /// *See My Answer*: creates the library with the settings chosen, adds
    /// the starting estimates and the first plan (``addStarterRecords(library:settings:)``),
    /// moves to the answer and starts recording it
    /// (`PlanStore.recordCheckInAnswer(on:)`), as a check-in does. When the
    /// library can't be created, it says why and stays on the step. After
    /// *Back* from the answer, it replaces what it added before.
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
        await addStarterRecords(library: library, settings: settings)
        if !openedExistingLibrary {
            preferences.gettingStartedSince = preferences.gettingStartedSince ?? library.asOfDate
        }
        step = .answer
        startedAnswer = false
        lever = nil
        startAnswer(library: library, plans: plans)
    }

    /// The starting estimates and the first plan, as the main plan, in a
    /// new library (one synced from another device keeps its own, as does
    /// one whose files didn't all load), and only in the currency of
    /// `settings`, which the amounts were typed in: a library that appeared
    /// in iCloud Drive meanwhile is opened instead. No plan without spending
    /// outside the euro (`PlanEditing.starterPlan`). When they can't be
    /// saved, the Plan screen still offers to create a plan.
    ///
    /// Again after *Back* from the answer, while the library holds just
    /// ``tourRecords``: those are replaced, the plan keeps its ID, and the
    /// library takes `settings`.
    private func addStarterRecords(library: LibraryStore, settings: LibrarySettings) async {
        var existing = library.library
        let replacing = holdsOnlyTourRecords(existing) ? tourRecords : nil
        if let replacing {
            for id in replacing.estimates { existing.accounts[id] = nil }
            existing.plans = [:]
            existing.settings.baseCurrency = settings.baseCurrency
            existing.settings.person = settings.person
            existing.settings.taxResidence = settings.taxResidence
        }
        guard library.canEdit, existing.plans.isEmpty, existing.accounts.isEmpty, library.unloadedFiles.isEmpty,
              existing.settings.baseCurrency == settings.baseCurrency
        else {
            openedExistingLibrary = !existing.plans.isEmpty || !existing.accounts.isEmpty
                || existing.settings.baseCurrency != settings.baseCurrency
            return
        }
        let answers = finalAnswers
        let today = library.asOfDate
        let planID = replacing?.plan ?? library.newPlanID(for: PlanEditing.starterPlanName)
        var plan = PlanEditing.starterPlan(
            id: planID, name: PlanEditing.starterPlanName,
            library: existing, asOf: today, payPerMonth: answers.payPerMonth,
            spendingPerMonth: answers.spendingPerMonth, retirementAge: answers.retirementAge)
        if var starter = plan {
            StarterSetup.complete(&starter, with: answers, asOf: today)
            plan = starter
        }
        do {
            let estimates = try await library.addStartingEstimates(
                answers, plan: plan, on: today, replacing: replacing?.estimates ?? [],
                replacingPlan: replacing?.plan, settings: replacing == nil ? nil : settings)
            let values = library.library.months.values.flatMap(\.valuations)
            tourRecords = TourRecords(estimates: estimates, values: Set(values), plan: plan?.id)
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
    /// retire today, no age works, saving more doesn't move the age, or
    /// you've stopped working.
    func findLever(for headline: RetirementAnswer, library: LibraryStore, plans: PlanStore) async {
        guard lever == nil, !hasStoppedWorking, !headline.canRetireNow, headline.earliestAge != nil,
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
        guard birthDate != nil, answers.hasStartingAmounts, !finalAnswers.hasNegativeAmount else { return nil }
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
                            savingPerMonth: finalAnswers.saving?.perMonth)
        guard next != estimate else { return }
        previousEstimate = estimate
        estimate = next
    }
}
