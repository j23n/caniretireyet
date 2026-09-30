import Model
import TaxKit

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
    public static let withdrawals: PlanSection = "withdrawals"
    public static let simulation: PlanSection = "simulation"
}

/// A problem with a plan: found while interpreting it, by a tax system's
/// validation, or while assessing a year. Errors stop a run; warnings are
/// shown with the results.
public struct PlanIssue: Hashable, Sendable {
    /// Errors stop a run; warnings are shown with the results.
    public var severity: TaxIssue.Severity
    /// A stable machine-readable code: `planner.…` for the engine's own
    /// checks, the tax system's code otherwise.
    public var code: String
    /// A message for the user.
    public var message: String
    /// The plan section to show it on.
    public var section: PlanSection
    /// The item within the section (a work phase, pension, event, …), by position.
    public var index: Int?
    /// The year it concerns, if any.
    public var year: Int?
    /// The regime it concerns, if any.
    public var regime: String?
    /// The option it concerns, if any, so the editor can highlight the field.
    public var option: String?
    /// The account it concerns, if any.
    public var account: AccountID?

    /// An issue found by the planner.
    public init(_ severity: TaxIssue.Severity, code: String, message: String, section: PlanSection,
                index: Int? = nil, year: Int? = nil, regime: String? = nil, option: String? = nil,
                account: AccountID? = nil) {
        self.severity = severity
        self.code = code
        self.message = message
        self.section = section
        self.index = index
        self.year = year
        self.regime = regime
        self.option = option
        self.account = account
    }

    /// A tax system's issue, placed on `section`.
    public init(_ issue: TaxIssue, section: PlanSection, index: Int? = nil) {
        self.init(issue.severity, code: issue.code, message: issue.message, section: section, index: index,
                  year: issue.year, regime: issue.regime, option: issue.option)
    }

    /// Whether it stops a run.
    public var isError: Bool { severity == .error }

    static func error(_ code: String, _ message: String, section: PlanSection, index: Int? = nil,
                      year: Int? = nil, regime: String? = nil, option: String? = nil,
                      account: AccountID? = nil) -> PlanIssue {
        PlanIssue(.error, code: code, message: message, section: section, index: index, year: year,
                  regime: regime, option: option, account: account)
    }

    static func warning(_ code: String, _ message: String, section: PlanSection, index: Int? = nil,
                        year: Int? = nil, regime: String? = nil, option: String? = nil,
                        account: AccountID? = nil) -> PlanIssue {
        PlanIssue(.warning, code: code, message: message, section: section, index: index, year: year,
                  regime: regime, option: option, account: account)
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
