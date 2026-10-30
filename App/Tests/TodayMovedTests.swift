import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// Today's *Your pay* and *Your net worth* tiles (UI.md, "What moved it"):
/// which lines they show, the net worth tile's steps and the pay tile's
/// ring.
struct TodayMovedTests {
    private func moved(saved: Decimal = 1880, markets: Decimal = -1120, oneOffs: Decimal = 0,
                       startedWith: Decimal = 0, lost: Decimal = 0, unexplained: Decimal = 0,
                       pay: WhatMoved.Pay? = nil) -> WhatMoved {
        WhatMoved(from: "2026-09-30", to: "2026-10-31", start: 300_000,
                  change: saved + markets + oneOffs + startedWith + lost + unexplained, saved: saved,
                  markets: markets, oneOffs: oneOffs, startedWith: startedWith, lost: lost, pay: pay)
    }

    @Test func payShowsTaxAndPensionOnlyWhenThereAreSome() {
        let plain = WhatMoved.Pay(moneyIn: 4810, pension: 0, tax: 0, saved: 1880)
        #expect(TodayMoved.payLines(plain).map(\.kind) == [.cameIn, .spent, .saved])
        let full = WhatMoved.Pay(moneyIn: 5900, pension: 520, tax: 1610, saved: 1880)
        let lines = TodayMoved.payLines(full)
        #expect(lines.map(\.kind) == [.cameIn, .pension, .tax, .spent, .saved])
        // Tax and spent are money that left.
        #expect(lines.map(\.amount) == [5900, 520, -1610, -2930, 1880])
        #expect(lines.last?.isSum == true)
        // What was saved of the pay after tax: 1.880 of 4.810.
        #expect(full.savedShare?.rounded(scale: 4) == Decimal(string: "0.3909"))
    }

    @Test func netWorthShowsTheRestOnlyWhenItIsntZero() {
        #expect(TodayMoved.netWorthLines(moved()).map(\.kind) == [.saved, .markets, .total])
        #expect(TodayMoved.netWorthLines(moved(markets: 0)).map(\.kind) == [.saved, .total])
        let two = TodayMoved.netWorthLines(moved(oneOffs: 250, startedWith: 400))
        #expect(two.map(\.kind) == [.saved, .markets, .oneOff, .startedWith, .total])
        #expect(two.last?.amount == 1410)
    }

    /// More than two parts besides saved and markets fold into one Other.
    @Test func manyPartsFoldIntoOther() {
        let lines = TodayMoved.netWorthLines(moved(oneOffs: 250, startedWith: 400, lost: -90))
        #expect(lines.map(\.kind) == [.saved, .markets, .other, .total])
        #expect(lines[2].amount == 560)
        #expect(lines.last?.amount == 1320)
    }

    /// Each bar starts where the one before ended; the sum starts at zero.
    @Test func stepsRunFromWhereTheLineBeforeEnded() {
        let steps = TodayMoved.steps(TodayMoved.netWorthLines(moved(oneOffs: 250)))
        #expect(steps == [0...1880, 760...1880, 760...1010, 0...1010])
    }

    @Test func theRingSharesWhatCameIn() {
        let ring = TodayMoved.ring(WhatMoved.Pay(moneyIn: 6420, pension: 0, tax: 1610, saved: 1880))
        #expect(ring.map(\.kind) == [.saved, .spent, .tax])
        #expect(abs(ring.map(\.share).reduce(0, +) - 1) < 1e-9)
        // Nothing saved: no slice for it.
        let spentItAll = TodayMoved.ring(WhatMoved.Pay(moneyIn: 3000, pension: 0, tax: 0, saved: -200))
        #expect(spentItAll.map(\.kind) == [.spent])
    }
}
