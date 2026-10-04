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
    /// Whether the file is read as a broker's transactions: a row per trade.
    var isTrades: Bool { session?.profile.layout == .trades }

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

    /// Rows left out because their type isn't mapped.
    var unmappedTypeRows: Int {
        typeRows.filter { $0.choice == .unmapped }.reduce(0) { $0 + $1.count }
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

    /// E.g. "Buy", "Transfer in".
    static func tradeTypeName(_ type: TradeType) -> String {
        switch type {
        case .buy: "Buy"
        case .sell: "Sell"
        case .dividend: "Dividend"
        case .interest: "Interest"
        case .fee: "Fee"
        case .tax: "Tax"
        case .deposit: "Deposit"
        case .withdrawal: "Withdrawal"
        case .split: "Split"
        case .transferIn: "Transfer in"
        case .transferOut: "Transfer out"
        case .opening: "Opening"
        default: type.rawValue
        }
    }

    static func typeChoiceName(_ choice: ImportTypeChoice) -> String {
        switch choice {
        case .type(let type): tradeTypeName(type)
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
