import Model
import Tracker

// SF Symbol names used across the app, so a kind of thing has one icon.

extension AccountKind {
    /// The account kind's icon, e.g. for account rows and the add-account grid.
    var systemImage: String {
        switch self {
        case .cash: "banknote"
        case .savings: "building.columns"
        case .brokerage: "chart.line.uptrend.xyaxis"
        case .crypto: "bitcoinsign.circle"
        case .metals: "circle.hexagongrid"
        case .pensionFund: "umbrella"
        case .tfr: "briefcase"
        case .property: "house"
        case .vehicle: "car"
        case .loan: "arrow.down.circle"
        case .mortgage: "house.lodge"
        case .creditCard: "creditcard"
        default: "square.stack"
        }
    }

    /// An English name, e.g. "Pension fund".
    var displayName: String {
        switch self {
        case .cash: "Current account"
        case .savings: "Savings"
        case .brokerage: "Brokerage"
        case .crypto: "Crypto wallet"
        case .metals: "Precious metals"
        case .pensionFund: "Pension fund"
        case .tfr: "TFR"
        case .property: "Property"
        case .vehicle: "Vehicle"
        case .loan: "Loan"
        case .mortgage: "Mortgage"
        case .creditCard: "Credit card"
        case .other: "Other"
        default: rawValue
        }
    }
}

extension AccountGroup {
    /// The group's icon in the sidebar and section headers.
    var systemImage: String {
        switch self {
        case .cash: "banknote"
        case .investments: "chart.line.uptrend.xyaxis"
        case .cryptoAndGold: "bitcoinsign.circle"
        case .pension: "umbrella"
        case .property: "house"
        case .debts: "creditcard"
        case .other: "square.stack"
        }
    }
}

/// Icons for places in the app.
enum AppSymbol {
    static let overview = "chart.line.uptrend.xyaxis"
    static let accounts = "list.bullet.rectangle"
    static let plan = "chart.pie"
    static let checkIn = "checklist"
    static let settings = "gearshape"
    static let importData = "square.and.arrow.down"
    static let instruments = "tag"
    static let sync = "arrow.triangle.2.circlepath.icloud"
    static let hideAmounts = "eye.slash"
    static let showAmounts = "eye"
    static let closed = "archivebox"
}
