import Foundation
import Model
import Planner
import Testing
@testable import CanIRetireYet

/// So far's year month by month (UI.md, "The year", *Month by month*), on
/// the example library (``PreviewLibrary``): where each year starts and
/// ends, and its milestones and events in between, in order.
@MainActor
struct PlanYearLineTests {
    private let english = Locale(identifier: "en_US")

    private func cards() throws -> [PlanProgressTimeline.Card] {
        let library = PreviewLibrary.library
        let plan = try #require(library.plans["base"])
        let progress = PlanProgress(plan: "base", document: plan, library: library, valuator: PreviewLibrary.valuator,
                                    asOf: PreviewLibrary.latestCheckIn)
        let cards = PlanProgressTimeline(progress, text: PlanMilestoneText(currency: .eur, locale: english)).cards
        try #require(!cards.isEmpty)
        return cards
    }

    @Test func aYearRunsFromItsStartToNowOrItsEnd() throws {
        let cards = try cards()
        let text = PlanMilestoneText(currency: .eur, locale: english)
        for card in cards {
            let entries = PlanYearLine.entries(card, text: text)
            let first = try #require(entries.first)
            let last = try #require(entries.last)
            #expect(first.kind == .start)
            #expect(first.title.text == (card.year.from.year < card.year.year ? "Started the year" : "First values"))
            #expect(first.date.year == card.year.year)
            #expect(last.kind == .end)
            #expect(last.title.text == (card.year.isLatest ? "Now" : "The year's end"))
            #expect(last.date == card.year.to)
            // Every milestone and event once, by date, between the two.
            let middle = entries.dropFirst().dropLast()
            #expect(middle.filter { $0.kind == .milestone }.count == card.milestones.count)
            #expect(middle.filter { $0.kind == .event }.count == card.events.count)
            #expect(middle.map(\.date) == middle.map(\.date).sorted())
            #expect(entries.map(\.id) == Array(entries.indices))
        }
        // The first year starts at the first record, so it isn't the whole year.
        let firstYear = try #require(cards.first)
        #expect(PlanYearLine.entries(firstYear, text: text).first?.title.text == "First values")
    }

    @Test func aMilestoneIsNamedAsTheListsNameIt() throws {
        let text = PlanMilestoneText(currency: .eur, locale: english)
        let cards = try cards()
        for card in cards {
            let named = PlanYearLine.entries(card, text: text).filter { $0.kind == .milestone }.map(\.title.text)
            #expect(named.sorted() == card.milestones.map { text.name($0.milestone).text }.sorted())
        }
    }
}
