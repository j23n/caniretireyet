import Foundation
import Model
import Planner
import Testing
@testable import CanIRetireYet

/// First launch's order and words, *Getting started* on the Overview, and
/// the answer after an import (UI.md, "Empty states and first launch",
/// "Overview", "Import").
struct OnboardingTests {
    private let english = Locale(identifier: "en_US")

    // MARK: The tour

    @Test func theAnswerComesBeforeTheFiles() {
        #expect(OnboardingStep.allCases == [.welcome, .you, .money, .later, .answer, .files, .notes])
        #expect(OnboardingStep.allCases.filter(\.comesAfterCreating) == [.answer, .files, .notes])
        #expect(OnboardingStep.later.next == .answer)
        #expect(OnboardingStep.notes.next == nil)
    }

    @Test func eachStepFollowsTheOneBefore() {
        #expect(OnboardingStep.welcome.previous == nil)
        #expect(OnboardingStep.you.previous == .welcome)
        #expect(OnboardingStep.answer.previous == .later)
        #expect(OnboardingStep.files.previous == .answer)
    }

    /// *Back* from the answer goes to the questions while the library holds
    /// just what the tour added, and *See My Answer* then replaces it.
    @MainActor
    @Test func backFromTheAnswerReplacesWhatTheTourAdded() async throws {
        let model = AppModel.preview(Library(settings: LibrarySettings()), defaults: "onboarding-back-tests")
        let tour = model.onboarding
        tour.currency = model.library.library.settings.baseCurrency
        tour.birthDate = tour.pickedBirthDate
        tour.answers.cash = 10_000
        tour.answers.spendingPerMonth = 2_000
        tour.step = .later
        await tour.seeAnswer(library: model.library, plans: model.plans, navigation: model.navigation,
                             preferences: model.preferences)
        #expect(tour.step == .answer)
        let first = try #require(tour.tourRecords)
        #expect(first.estimates.count == 1)
        #expect(tour.previousStep(in: model.library.library, answerIsRunning: false) == .later)
        #expect(tour.previousStep(in: model.library.library, answerIsRunning: true) == nil)

        tour.step = .later
        tour.answers.cash = 25_000
        tour.answers.investments = 5_000
        tour.birthDate = Calendar.current.date(byAdding: .year, value: -1, to: tour.pickedBirthDate)
        tour.currency = tour.currency == "USD" ? "EUR" : "USD"
        await tour.seeAnswer(library: model.library, plans: model.plans, navigation: model.navigation,
                             preferences: model.preferences)
        let second = try #require(tour.tourRecords)
        let library = model.library.library
        #expect(!tour.openedExistingLibrary)
        #expect(second.plan == first.plan)
        #expect(second.estimates.count == 2)
        #expect(Set(library.accounts.keys) == Set(second.estimates))
        #expect(Set(library.plans.keys) == Set(second.plan.map { [$0] } ?? []))
        #expect(library.settings.mainPlan == second.plan)
        #expect(library.settings.baseCurrency == tour.currency)
        #expect(library.settings.person?.birthDate == tour.birthCalendarDate)
        #expect(library.accounts.values.allSatisfy { $0.currency == tour.currency })
        #expect(Set(library.months.values.flatMap(\.valuations)) == second.values)
    }

    /// Once something else is in the library, such as an imported account,
    /// the answer has no *Back*.
    @MainActor
    @Test func anImportEndsBackFromTheAnswer() async throws {
        let model = AppModel.preview(Library(settings: LibrarySettings()), defaults: "onboarding-import-tests")
        let tour = model.onboarding
        tour.currency = model.library.library.settings.baseCurrency
        tour.birthDate = tour.pickedBirthDate
        tour.answers.cash = 10_000
        tour.answers.spendingPerMonth = 2_000
        tour.step = .later
        await tour.seeAnswer(library: model.library, plans: model.plans, navigation: model.navigation,
                             preferences: model.preferences)
        let records = try #require(tour.tourRecords)
        #expect(tour.previousStep(in: model.library.library, answerIsRunning: false) == .later)

        var newAccount = model.library.library
        newAccount.accounts["bank"] = Account(id: "bank", name: "Bank", kind: .cash, currency: tour.currency,
                                              opened: "2026-01-01")
        #expect(tour.previousStep(in: newAccount, answerIsRunning: false) == nil)

        // The starter spreadsheet's columns match the estimates by name, so
        // its values land in them.
        var intoEstimate = model.library.library
        let estimate = try #require(records.estimates.first)
        intoEstimate.upsert(Valuation(account: estimate, date: "2026-11-30", balance: 12_000, source: .manual))
        #expect(tour.previousStep(in: intoEstimate, answerIsRunning: false) == nil)
    }

