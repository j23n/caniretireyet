import Foundation
import Model
import Testing
@testable import CanIRetireYet

/// *With this change*'s words (UI.md, "With this change"): how far the date
/// moved, and the tiles' pills.
struct PlanChangeWordsTests {
    private let english = Locale(identifier: "en_US")

    private func answer(_ earliest: CalendarDate, age: Int) -> RetirementAnswer {
        RetirementAnswer(confidence: 0.9, earliestAge: age, earliestDate: earliest)
    }

    @Test func theDateMovesInMonthsAndYears() throws {
        let base = answer("2050-06-15", age: 62)
        #expect(try #require(PlanDateMove(from: base, to: answer("2050-06-20", age: 62))).words == "Same date")
        #expect(try #require(PlanDateMove(from: base, to: answer("2051-06-15", age: 63))).words == "A year later")
        #expect(try #require(PlanDateMove(from: base, to: answer("2048-06-15", age: 60))).words == "2 years sooner")
        #expect(try #require(PlanDateMove(from: base, to: answer("2050-07-15", age: 62))).words == "A month later")
        // Across a year's end.
        let december = answer("2050-12-14", age: 62)
        let move = try #require(PlanDateMove(from: december, to: answer("2051-02-15", age: 63)))
        #expect(move.months == 2)
        #expect(move.words == "2 months later")
        // No date on either side: nothing to compare.
        #expect(PlanDateMove(from: base, to: RetirementAnswer(confidence: 0.9)) == nil)
    }

    @Test func aPillSaysSameAsNowWhenTheRoundedValuesMatch() {
        let words = { (change: PlanChangeTile.Change) in
            PlanChangeTile.words(change, currency: .eur, locale: english)
        }
        let same = words(.share(from: 0.81, to: 0.84))
        #expect(same.text == "Same as now")
        #expect(same.direction == 0)
        let up = words(.share(from: 0.8, to: 0.9))
        #expect(up.text == "▲ from 8 in 10")
        #expect(up.direction == 1)
        #expect(!up.isAmount)
        #expect(words(.share(from: 0.9, to: 0.7)).text == "▼ from 9 in 10")

        let cents = words(.amount(Decimal(string: "0.4") ?? 0, good: true))
        #expect(cents.text == "Same as now")
        #expect(!cents.isAmount)
        let less = words(.amount(-500, good: true))
        #expect(less.text == "▼ " + AmountFormat.amount(500, currency: .eur, locale: english))
        #expect(less.direction == -1)
        #expect(less.good == true)
        #expect(less.isAmount)
    }
}
