import CoreGraphics
import Testing
@testable import CanIRetireYet

/// How many slots a row of tiles has (UI.md, "Tiles"): two on iPhone in
/// portrait, then four or six on wider pages, never three, five or more
/// than six.
@MainActor
struct TileGridTests {
    @Test func aRowHasTwoFourOrSixSlots() {
        for width in stride(from: CGFloat(0), through: 3000, by: 7) {
            #expect([2, 4, 6].contains(TileGrid.slots(width: width)), "width \(width)")
        }
    }

    @Test func aRowTakesTheMostEvenSlotsThatKeepTheirWidth() {
        let small = TileGrid.minimumSmallWidth
        let spacing: CGFloat = 12
        func width(slots: Int) -> CGFloat { CGFloat(slots) * small + CGFloat(slots - 1) * spacing }
        #expect(TileGrid.slots(width: 360, spacing: spacing) == 2)
        #expect(TileGrid.slots(width: width(slots: 3), spacing: spacing) == 2)
        #expect(TileGrid.slots(width: width(slots: 4) - 1, spacing: spacing) == 2)
        #expect(TileGrid.slots(width: width(slots: 4), spacing: spacing) == 4)
        #expect(TileGrid.slots(width: width(slots: 5), spacing: spacing) == 4)
        #expect(TileGrid.slots(width: width(slots: 6), spacing: spacing) == 6)
        #expect(TileGrid.slots(width: width(slots: 9), spacing: spacing) == 6)
    }

    @Test func anUnboundedWidthHasTwoSlots() {
        #expect(TileGrid.slots(width: .infinity) == 2)
    }

    @Test func aSmallTileIsNeverNarrowerThanItsMinimum() {
        for width in stride(from: CGFloat(332), through: 3000, by: 7) {
            #expect(TileGrid.smallWidth(width: width) >= TileGrid.minimumSmallWidth, "width \(width)")
        }
    }
}