    @Test func everyStepAfterTheWelcomeIsNumbered() {
        #expect(OnboardingStep.allCases.compactMap(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(OnboardingStep.count == 6)
        #expect(OnboardingStep.welcome.number == nil)
        #expect(OnboardingStep.notes.number == 6)
    }

    /// The answer is an age, so *About you* doesn't go on without a birth
    /// date; the picker's suggestion doesn't count until it's chosen.
    @MainActor
    @Test func aboutYouWaitsForABirthDate() {
        let model = OnboardingModel(locale: english)
        model.step = .you
        #expect(!model.canContinue)
        model.birthDate = model.pickedBirthDate
        #expect(model.canContinue)
    }

    @MainActor
    @Test func aNegativeAmountKeepsTheMoneyStepFromGoingOn() {
        let model = OnboardingModel(locale: english)
        model.step = .money
        #expect(model.canContinue)
        model.answers.cash = -1
        #expect(!model.canContinue)
    }

    /// Without a birth date the answer step asks for one, so the tour
    /// doesn't start a run the planner would refuse.
    @MainActor
    @Test func theAnswerWaitsForABirthDate() throws {
        var library = Library(settings: LibrarySettings())
        StarterSetup.addEstimates(StarterAnswers(cash: 10_000), to: &library, on: "2026-10-15")
        let plan = try #require(PlanEditing.starterPlan(
            id: "base-case", name: PlanEditing.starterPlanName, library: library, asOf: "2026-10-15",
            payPerMonth: nil, spendingPerMonth: 2_000))
        library.plans[plan.id] = plan
        library.settings.mainPlan = plan.id
        let model = AppModel.preview(library, defaults: "onboarding-tests")
        model.onboarding.startAnswer(library: model.library, plans: model.plans)
        #expect(!model.onboarding.startedAnswer)
        #expect(model.plans.checkInAnswer == nil)
    }

    // MARK: Words

    @Test func theRevealSaysYesOrNotYet() {
        #expect(OnboardingText.revealTitle(RetirementAnswer(confidence: 0.9, canRetireNow: true)) == "Yes.")
        #expect(OnboardingText.revealTitle(RetirementAnswer(confidence: 0.9, earliestAge: 58)) == "Not yet.")
    }

    @Test func theRevealLineSaysTheAgeAndHowSure() {
        let today: CalendarDate = "2026-10-15"
        #expect(OnboardingText.revealLine(RetirementAnswer(confidence: 0.9, earliestAge: 58), today: today)
            == "You could retire at 58.")
        #expect(OnboardingText.revealLine(RetirementAnswer(confidence: 0.9, canRetireNow: true), today: today)
            == "You could retire today, in at least 9 of 10 futures.")
        #expect(OnboardingText.revealLine(RetirementAnswer(confidence: 0.9), today: today)
            == "No age works in 9 of 10 futures yet.")
    }

    @Test func sharesOfPayAreWordsWhenClose() {
        #expect(OnboardingText.share(0.5, locale: english) == "half")
        #expect(OnboardingText.share(0.34, locale: english) == "a third")
        #expect(OnboardingText.share(0.25, locale: english) == "a quarter")
        #expect(OnboardingText.share(0.38, locale: english) == "38%")
    }

    @Test func theSavingLineFollowsPayAndSpending() throws {
        #expect(OnboardingText.savingLine(StarterAnswers(payPerMonth: 3_000), currency: .eur, locale: english) == nil)
        let saving = try #require(OnboardingText.savingLine(
            StarterAnswers(payPerMonth: 3_000, spendingPerMonth: 2_000), currency: .eur, locale: english))
        #expect(saving.parts.first == .words("You save about "))
        #expect(saving.parts.last == .words(" a month, a third of your pay."))
        #expect(saving.hasAmounts)
        let even = try #require(OnboardingText.savingLine(
            StarterAnswers(payPerMonth: 3_000, spendingPerMonth: 3_000), currency: .eur, locale: english))
        #expect(even.text == "You spend all you take home.")
        let short = try #require(OnboardingText.savingLine(
            StarterAnswers(payPerMonth: 3_000, spendingPerMonth: 3_300), currency: .eur, locale: english))
        #expect(short.parts.first == .words("You spend about "))
    }

    // MARK: Getting started

    private func library(home: Decimal? = 300_000) -> Library {
        var library = Library(settings: LibrarySettings())
        StarterSetup.addEstimates(StarterAnswers(cash: 10_000, pension: 20_000, home: home), to: &library,
                                  on: "2026-10-15")
        return library
    }

    @Test func gettingStartedListsTheFirstSteps() {
        let list = GettingStartedList(library: library(), hasAnswer: true, hasWidget: false, since: "2026-10-15",
                                      today: "2026-10-15", locale: english)
        #expect(list.rows.map(\.item) == [.answer, .importFiles, .fillIn, .widget, .checkIn])
        #expect(list.rows.map(\.isDone) == [true, false, false, false, false])
        #expect(list.doneCount == 1)
        #expect(!list.isDone)
        #expect(list.rows[2].title == "Fill in your home and pension")
    }

    @Test func fillingInGoesWithoutAHomeOrPensionEstimate() {
        var library = Library(settings: LibrarySettings())
        StarterSetup.addEstimates(StarterAnswers(cash: 10_000), to: &library, on: "2026-10-15")
        let list = GettingStartedList(library: library, hasAnswer: false, hasWidget: false, since: "2026-10-15",
                                      today: "2026-10-15", locale: english)
        #expect(list.rows.map(\.item) == [.answer, .importFiles, .widget, .checkIn])
    }

    @Test func importingAndClosingTheEstimatesTicksThem() {
        var library = library(home: nil)
        library.accounts["bank"] = Account(id: "bank", name: "Bank", kind: .cash, currency: .eur, opened: "2026-01-01")
        library.upsert(Valuation(account: "bank", date: "2026-11-30", balance: 9_000))
        for estimate in library.openStartingEstimates where estimate.kind == .pensionFund {
            library.accounts[estimate.id]?.closed = "2026-11-29"
        }
        let list = GettingStartedList(library: library, hasAnswer: true, hasWidget: true, since: "2026-10-15",
                                      today: "2026-12-01", locale: english)
        #expect(list.rows.map(\.item) == [.answer, .importFiles, .fillIn, .widget, .checkIn])
        #expect(list.rows[2].title == "Fill in your pension")
        #expect(list.isDone)
    }

    // MARK: After an import

    @Test func theAnswerAfterAnImportComparesWithTheFirstSketch() {
        let sketch = RetirementAnswer(confidence: 0.9, earliestAge: 60)
        #expect(ImportAnswerFollowUp.change(from: sketch, to: RetirementAnswer(confidence: 0.9, earliestAge: 58))
            == "2 years sooner than your first sketch.")
        #expect(ImportAnswerFollowUp.change(from: sketch, to: RetirementAnswer(confidence: 0.9, earliestAge: 61))
            == "A year later than your first sketch.")
        #expect(ImportAnswerFollowUp.change(from: sketch, to: sketch) == "The same age as your first sketch.")
        #expect(ImportAnswerFollowUp.change(from: nil, to: sketch) == nil)
    }
}
