import Model
import SwiftUI
import Tracker

/// The chosen year's pay on So far, as a wide tile (UI.md, "So far"): "💶
/// Your pay in 2026 so far", the lines of Today's *Your pay* (what came in,
/// what went into a pension and the tax when there's some, what was spent,
/// then what that left saved), and a grey line for the year's one-offs,
/// which aren't counted; beside them the ring, with what was saved of the
/// pay after tax, the year's savings rate, over the plan's own.
struct SoFarPayTile: View {
    let title: String
    let pay: WhatMoved.Pay
    /// The year's one-offs, neither came in nor saved; zero without any.
    var oneOffs: Decimal = 0
    /// The plan's own savings rate.
    var planRate: Decimal?

    var body: some View {
        ColorTile {
            TileLabel(title, emoji: "💶")
                .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.s)
            HStack(alignment: .center, spacing: Metrics.l) {
                VStack(alignment: .leading, spacing: 5) {
                    TodayMovedLedger(lines: TodayMoved.payLines(pay), signed: false)
                    if oneOffs != 0 {
                        notCounted
                    }
                }
                TodayPayRing(pay: pay, planRate: planRate)
                    .frame(width: 96, height: 96)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Not counted: one-offs 20.000 €", in grey, with a hollow dot.
    private var notCounted: some View {
        HStack(spacing: Metrics.s) {
            Circle()
                .strokeBorder(Palette.mutedInk, lineWidth: 1.5)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text("Not counted: one-offs")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            AmountText(oneOffs)
                .lineLimit(1)
                .fixedSize()
        }
        .font(.footnote)
        .foregroundStyle(Palette.secondaryInk)
    }
}

#Preview("Your pay in a year") {
    let pay = WhatMoved.Pay(moneyIn: 52_400, pension: 5_200, tax: 9_800, saved: 14_800)
    VStack(spacing: Metrics.m) {
        TileGrid {
            SoFarPayTile(title: "Your pay in 2026 so far", pay: pay, planRate: Decimal(string: "0.28"))
                .tileSize(.wide)
        }
        TileGrid {
            SoFarPayTile(title: "Your pay in 2025", pay: pay, oneOffs: 20_000, planRate: Decimal(string: "0.28"))
                .tileSize(.wide)
        }
    }
    .padding()
    .background(Palette.page)
    .previewEnvironment()
}
