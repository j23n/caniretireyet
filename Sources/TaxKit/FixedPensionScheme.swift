/// The shared `fixed` pension scheme: a gross yearly amount from an age, as
/// on a statement, e.g. a state pension from a previous country. It doesn't
/// build up, so it works the same under every tax system; systems list it
/// in their `pensionSchemes` so a registry always finds it.
///
/// The amount and age come from the options `perYear` and `fromAge`. A
/// plan's pension entry writes them as top-level keys (`"fromAge": 67,
/// "perYear": "4800"`); the planner passes them on as options.
public struct FixedPensionScheme: PensionScheme {
    /// `fixed`.
    public static let schemeID = "fixed"

    public let id = FixedPensionScheme.schemeID
    public let name = "Fixed pension"

    public init() {}

    public var options: [OptionField] {
        [
            .money("perYear", "Gross amount per year", required: true,
                   help: "From your statement, in today's euros."),
            .int("fromAge", "Paid from age", range: 0...120, required: true),
        ]
    }

    /// Keeps `perYear` and `fromAge` in the record's `extra`.
    public func startingRecord(options: OptionValues, year: Int, parameters: any ParameterStore) -> PensionRecord {
        var extra: [String: Double] = [:]
        extra["perYear"] = options.double("perYear")
        extra["fromAge"] = options.double("fromAge")
        return PensionRecord(scheme: id, extra: extra)
    }

    /// Nothing accrues: the amount is fixed.
    public func accrue(_ accruals: [Accrual], in year: Int, to record: inout PensionRecord, options: OptionValues,
                       parameters: ParameterSet) {}

    /// One option: `perYear` from `fromAge`, read from the context's options
    /// or else from the record. None when either is unknown.
    public func claimOptions(for record: PensionRecord, context: ClaimContext, parameters: any ParameterStore)
        -> [ClaimOption] {
        guard let amount = context.options.double("perYear") ?? record.extra["perYear"],
              let age = context.options.int("fromAge") ?? record.extra["fromAge"].map({ Int($0) })
        else { return [] }
        return [ClaimOption(route: id, label: "Fixed pension", age: age, annualAmount: amount)]
    }
}
