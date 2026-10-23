import Foundation

/// Plus's products in the App Store (App/Config/Plus.storekit, and App Store
/// Connect): a yearly subscription, with a month free for new subscribers,
/// and a lifetime purchase.
enum PlusProduct: String, CaseIterable, Sendable {
    case yearly = "com.j23n.caniretireyet.plus.yearly"
    case lifetime = "com.j23n.caniretireyet.plus.lifetime"

    var id: String { rawValue }
}

/// A purchase of a Plus product, as the App Store reports it (a verified
/// `Transaction` from `Transaction.currentEntitlements`), without StoreKit,
/// so ``PlusAccess`` can be worked out and tested from plain values.
struct PlusPurchase: Equatable, Sendable {
    var productID: String
    /// When a subscription's period ends, or ended if it's in its Billing
    /// Grace Period; `nil` for the lifetime purchase.
    var expiresAt: Date?
    /// When the App Store refunded or revoked it.
    var revokedAt: Date?
    /// Whether the period is the free month new subscribers get.
    var isFreeTrial = false
}

/// Whether this person has Plus, and how (UI.md, "Plus"): the one answer
/// screens ask, through ``PlusStore``.
///
/// A subscription that has lapsed is ``free`` again: the plans and files
/// it made stay, and only Plus's actions lock again.
enum PlusAccess: Equatable, Sendable {
    /// No Plus: tracking, check-ins, import, widgets and one plan with its answer.
    case free
    /// The yearly subscription's free month, until `endsAt`; in the past
    /// during a Billing Grace Period.
    case trial(endsAt: Date)
    /// The yearly subscription, paid up to `renewsAt`; in the past during a
    /// Billing Grace Period.
    case yearly(renewsAt: Date)
    /// The lifetime purchase.
    case lifetime

    var hasPlus: Bool { self != .free }

    /// The access `purchases` give at `now`: the lifetime purchase, else the
    /// yearly subscription (the period that runs longest), else none.
    /// Revoked purchases and other products don't count.
    ///
    /// `purchases` are the App Store's current entitlements, which list a
    /// subscription only while it's active. That includes its Billing Grace
    /// Period, after its period has ended, so a period's end isn't checked
    /// here: a subscriber whose renewal is being retried keeps Plus.
    init(purchases: [PlusPurchase], at now: Date) {
        let valid = purchases.filter { $0.revokedAt.map { $0 > now } ?? true }
        if valid.contains(where: { $0.productID == PlusProduct.lifetime.id }) {
            self = .lifetime
            return
        }
        let yearly = valid
            .filter { $0.productID == PlusProduct.yearly.id }
            .compactMap { purchase in purchase.expiresAt.map { (purchase, $0) } }
            .max { $0.1 < $1.1 }
        if case let (purchase, end)? = yearly {
            self = purchase.isFreeTrial ? .trial(endsAt: end) : .yearly(renewsAt: end)
        } else {
            self = .free
        }
    }
}

/// What Plus adds that an action asked for: the paywall opens on it.
enum PlusFeature: String, Identifiable, Sendable {
    /// *New Plan* or *Duplicate* when there's a plan already.
    case morePlans
    /// The plan's levers, and *Save as Plan…* from them.
    case whatIf
    /// *Save Baseline…* and *Add a Past Baseline…*.
    case baselines
    /// *Export Calculations…*.
    case exportCalculations

    var id: String { rawValue }

    /// The paywall's title for it.
    var title: String {
        switch self {
        case .morePlans: "More plans come with Plus"
        case .whatIf: "The levers come with Plus"
        case .baselines: "Baselines come with Plus"
        case .exportCalculations: "Export Calculations comes with Plus"
        }
    }
}
