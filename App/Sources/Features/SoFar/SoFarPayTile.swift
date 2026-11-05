import Model
import SwiftUI
import Tracker

/// The chosen year's pay on So far, as a wide tile (UI.md, "So far"): "💶
/// Your pay in 2026 so far", the lines of Today's *Your pay* (what came in,
/// what went into a pension and the tax when there's some, what was spent
/// and the year's one-offs when there are some, then what was saved, which
/// they add up to); beside them the ring, with what the pay saved of the
/// pay after tax, the year's savings rate, over the plan's own.
struct SoFarPayTile: View {
    let title: String
    let pay: WhatMoved.Pay
    /// The plan's own savings rate.
    var planRate: Decimal?

    var body: some View {
        ColorTile {
            TileLabel(title, emoji: "💶")
                .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.s)
            HStack(alignment: .center, spacing: Metrics.l) {
                TodayMovedLedger(lines: TodayMoved.payLines(pay), signed: false)
                TodayPayRing(pay: pay, planRate: planRate)
                    .frame(width: 96, height: 96)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Your pay in a year") {
    let pay = WhatMoved.Pay(moneyIn: 52_400, pension: 5_200, tax: 9_800, saved: 14_800)
    let withOneOff = WhatMoved.Pay(moneyIn: 52_400, pension: 5_200, tax: 9_800, saved: 34_800, oneOffs: 20_000)
    VStack(spacing: Metrics.m) {
        TileGrid {
            SoFarPayTile(title: "Your pay in 2026 so far", pay: pay, planRate: Decimal(string: "0.28"))
                .tileSize(.wide)
        }
        TileGrid {
            SoFarPayTile(title: "Your pay in 2025", pay: withOneOff, planRate: Decimal(string: "0.28"))
                .tileSize(.wide)
        }
    }
    .padding()
    .background(Palette.page)
    .previewEnvironment()
}
