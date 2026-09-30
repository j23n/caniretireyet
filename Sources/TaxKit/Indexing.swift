/// Converts amounts written in a parameter file, which are nominal euros of
/// the file's tax year, into the planner's today's euros for a simulated
/// year. Multiply thresholds and fixed amounts by the factor (or scale a
/// schedule with its `scaled(by:)`).
///
/// - Up to the file's tax year, and in every year when the plan doesn't
///   index thresholds, amounts are fixed in nominal euros, so they shrink in
///   today's euros as prices rise (fiscal drag): the factor is
///   `1 / inflationFactor`.
/// - After the file's tax year, with indexing on, amounts rise with prices,
///   so they keep their value in today's euros: the factor is 1. This assumes
///   the plan starts in the file's tax year; when it starts later, the
///   file's amounts are treated as already being in the plan's euros.
public enum ThresholdIndexing {
    /// The factor for amounts from a file for `parameterYear`, used in `year`.
    public static func scale(year: Int, parameterYear: Int, inflationFactor: Double, indexThresholds: Bool) -> Double {
        guard inflationFactor > 0, inflationFactor.isFinite else { return 1 }
        if indexThresholds && year > parameterYear { return 1 }
        return 1 / inflationFactor
    }

    /// The factor for `year`'s amounts from a file for `parameterYear`.
    public static func scale(for year: FixedYear, parameterYear: Int) -> Double {
        scale(year: year.year, parameterYear: parameterYear, inflationFactor: year.inflationFactor,
              indexThresholds: year.indexThresholds)
    }
}

/// A value that changes from given years on, e.g. a pension age that rises
/// by a month in 2027 and by three months in total from 2028, optionally
/// continuing by a fixed step every year after the last change.
///
/// In a parameter file: `{ "value": 0, "changes": [ { "from": 2027, "value": 1 }, { "from": 2028, "value": 3 } ] }`.
public struct YearSchedule: Hashable, Sendable {
    /// A new value from a year on.
    public struct Change: Hashable, Sendable {
        public var from: Int
        public var value: Double

        public init(from: Int, value: Double) {
            self.from = from
            self.value = value
        }
    }

    /// The value before the first change.
    public var initial: Double
    /// Changes in ascending order of year.
    public var changes: [Change]
    /// Added once for every year after the last change (0 for none).
    public var yearlyStepAfterLastChange: Double

    public init(initial: Double, changes: [Change] = [], yearlyStepAfterLastChange: Double = 0) {
        self.initial = initial
        self.changes = changes.sorted { $0.from < $1.from }
        self.yearlyStepAfterLastChange = yearlyStepAfterLastChange
    }

    /// Reads `value` and the optional `changes`.
    public init(_ node: ParameterNode) throws {
        let changes = try node["changes"].optionalList().map { change in
            Change(from: try change["from"].int(), value: try change["value"].double())
        }
        self.init(initial: try node["value"].double(), changes: changes)
    }

    /// The value in force in `year`.
    public func value(in year: Int) -> Double {
        guard let current = changes.last(where: { $0.from <= year }) else { return initial }
        guard let last = changes.last, current == last, yearlyStepAfterLastChange != 0 else { return current.value }
        return last.value + Double(year - last.from) * yearlyStepAfterLastChange
    }
}
