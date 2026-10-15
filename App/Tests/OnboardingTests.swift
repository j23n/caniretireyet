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

    @Test func backNeverGoesToBeforeTheLibraryWasCreated() {
        #expect(OnboardingStep.welcome.previous == nil)
        #expect(OnboardingStep.you.previous == .welcome)
        #expect(OnboardingStep.answer.previous == nil)
        #expect(OnboardingStep.files.previous == .answer)
    }

    @Test func theQuestionsAreNumberedUpToTheAnswer() {
        #expect(OnboardingStep.allCases.compactMap(\.questionNumber) == [1, 2, 3, 4])
        #expect(OnboardingStep.questionCount == 4)
        #expect(OnboardingStep.welcome.questionNumber == nil)
        #expect(OnboardingStep.files.questionNumber == nil)
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
        #expect(saving.parts.first == .words("So you save about "))
        #expect(saving.parts.last == .words(" a month, a third of your pay."))
        #expect(saving.hasAmounts)
        let even = try #require(OnboardingText.savingLine(
            StarterAnswers(payPerMonth: 3_000, spendingPerMonth: 3_000), currency: .eur, locale: english))
        #expect(even.text == "So you spend all you take home.")
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
