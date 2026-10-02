import Foundation
import TaxKit

/// `ch.bvg`: the occupational pension fund (2nd pillar, BVG/LPP). See
/// docs/tax/CH.md, "Occupational pension".
///
/// - **Record.** The retirement assets in CHF (`montante`): the plan's
///   `startingBalance` (from the pension certificate, or the value of the
///   accounts with the seed wrapper `ch.bvg`), growing by `realInterest`,
///   plus the age credits from work and buy-ins.
/// - **Claim.** One age from 58 to 70, with three routes: the annuity
///   (`ch.bvg.annuity`), all of it as a lump sum (`ch.bvg.capital`), and
///   `lumpSumShare` as a lump sum with the rest as an annuity
///   (`ch.bvg.partialCapital`). The route matching `lumpSumShare` comes
///   first, so it's the default; the plan's `claimRoute` picks another. The
///   annuity is the assets × the fund's conversion rate for the age; it's
///   nominal, so in today's money it falls by `inflation` a year.
/// - **Leaving work before 58.** The assets move to a vested-benefits
///   account (`ch.vestedBenefits`), untaxed, whatever the route.
public struct BVGPensionScheme: PensionScheme {
    /// `ch.bvg`.
    public static let schemeID = "ch.bvg"

    public let id = BVGPensionScheme.schemeID
    public let name = "BVG (pension fund)"
    /// The plan assumptions' defaults, from the parameter file.
    let defaults: SwissParameters.BVGDefaults?

    /// The scheme with the defaults of the bundled parameter file.
    public init() {
        let store = SwissTaxSystem.bundledParameters
        let latest = store.years.last.flatMap { try? store.parameters(for: $0) }.flatMap { try? SwissParameters($0) }
        self.init(defaults: latest?.bvgDefaults)
    }

    init(defaults: SwissParameters.BVGDefaults?) {
        self.defaults = defaults
    }

    /// Accounts that hold a pension-fund balance.
    public var seedWrapper: String? { SwissWrapper.bvg }

    public var options: [OptionField] {
        [
            .money("startingBalance", "Retirement assets", default: 0,
                   help: "From your pension certificate (Vorsorgeausweis), in the plan's currency. Accounts with the "
                       + "wrapper ch.bvg fill it in."),
            .percent("mandatoryShare", "Share of the assets in the mandatory part", default: 1,
                     help: "Matters to countries that tax the mandatory part differently, and on leaving for the EU."),
            .percent("conversionRate", "Conversion rate at 65", default: defaults?.conversionRateAt65, range: 0...0.1,
                     help: "Your fund's rate on all the assets (the legal 6.8% applies to the mandatory part only)."),
            .percent("conversionRateStepPerYear", "Change of the rate per year of age",
                     default: defaults?.conversionRateStepPerYear, range: 0...0.01,
                     help: "Lower for each year before 65, higher after."),
            .percent("lumpSumShare", "Share taken as a lump sum", default: 0,
                     help: "The law allows at least a quarter of the mandatory assets; many funds allow it all."),
            .percent("realInterest", "Interest credited above Swiss inflation", default: defaults?.realInterest,
                     range: -0.05...0.1),
            .percent("inflation", "Swiss inflation", default: defaults?.inflation, range: -0.05...0.2,
                     help: "The annuity is nominal, so in today's money it falls by this a year."),
        ]
    }

