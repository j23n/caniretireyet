import Foundation
import Importer
import Model

/// What a value of the file's type column is read as, in the Types step.
enum ImportTypeChoice: Hashable, Sendable {
    /// Its rows become trades of this type.
    case type(TradeType)
    /// Its rows are left out (`ignore` in the profile's `tradeTypes`).
    case ignore
    /// Not mapped yet: its rows are left out and flagged.
    case unmapped
}

/// A value of the file's type column, e.g. "Acquisto", and the trade type
/// its rows become, for the Types step.
struct ImportTypeRow: Identifiable, Hashable, Sendable {
    /// The value as the file writes it.
    var value: String
    var id: String { value }
    /// How many rows have it.
    var count: Int
    var choice: ImportTypeChoice
    var source: TradeTypeValue.Source
    /// What the usual words suggest for it, if anything.
    var suggestion: TradeType?

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
    /// Every value of the type column, in the order the file has them.
    var typeRows: [ImportTypeRow] {
        (session?.tradeTypeValues ?? []).map { value in
            let choice: ImportTypeChoice = if value.isIgnored { .ignore }
                else { value.type.map(ImportTypeChoice.type) ?? .unmapped }
            return ImportTypeRow(value: value.value, count: value.count, choice: choice, source: value.source,
                                 suggestion: value.suggestion)
        }
    }

    /// Whether the file has a type column; without one, a negative quantity is a sell.
    var hasTypeColumn: Bool { session?.tradeTypeColumn != nil }

    /// The choices for a type, in menu order: the trade types, then leaving the rows out.
    static let typeChoices: [ImportTypeChoice] = TradeTypeWords.choices.map(ImportTypeChoice.type) + [.ignore]

    /// Maps a type value; its rows follow. Remembered in the profile, if saved.
    mutating func setTradeType(_ choice: ImportTypeChoice, for value: String) {
        editSession { session in
            switch choice {
            case .type(let type): session.setTradeType(type, for: value)
            case .ignore: session.setTradeType(TradeTypeWords.ignore, for: value)
            case .unmapped: session.setTradeType(nil, for: value)
            }
        }
    }

    /// Goes back to what the usual words suggest for a value.
    mutating func resetTradeType(for value: String) {
        editSession { $0.setTradeType(nil, for: value) }
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

    static func typeChoiceName(_ choice: ImportTypeChoice) -> String {
        switch choice {
        case .type(let type): TradeTypeDisplay.name(type)
        case .ignore: "Leave out"
        case .unmapped: "Choose…"
        }
    }

    static func amountSignName(_ sign: TradeAmountSign) -> String {
        switch sign {
        case .fromType: "Without signs: from the type"
        case .asWritten: "Signed: as written"
        default: "Automatic"
        }
    }
}
