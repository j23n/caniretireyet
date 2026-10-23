import Foundation
import Observation
import StoreKit

/// Plus, the paid tier (UI.md, "Plus"), with StoreKit 2: its products and
/// their prices, whether this person has it (``access``, from
/// `Transaction.currentEntitlements`), *Restore Purchases*, and the paywall
/// an action opens without it (``unlock(_:then:)``). Screens ask
/// ``hasPlus`` or call ``unlock(_:then:)``; none of them asks StoreKit.
///
/// Nothing in the library's files depends on Plus, and the CLI has every
/// feature. A subscription that lapses locks only Plus's actions again: the
/// plans, baselines and files made with it stay as they are.
///
/// The app shares one store, ``live``, across the models its session opens
/// (test profiles use the same Apple Account). Previews and the screen
/// tests use one that never asks the App Store, with Plus by default.
@Observable @MainActor
final class PlusStore {
    /// The app's store, which asks the App Store.
    static let live = PlusStore(usesAppStore: true)

    /// Whether this person has Plus, and how.
    private(set) var access: PlusAccess
    /// The products' prices, once the App Store has answered.
    private(set) var prices: PlusPrices?
    /// The paywall, while it's shown over the app (`AppPresentation`).
    var offer: PlusOffer?

    var hasPlus: Bool { access.hasPlus }

    /// The products, for buying them.
    @ObservationIgnored private var products: [PlusProduct: Product] = [:]
    /// What the paywall was opened for, run once it closes with Plus.
    @ObservationIgnored private var unlockedAction: (@MainActor () -> Void)?
    private let usesAppStore: Bool
    @ObservationIgnored private var updates: Task<Void, Never>?

    private init(usesAppStore: Bool) {
        self.usesAppStore = usesAppStore
        access = .free
    }

    /// A store that never asks the App Store, for previews and the screen
    /// tests: `access` stays as given.
    init(access: PlusAccess, prices: PlusPrices? = nil) {
        usesAppStore = false
        self.access = access
        self.prices = prices
    }

    /// Launch work, once: finishes transactions left unfinished, listens for
    /// new ones (a renewal, a refund, a purchase on another device or
    /// approved later), and works out ``access`` and the prices.
    func start() {
        guard usesAppStore, updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case let .verified(transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task {
            for await result in Transaction.unfinished {
                if case let .verified(transaction) = result { await transaction.finish() }
            }
            await refresh()
            await loadPrices()
        }
    }

    /// Works out ``access`` again from the App Store's current entitlements.
    func refresh() async {
        guard usesAppStore else { return }
        var purchases: [PlusPurchase] = []
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result {
                purchases.append(PlusPurchase(transaction))
            }
        }
        access = PlusAccess(purchases: purchases, at: .now)
    }

    /// Asks the App Store for the products and their prices, and whether this
    /// person may have the yearly subscription's free trial, until it answers.
    func loadPrices() async {
        guard usesAppStore, prices == nil,
              let found = try? await Product.products(for: PlusProduct.allCases.map(\.id)) else { return }
        for product in found {
            if let kind = PlusProduct(rawValue: product.id) { products[kind] = product }
        }
        guard let yearly = products[.yearly], let lifetime = products[.lifetime] else { return }
        var freeTrial: String?
        if let subscription = yearly.subscription, let intro = subscription.introductoryOffer,
           intro.paymentMode == .freeTrial, await subscription.isEligibleForIntroOffer {
            freeTrial = Self.length(of: intro.period)
        }
        prices = PlusPrices(yearly: yearly.displayPrice, lifetime: lifetime.displayPrice, freeTrial: freeTrial)
    }

    /// The product to buy, once the App Store has answered.
    func product(_ kind: PlusProduct) -> Product? {
        products[kind]
    }

    /// Runs `action` with Plus; without it, opens the paywall for
    /// `feature`, and runs `action` once the paywall closes with Plus.
    func unlock(_ feature: PlusFeature, then action: @escaping @MainActor () -> Void) {
        if hasPlus {
            action()
        } else {
            unlockedAction = action
            offer = PlusOffer(feature: feature)
        }
    }

    /// The paywall closed: runs what it was opened for, if Plus was bought.
    func offerClosed() {
        let action = unlockedAction
        unlockedAction = nil
        if hasPlus { action?() }
    }

    /// Takes a purchase's result: finishes the transaction and works out
    /// ``access`` again. Returns whether it was bought, or throws what to say.
    func complete(_ result: Product.PurchaseResult) async throws -> Bool {
        switch result {
        case let .success(verification):
            guard case let .verified(transaction) = verification else { throw PlusError.unverified }
            await transaction.finish()
            await refresh()
            return hasPlus
        case .pending:
            throw PlusError.pending
        default:
            // Cancelled.
            return false
        }
    }

    /// *Restore Purchases*: asks the App Store for this Apple Account's
    /// purchases (it may ask to sign in), then works out ``access`` again.
    /// Returns what to say; `nil` when the person cancelled.
    func restore() async -> String? {
        guard usesAppStore else { return nil }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return nil
        } catch {
            return error.localizedDescription
        }
        await refresh()
        return hasPlus ? "Plus is back." : "This Apple Account hasn't bought Plus."
    }

    /// "month", "2 weeks": how long a free trial lasts, after "First".
    private static func length(of period: Product.SubscriptionPeriod) -> String {
        let units: [(Product.SubscriptionPeriod.Unit, String)] = [
            (.day, "day"), (.week, "week"), (.month, "month"), (.year, "year"),
        ]
        let unit = units.first { $0.0 == period.unit }?.1 ?? "period"
        return period.value == 1 ? unit : "\(period.value) \(unit)s"
    }
}

/// The products' prices as the App Store gives them, in the person's
/// storefront's currency ("34,99 €").
struct PlusPrices: Equatable, Sendable {
    /// A year of the subscription.
    var yearly: String
    /// The lifetime purchase.
    var lifetime: String
    /// How long the yearly subscription's free trial is ("month"), when this
    /// person may have it: new subscribers only.
    var freeTrial: String?

    /// Made-up prices, for previews and the screens opened without the App Store.
    static let sample = PlusPrices(yearly: "34,99 €", lifetime: "99,99 €", freeTrial: "month")
}

/// The paywall, shown for a feature (``PlusStore/unlock(_:then:)``).
struct PlusOffer: Identifiable {
    let id = UUID()
    var feature: PlusFeature?
}

/// Why a purchase didn't give Plus.
enum PlusError: LocalizedError {
    /// Waiting for approval, e.g. Ask to Buy.
    case pending
    /// The App Store's signature didn't check out.
    case unverified

    var errorDescription: String? {
        switch self {
        case .pending: "The purchase is waiting for approval. Plus starts once it's approved."
        case .unverified: "The App Store couldn't confirm the purchase. Try Restore Purchases."
        }
    }
}

extension PlusPurchase {
    /// A verified transaction from the App Store.
    init(_ transaction: Transaction) {
        self.init(productID: transaction.productID, expiresAt: transaction.expirationDate,
                  revokedAt: transaction.revocationDate,
                  isFreeTrial: transaction.offer?.paymentMode == .freeTrial)
    }
}
