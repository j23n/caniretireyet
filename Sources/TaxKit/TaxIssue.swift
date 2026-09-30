/// A problem found in a plan or while assessing a year, e.g. "Impatriati
/// doesn't apply to forfettario income: you lose the 2029 exemption."
public struct TaxIssue: Hashable, Sendable {
    /// Errors block a run (e.g. an unknown regime ID); warnings are shown with the results.
    public enum Severity: String, Hashable, Sendable, Comparable {
        case warning
        case error

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs == .warning && rhs == .error
        }
    }

    public var severity: Severity
    /// A stable machine-readable code, e.g. `it.forfettario.revenueLimit`.
    public var code: String
    /// A message for the user.
    public var message: String
    /// The year it concerns, if any.
    public var year: Int?
    /// The regime it concerns, if any.
    public var regime: String?
    /// The option it concerns, if any, so the editor can highlight the field.
    public var option: String?

    public init(_ severity: Severity, code: String, message: String, year: Int? = nil, regime: String? = nil,
                option: String? = nil) {
        self.severity = severity
        self.code = code
        self.message = message
        self.year = year
        self.regime = regime
        self.option = option
    }

    public static func error(_ code: String, _ message: String, year: Int? = nil, regime: String? = nil,
                             option: String? = nil) -> TaxIssue {
        TaxIssue(.error, code: code, message: message, year: year, regime: regime, option: option)
    }

    public static func warning(_ code: String, _ message: String, year: Int? = nil, regime: String? = nil,
                               option: String? = nil) -> TaxIssue {
        TaxIssue(.warning, code: code, message: message, year: year, regime: regime, option: option)
    }
}
