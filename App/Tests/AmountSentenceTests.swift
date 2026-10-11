import Testing
@testable import CanIRetireYet

/// Sentences with amounts in them (``AmountSentence``): the words stay, the
/// amounts are kept apart so they can hide with the eye.
struct AmountSentenceTests {
    private let saved: AmountSentence = "You saved \(amount: "4.210 €") and markets added \(amount: "1.200 €")."

    @Test func amountsAreKeptApartFromTheWords() {
        #expect(saved.parts == [.words("You saved "), .amount("4.210 €"), .words(" and markets added "),
                                .amount("1.200 €"), .words(".")])
        #expect(saved.hasAmounts)
    }

    @Test func itReadsWithItsAmounts() {
        #expect(saved.text == "You saved 4.210 € and markets added 1.200 €.")
        #expect(saved.spoken(hidesAmounts: false) == saved.text)
    }

    @Test func voiceOverReadsAmountHiddenInTheirPlace() {
        #expect(saved.spoken(hidesAmounts: true) == "You saved amount hidden and markets added amount hidden.")
    }

    @Test func wordsAndOtherValuesStayWords() {
        let age = 54
        let sentence: AmountSentence = "Stop at \(age), in \("March 2042")."
        #expect(sentence.parts == [.words("Stop at 54, in March 2042.")])
        #expect(!sentence.hasAmounts)
        #expect(sentence.spoken(hidesAmounts: true) == "Stop at 54, in March 2042.")
    }

    @Test func sentencesJoinAndKeepTheirAmounts() {
        let joined = [AmountSentence.amount("180.000 €"), "typically by late 2028"].joined(separator: " · ")
        #expect(joined.parts == [.amount("180.000 €"), .words(" · typically by late 2028")])
        let sum = AmountSentence("past ") + AmountSentence.amount("300.000 €") + AmountSentence(".")
        #expect(sum.text == "past 300.000 €.")
        #expect(sum.parts.count == 3)
    }

    @Test func listsReadAsWordingDoes() {
        let parts: [AmountSentence] = ["Rent (\(amount: "150k"))", "Inheritance (\(amount: "90k"))", "Car"]
        #expect(parts.listed().text == "Rent (150k), Inheritance (90k) and Car")
        #expect([AmountSentence("Car")].listed().text == "Car")
        #expect([AmountSentence]().listed().isEmpty)
    }

    @Test func theFirstWordIsCapitalized() {
        let caption: AmountSentence = "typically by \("mid 2027")"
        #expect(caption.capitalizedFirst.text == "Typically by mid 2027")
        #expect(AmountSentence.amount("300.000 €").capitalizedFirst.text == "300.000 €")
    }
}
