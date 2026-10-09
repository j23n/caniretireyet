import Foundation
import Importer
import Model

/// A value of the file's type column, e.g. "Acquisto", as the Types step
/// shows it.
extension TradeTypeValue {
    /// "Usual word", "Set by you", "Not mapped".
    var sourceTitle: String {
        switch source {
        case .profile: "Set by you or the profile"
        case .suggested: "The usual word"
        case .unmapped: "Not mapped: its rows are left out"
        }
    }

    /// Whether choosing again can go back to the suggestion.
    var canReset: Bool { source == .profile && suggestion != nil }
}

/// The Types step of a broker's transactions (the trades layout): each type
/// word of the file mapped to a trade type, and how amounts are signed.
extension ImportFlow {
    /// Every value of the type column, in the order the file has them, with
    /// the trade type its rows become.
    var typeRows: [TradeTypeValue] { session?.tradeTypeValues ?? [] }

    /// Whether the file has a type column; without one, a negative quantity is a sell.
    var hasTypeColumn: Bool { session?.tradeTypeColumn != nil }

    /// The choices for a type, in menu order: the trade types, then leaving
    /// the rows out (``TradeTypeWords/ignore``).
    static let typeChoices: [TradeType] = TradeTypeWords.choices + [TradeTypeWords.ignore]

    /// Maps a type value; its rows follow. Remembered in the profile, if
    /// saved. ``TradeTypeWords/ignore`` leaves its rows out; `nil` goes back
    /// to what the usual words suggest.
    mutating func setTradeType(_ type: TradeType?, for value: String) {
        editSession { $0.setTradeType(type, for: value) }
    }

    /// How the file's amounts are signed: the profile's setting (default: auto).
    var amountSign: TradeAmountSign {
        session?.profile.defaults.amountSign ?? .auto
    }

    mutating func setAmountSign(_ sign: TradeAmountSign) {
        editSession { $0.profile.defaults.amountSign = sign == .auto ? nil : sign }
    }

    /// How signs and quantities were read, e.g. "“Importo”: amounts are
    /// signed, so their signs were kept…".
    var tradeSignNotes: [String] {
        (preview?.issues ?? []).filter { issue in
            switch issue.kind {
            case .tradeAmountSigns, .negativeQuantities, .cashDirectionBySign, .ignoredTradeRows: true
            default: false
            }
        }.map(\.description)
    }

    /// "Buy", "Leave out" for ``TradeTypeWords/ignore``, "Choose…" while not mapped.
    static func typeChoiceName(_ type: TradeType?) -> String {
        guard let type else { return "Choose…" }
        return type == TradeTypeWords.ignore ? "Leave out" : TradeTypeDisplay.name(type)
    }

    static func amountSignName(_ sign: TradeAmountSign) -> String {
        switch sign {
        case .fromType: "Without signs: from the type"
        case .asWritten: "Signed: as written"
        default: "Automatic"
        }
    }
}
