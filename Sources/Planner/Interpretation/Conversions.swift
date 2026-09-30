import Foundation
import Model
import TaxKit

extension Decimal {
    /// The nearest `Double`, parsed from the exact decimal string so the
    /// conversion is the same on every platform.
    var double: Double {
        Double(description) ?? NSDecimalNumber(decimal: self).doubleValue
    }

    /// `value` rounded to `scale` fractional digits, as an exact decimal.
    static func rounded(_ value: Double, scale: Int) -> Decimal {
        guard value.isFinite else { return 0 }
        var factor: Int64 = 1
        for _ in 0..<scale { factor *= 10 }
        let scaled = (value * Double(factor)).rounded()
        guard abs(scaled) < 9e15 else { return Decimal(string: String(format: "%.0f", value)) ?? 0 }
        return Decimal(Int64(scaled)) / Decimal(factor)
    }
}

extension JSONValue {
    /// This value as a TaxKit option value. Numbers become `Double`.
    var optionValue: OptionValue {
        switch self {
        case .null: .null
        case .bool(let value): .bool(value)
        case .number(let value): .number(value.double)
        case .string(let value): .string(value)
        case .array(let values): .list(values.map(\.optionValue))
        case .object(let object): .object(object.mapValues(\.optionValue))
        }
    }
}

extension OptionValues {
    /// A plan's free-form options in TaxKit's types.
    init(_ json: [String: JSONValue]) {
        self.init(json.mapValues(\.optionValue))
    }
}

extension CalendarDate {
    /// 1 January of `year`.
    static func firstDay(of year: Int) -> CalendarDate {
        CalendarDate(year: year, month: 1, day: 1)!
    }

    /// 31 December of `year`.
    static func lastDay(of year: Int) -> CalendarDate {
        CalendarDate(year: year, month: 12, day: 31)!
    }

    /// The number of days from `start` to `end`, both inclusive; 0 when `end` is before `start`.
    static func inclusiveDays(from start: CalendarDate, to end: CalendarDate) -> Int {
        max(0, start.days(to: end) + 1)
    }

    /// The birth date as TaxKit's type.
    var birthDate: BirthDate {
        BirthDate(year: year, month: month, day: day)
    }
}

/// A parameter store with a plan's overrides applied to every year.
struct OverriddenParameterStore: ParameterStore {
    let base: any ParameterStore
    let overrides: OptionValues
    /// Each file's set with the overrides applied, made once: every year
    /// using a file then gets the same set, which a tax system can cache
    /// its parsing of.
    private let sets: [Int: ParameterSet]

    init(base: any ParameterStore, overrides: OptionValues) {
        self.base = base
        self.overrides = overrides
        var sets: [Int: ParameterSet] = [:]
        for year in base.years {
            guard let set = try? base.parameters(for: year), set.year == year else { continue }
            sets[year] = overrides.isEmpty ? set : set.applying(overrides: overrides)
        }
        self.sets = sets
    }

    var system: String { base.system }
    var years: [Int] { base.years }

    func parameters(for year: Int) throws -> ParameterSet {
        if let fileYear = base.parameterYear(for: year), let set = sets[fileYear] { return set }
        let set = try base.parameters(for: year)
        return overrides.isEmpty ? set : set.applying(overrides: overrides)
    }
}
