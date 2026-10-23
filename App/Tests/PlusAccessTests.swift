import Foundation
import Testing
@testable import CanIRetireYet

/// Whether someone has Plus, from their purchases (UI.md, "Plus").
@MainActor
struct PlusAccessTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let day: TimeInterval = 86_400

    private func yearly(expires: Date, trial: Bool = false, revoked: Date? = nil) -> PlusPurchase {
        PlusPurchase(productID: PlusProduct.yearly.id, expiresAt: expires, revokedAt: revoked, isFreeTrial: trial)
    }

    private var lifetime: PlusPurchase {
        PlusPurchase(productID: PlusProduct.lifetime.id)
    }

    @Test func noPurchaseIsFree() {
        let access = PlusAccess(purchases: [], at: now)
        #expect(access == .free)
        #expect(!access.hasPlus)
    }

    @Test func theYearlyFreeMonthCountsAsPlus() {
        let end = now.addingTimeInterval(20 * day)
        let access = PlusAccess(purchases: [yearly(expires: end, trial: true)], at: now)
        #expect(access == .trial(endsAt: end))
        #expect(access.hasPlus)
    }

    @Test func anActiveYearlyIsPlus() {
        let end = now.addingTimeInterval(200 * day)
        let access = PlusAccess(purchases: [yearly(expires: end)], at: now)
        #expect(access == .yearly(renewsAt: end))
        #expect(access.hasPlus)
        #expect(PlusSection.status(access, at: now).hasPrefix("Yearly, renews "))
    }

    /// The App Store lists a subscription in its Billing Grace Period, after
    /// its period has ended, while it retries the renewal: it keeps Plus.
    /// Once the subscription lapses it isn't listed, and that's free
    /// (`noPurchaseIsFree`).
    @Test func aYearlyInItsGracePeriodIsPlus() {
        let ended = now.addingTimeInterval(-3 * day)
        let access = PlusAccess(purchases: [yearly(expires: ended)], at: now)
        #expect(access == .yearly(renewsAt: ended))
        #expect(access.hasPlus)
        #expect(PlusSection.status(access, at: now) == "Yearly, renewal pending")

        let trialEnded = PlusAccess(purchases: [yearly(expires: ended, trial: true)], at: now)
        #expect(trialEnded == .trial(endsAt: ended))
        #expect(trialEnded.hasPlus)
        #expect(PlusSection.status(trialEnded, at: now) == "Yearly, renewal pending")
    }

    @Test func lifetimeIsPlus() {
        #expect(PlusAccess(purchases: [lifetime], at: now) == .lifetime)
        // Also beside a subscription, active or not.
        let purchases = [yearly(expires: now.addingTimeInterval(30 * day)), lifetime]
        #expect(PlusAccess(purchases: purchases, at: now) == .lifetime)
    }

    @Test func aRefundedPurchaseIsFree() {
        let refunded = PlusPurchase(productID: PlusProduct.lifetime.id, revokedAt: now.addingTimeInterval(-day))
        #expect(PlusAccess(purchases: [refunded], at: now) == .free)
        let refundedYearly = yearly(expires: now.addingTimeInterval(100 * day), revoked: now.addingTimeInterval(-day))
        #expect(PlusAccess(purchases: [refundedYearly], at: now) == .free)
    }

    @Test func otherProductsDontCount() {
        let other = PlusPurchase(productID: "com.example.other", expiresAt: now.addingTimeInterval(day))
        #expect(PlusAccess(purchases: [other], at: now) == .free)
    }

    /// After the free month the paid year follows: the period that runs longest counts.
    @Test func theLatestPeriodCounts() {
        let paidEnd = now.addingTimeInterval(330 * day)
        let purchases = [yearly(expires: now.addingTimeInterval(5 * day), trial: true), yearly(expires: paidEnd)]
        #expect(PlusAccess(purchases: purchases, at: now) == .yearly(renewsAt: paidEnd))
    }

    /// Without Plus an action opens the paywall for its feature and waits;
    /// with Plus it runs at once.
    @Test func plusActionsOpenThePaywallWithoutPlus() {
        var ran = 0
        let free = PlusStore(access: .free)
        free.unlock(.morePlans) { ran += 1 }
        #expect(free.offer?.feature == .morePlans)
        #expect(ran == 0)
        free.offer = nil
        free.offerClosed()
        #expect(ran == 0)

        let plus = PlusStore(access: .trial(endsAt: now))
        plus.unlock(.whatIf) { ran += 1 }
        #expect(plus.offer == nil)
        #expect(ran == 1)
    }

    @Test func theYearlyPriceSaysTheFreeMonth() {
        #expect(PlusPaywall.yearlyDetail(.sample) == "First month free, then 34,99 € a year")
        let used = PlusPrices(yearly: "34,99 €", lifetime: "99,99 €")
        #expect(PlusPaywall.yearlyDetail(used) == "34,99 € a year")
    }
}
