import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// The accounts list's cards (UI.md, "Accounts"), from the example library
/// (``PreviewLibrary``): an expanded group is a card of its own, and the
/// collapsed groups next to each other share one card, a row each.
struct AccountListCardsTests {
    private var list: AccountList {
        let library = PreviewLibrary.library
        return AccountList(library: library, valuator: Valuator(library: library),
                           today: PreviewLibrary.latestCheckIn, stalenessThreshold: 45, includesSparklines: false)
    }

    private func groups(_ cards: [AccountListCard]) -> [AccountGroup] {
        cards.compactMap { card in
            if case .group(let section) = card { section.group } else { nil }
        }
    }

    @Test func expandedGroupsAreACardEach() throws {
        let list = self.list
        try #require(list.sections.count >= 3)
        let cards = list.cards { $0 != .closed }
        #expect(groups(cards) == list.sections.map(\.group))
        if list.closed.isEmpty {
            #expect(cards.count == list.sections.count)
        } else {
            let last = try #require(cards.last)
            guard case .collapsed(let rows) = last else {
                Issue.record("A collapsed Closed should end the list as a row")
                return
            }
            #expect(rows.map(\.folder) == [.closed])
            #expect(rows.first?.count == list.closed.count)
            #expect(rows.first?.subtotal == nil)
        }
    }

    @Test func collapsedGroupsNextToEachOtherShareACard() throws {
        let list = self.list
        try #require(list.sections.count >= 3)
        let first = list.sections[0].group
        let cards = list.cards { $0 == .group(first) }
        #expect(cards.count == 2)
        #expect(groups(cards) == [first])
        guard case .collapsed(let rows) = try #require(cards.last) else {
            Issue.record("The other groups should share one card")
            return
        }
        var expected = list.sections.dropFirst().map { SidebarAccountFolder.group($0.group) }
        if !list.closed.isEmpty {
            expected.append(SidebarAccountFolder.closed)
        }
        #expect(rows.map(\.folder) == expected)
        #expect(rows.first?.subtotal == list.sections[1].subtotal)
        #expect(rows.first?.title == list.sections[1].group.description)
    }

    @Test func anExpandedGroupSplitsTheCollapsedOnes() throws {
        let list = self.list
        try #require(list.sections.count >= 3)
        let middle = list.sections[1].group
        let cards = list.cards { $0 == .group(middle) || $0 == .closed }
        #expect(cards.count == (list.closed.isEmpty ? 3 : 4))
        guard case .collapsed(let before) = cards[0] else {
            Issue.record("The first group should be a row of its own card")
            return
        }
        #expect(before.map(\.folder) == [.group(list.sections[0].group)])
        #expect(groups(cards) == [middle])
    }
}
