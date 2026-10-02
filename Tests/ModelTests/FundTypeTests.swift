import Foundation
import Model
import Testing

/// The kind of fund an ETF or fund is taxed as (PLANNER.md, "Portfolio"):
/// one rule for the planner, the app and the CLI. All made up.
struct FundTypeTests {
    private static func d(_ string: String) -> Decimal { Decimal(fileString: string)! }

    private func fund(_ kind: InstrumentKind, _ mix: AssetMix, tax: InstrumentTax? = nil) -> Instrument {
        Instrument(id: "f", name: "F", kind: kind, currency: .usd, unit: .share, assetClasses: mix, tax: tax)
    }

    @Test func theMixDecides() {
        func type(_ mix: AssetMix) -> FundType { FundType.derived(from: mix) }
        #expect(type(.single(.equity)) == .equity)
        #expect(type([.equity: Self.d("0.6"), .bonds: Self.d("0.4")]) == .equity)
        #expect(type([.equity: Self.d("0.5"), .bonds: Self.d("0.5")]) == .mixed)
        #expect(type([.equity: Self.d("0.25"), .bonds: Self.d("0.75")]) == .mixed)
        #expect(type([.equity: Self.d("0.2"), .bonds: Self.d("0.8")]) == .other)
        #expect(type([.realEstate: Self.d("0.6"), .equity: Self.d("0.4")]) == .realEstate)
        #expect(type([.realEstate: Self.d("0.5"), .equity: Self.d("0.3"), .bonds: Self.d("0.2")]) == .mixed)
        #expect(type(.single(.bonds)) == .other)
        #expect(type(AssetMix()) == .other)
        // Shares are of the positive parts: 0.3 of 1.2 is a quarter.
        #expect(type([.equity: Self.d("0.3"), .bonds: Self.d("0.9")]) == .mixed)
        #expect(type([.equity: Self.d("0.6"), .bonds: Self.d("-0.2")]) == .equity)
    }

    @Test func aKnownFundTypeOverridesTheMix() {
        #expect(fund(.etf, .single(.equity)).effectiveFundType == .equity)
        #expect(fund(.fund, .single(.bonds)).effectiveFundType == .other)
        #expect(fund(.etf, .single(.equity), tax: InstrumentTax(fundType: .foreignRealEstate)).effectiveFundType
            == .foreignRealEstate)
        // A type this version doesn't know is derived from the mix.
        #expect(fund(.etf, .single(.equity), tax: InstrumentTax(fundType: "infrastructure")).effectiveFundType == .equity)
    }

    @Test func onlyETFsAndFundsHaveAFundType() {
        #expect(InstrumentKind.etf.hasFundType && InstrumentKind.fund.hasFundType)
        #expect(!InstrumentKind.stock.hasFundType && !InstrumentKind.etc.hasFundType)
        #expect(fund(.stock, .single(.equity)).effectiveFundType == nil)
        #expect(fund(.etc, .single(.gold), tax: InstrumentTax(fundType: .equity)).effectiveFundType == nil)
    }

    @Test func anETCMayGiveADeliveryClaim() {
        #expect(fund(.etc, .single(.gold), tax: InstrumentTax(deliveryClaim: true)).hasDeliveryClaim)
        #expect(!fund(.etc, .single(.gold)).hasDeliveryClaim)
        #expect(!fund(.etf, .single(.gold), tax: InstrumentTax(deliveryClaim: true)).hasDeliveryClaim)
    }
}