    public func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore) -> PensionRecord {
        startingRecord(options: options, year: year, parameters: parameters, currencyRate: 1)
    }

    /// The record from `startingBalance` (in the plan's currency, converted to CHF).
    public func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore,
                               currencyRate: Double) -> PensionRecord {
        let options = options.withDefaults(from: self.options)
        return PensionRecord(scheme: id, montante: max(0, options.double("startingBalance", default: 0)) * currencyRate)
    }

    public func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                       parameters: ParameterSet) {
        accrue(accruals, in: year, to: &record, options: options, parameters: parameters, currencyRate: 1)
    }

    /// Credits the year's interest, then the age credits and buy-ins (in
    /// the plan's currency).
    public func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                       parameters: ParameterSet, currencyRate: Double) {
        let options = options.withDefaults(from: self.options)
        record.montante *= 1 + options.double("realInterest", default: 0)
        let credits = accruals.filter { $0.target == .pensionScheme(id) }.reduce(0) { $0 + max(0, $1.amount) }
        record.montante += credits * currencyRate
    }

    /// The claim options for the assets: the transfer to vested benefits
    /// when work stopped before the earliest age, otherwise the three routes
    /// at each age from the earliest (or the context's) to the latest.
    public func claimOptions(for record: PensionRecord, context: ClaimContext, parameters: any ParameterStore)
        -> [ClaimOption] {
        let assets = record.montante
        guard assets > 0, let set = try? parameters.parameters(for: context.year) else { return [] }
        let root = ParameterNode(set)
        let earliest = (try? root["bvg"]["earliestRetirementAge"].int()) ?? 58
        let latest = (try? root["bvg"]["latestRetirementAgeIfWorking"].int()) ?? 70
        let referenceAge = (try? root["ahvPension"]["referenceAge"].int()) ?? 65
        let options = context.options.withDefaults(from: self.options)
        let currentAge = context.year - context.birthDate.year
        let mandatory = min(1, max(0, options.double("mandatoryShare", default: 1)))

        if let stopped = context.yearsSinceWorkStopped, currentAge - stopped < earliest {
            let transfer = context.inPlanCurrency(assets)
            let note = "Work stopped before \(earliest): the assets move to a vested-benefits account, untaxed."
            return Self.routes.map { route in
                ClaimOption(route: route, label: "Transfer to vested benefits", age: currentAge, annualAmount: 0,
                            note: note, lumpSum: transfer, lumpSumWrapper: SwissWrapper.vestedBenefits,
                            mandatoryShare: mandatory)
            }
        }

        let share = min(1, max(0, options.double("lumpSumShare", default: 0)))
        var routes: [(id: String, share: Double)] = [(Self.annuityRoute, 0), (Self.capitalRoute, 1)]
        if share >= 1 {
            routes.reverse()
        } else if share > 0 {
            routes.insert((Self.partialRoute, share), at: 0)
        }
        let conversion = options.double("conversionRate", default: 0)
        let step = options.double("conversionRateStepPerYear", default: 0)
        let interest = options.double("realInterest", default: 0)
        let inflation = options.double("inflation", default: 0)
        let growth = inflation != 0 ? 1 / (1 + inflation) - 1 : nil
        var result: [ClaimOption] = []
        for age in max(earliest, currentAge)...max(latest, currentAge) {
            let projected = assets * pow(1 + interest, Double(max(0, age - currentAge)))
            let rate = max(0, conversion + step * Double(min(age, latest) - referenceAge))
            for route in routes {
                let lumpSum = projected * route.share
                let annuity = projected * (1 - route.share) * rate
                let label: String
                switch route.id {
                case Self.annuityRoute: label = "BVG annuity (\(percent(rate)) of \(francs(projected)))"
                case Self.capitalRoute: label = "BVG lump sum"
                default: label = "BVG \(percent(route.share)) as a lump sum, the rest as an annuity"
                }
                result.append(ClaimOption(
                    route: route.id, label: label, age: age, annualAmount: context.inPlanCurrency(annuity),
                    note: "Conversion rate \(percent(rate)) at \(age).",
                    lumpSum: lumpSum > 0 ? context.inPlanCurrency(lumpSum) : nil,
                    realGrowthPerYear: annuity > 0 ? growth : nil, mandatoryShare: mandatory))
            }
        }
        return result
    }

    /// An occupational pension, as other countries' systems see it.
    public func pensionKind(options: OptionValues) -> PensionKind? {
        .occupational
    }

    static let annuityRoute = "ch.bvg.annuity"
    static let capitalRoute = "ch.bvg.capital"
    static let partialRoute = "ch.bvg.partialCapital"
    static let vestedBenefitsRoute = "ch.bvg.vestedBenefits"
    /// Every route, so a plan's route still finds the transfer to vested benefits.
    static let routes = [vestedBenefitsRoute, annuityRoute, capitalRoute, partialRoute]
}
