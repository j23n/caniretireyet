import SwiftUI
import Tracker

extension AccountGroup {
    /// The group's dot in the sidebar: cash blue, investments green, crypto
    /// and gold yellow, pension violet, property gray, debts orange. A small
    /// mark, so in ``Palette``'s line steps, which reach 3:1 on the card and
    /// the page.
    var color: Color {
        switch self {
        case .cash: Palette.blue
        case .investments: Palette.green
        case .cryptoAndGold: Palette.yellowStroke
        case .pension: Palette.violet
        case .property: Palette.mutedInk
        case .debts: Palette.orangeStroke
        case .other: Palette.secondaryInk
        }
    }
}
