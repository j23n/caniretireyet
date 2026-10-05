import Model

/// The part of a plan an issue concerns, so the editor can show it on the
/// right card. Mirrors the plan file's sections, plus `person` for the
/// library's birth date.
public struct PlanSection: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    /// The person in `library.json` (the birth date).
    public static let person: PlanSection = "person"
    public static let retirement: PlanSection = "retirement"
    public static let tax: PlanSection = "tax"
    public static let work: PlanSection = "work"
    public static let spending: PlanSection = "spending"
    public static let pensions: PlanSection = "pensions"
    public static let contributions: PlanSection = "contributions"
    public static let events: PlanSection = "events"
    public static let portfolio: PlanSection = "portfolio"
    public static let assumptions: PlanSection = "assumptions"
    public static let simulation: PlanSection = "simulation"
}

/// A problem with a plan, found while interpreting it. Errors stop a run;
/// warnings are shown with the results.
public struct PlanIssue: Hashable, Sendable {
    /// How serious an issue is.
    public enum Severity: String, Hashable, Sendable {
        /// The plan can't run until it's fixed.
        case error
        /// The plan runs; the result may not be what you meant.
        case warning
    }

    public var severity: Severity
    /// A stable identifier, e.g. `planner.noNetIncome`.
    public var code: String
    /// A sentence for the user.
    public var message: String
    public var section: PlanSection
    /// The index of the item in a list section (a work phase, a pension, …).
    public var index: Int?
    /// The calendar year it concerns, if any.
    public var year: Int?
    /// The field it concerns, e.g. `investmentRate`.
    public var option: String?
    /// The account it concerns, if any.
    public var account: AccountID?

    public init(_ severity: Severity, code: String, message: String, section: PlanSection, index: Int? = nil,
                year: Int? = nil, option: String? = nil, account: AccountID? = nil) {
        self.severity = severity
        self.code = code
        self.message = message
        self.section = section
        self.index = index
        self.year = year
        self.option = option
        self.account = account
    }

    public var isError: Bool { severity == .error }

    static func error(_ code: String, _ message: String, section: PlanSection, index: Int? = nil,
                      year: Int? = nil, option: String? = nil, account: AccountID? = nil) -> PlanIssue {
        PlanIssue(.error, code: code, message: message, section: section, index: index, year: year, option: option,
                  account: account)
    }

    static func warning(_ code: String, _ message: String, section: PlanSection, index: Int? = nil,
                        year: Int? = nil, option: String? = nil, account: AccountID? = nil) -> PlanIssue {
        PlanIssue(.warning, code: code, message: message, section: section, index: index, year: year,
                  option: option, account: account)
    }
}

/// Why a run couldn't start.
public enum PlannerError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The plan has errors (and possibly warnings); fix the errors and run again.
    case invalidPlan([PlanIssue])

    /// Every issue found, errors and warnings.
    public var issues: [PlanIssue] {
        switch self {
        case .invalidPlan(let issues): issues
        }
    }

    public var description: String {
        switch self {
        case .invalidPlan(let issues):
            "The plan can't run: " + issues.filter(\.isError).map(\.message).joined(separator: " ")
        }
    }
}
