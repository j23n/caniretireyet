import Foundation
import Model
import Planner

/// The sections of the plan debugger's screen, in order, after the
/// diagnosis (PLANNER.md, "Plan debugger").
enum PlanDebugSection: String, CaseIterable, Hashable, Identifiable, Sendable {
    case run
    case plan
    case start
    case schedule
    case simulation
    case percentiles
    case paths
    case issues

    var id: String { rawValue }

    var title: String {
        switch self {
        case .run: "What was run"
        case .plan: "The person and the plan as read"
        case .start: "Starting portfolio"
        case .schedule: "Year-by-year schedule"
        case .simulation: "Simulation summary"
        case .percentiles: "Percentiles by year"
        case .paths: "Traced runs"
        case .issues: "Issues"
        }
    }

    var systemImage: String {
        switch self {
        case .run: "gearshape"
        case .plan: "person.text.rectangle"
        case .start: "banknote"
        case .schedule: "calendar"
        case .simulation: "chart.line.uptrend.xyaxis"
        case .percentiles: "chart.bar.xaxis"
        case .paths: "point.topleft.down.to.point.bottomright.curvepath"
        case .issues: "exclamationmark.triangle"
        }
    }

    /// One line on how to read the section, as the report explains it.
    func howToRead(_ report: PlanDebugReport) -> String {
        let age = report.header.retirementAge
        switch self {
        case .run:
            return "The engine, the plan and the simulation settings behind every number here."
        case .plan:
            return "How the engine read the plan and your library: the inputs every calculation starts from, "
                + "and the return each asset class is assumed to make."
        case .start:
            return "Each account on the start date, in the plan's currency, and the bucket (tax wrapper) it went "
                + "into: the simulation draws from buckets, liquid ones at any time, the others by their rules."
        case .schedule:
            return "What doesn't depend on the markets, retiring at \(age): income, pensions, spending and the "
                + "taxes on them. “To draw” is what the portfolio must provide; negative is money saved."
        case .simulation:
            return "How often the plan works at each retirement age (the same random futures for every age), "
                + "how the two searches found their answers, and why runs fail."
        case .percentiles:
            return "Plan assets at each year-end across every run, retiring at \(age), from the 10th to the 90th "
                + "percentile, with what's drawn and taxed among the runs still going."
        case .paths:
            return "Single runs simulated again year by year, with the same random draws, so each ends exactly "
                + "as it did. Choose a year to see every step of it."
        case .issues:
            return "Warnings from the plan, the tax systems and the years assessed."
        }
    }
}

/// The retirement age the details are for.
enum PlanDebugAgeChoice: String, CaseIterable, Hashable, Identifiable, Sendable {
    /// Today's age: the "retire today" scenario behind "needed to retire today".
    case today
    /// The plan's target age, or the earliest age that reaches the confidence level.
    case target
    /// An age chosen with the stepper.
    case age

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .target: "Target"
        case .age: "Age…"
        }
    }

    var explanation: String {
        switch self {
        case .today: "Retiring today: the scenario behind “needed to retire today”."
        case .target: "The plan's retirement age, or the earliest age that reaches its confidence level."
        case .age: "Retiring at the age you choose."
        }
    }
}

/// What the percentiles, failures and traced runs start from.
enum PlanDebugStartChoice: String, CaseIterable, Hashable, Identifiable, Sendable {
    case automatic
    /// Today's plan assets.
    case actual
    /// What retiring today needs.
    case assetsNeeded
    /// A multiple of today's plan assets.
    case factor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .actual: "Today's assets"
        case .assetsNeeded: "What's needed"
        case .factor: "A multiple"
        }
    }

    var explanation: String {
        switch self {
        case .automatic:
            "Retiring today with too little, the runs start from what retiring today needs, to show why it's "
                + "that much; otherwise from today's plan assets."
        case .actual:
            "The runs start from today's plan assets."
        case .assetsNeeded:
            "The runs start from the plan assets retiring today needs (or the most the search tries)."
        case .factor:
            "The runs start from a multiple of today's plan assets, every holding scaled alike."
        }
    }
}

/// The options of the debugger's controls.
struct PlanDebugChoices: Hashable, Sendable {
    var age: PlanDebugAgeChoice = .today
    /// The age for ``PlanDebugAgeChoice/age``.
    var customAge = 60
    var start: PlanDebugStartChoice = .automatic
    /// The multiple for ``PlanDebugStartChoice/factor``.
    var factor = 2.0
    /// How many runs to trace, chosen by outcome (the deterministic run comes on top).
    var pathCount = PlanDebugOptions.defaultPathCount
    /// Whether a what-if in use is applied to the plan.
    var includesWhatIf = true

    /// The traced runs offered: up to the six the debugger picks by outcome.
    static let pathCounts = 0...6
    /// The multiples offered.
    static let factors = 0.5...20.0

    /// The debugger's options: the plan run as the app runs it (every run,
    /// every age, from the latest check-in), with these choices.
    func options(asOf: CalendarDate, runDate: CalendarDate) -> PlanDebugOptions {
        let retirementAge: PlanDebugOptions.RetirementAge = switch age {
        case .today: .today
        case .target: .target
        case .age: .age(customAge)
        }
        let startScale: PlanDebugOptions.StartScale = switch start {
        case .automatic: .automatic
        case .actual: .actual
        case .assetsNeeded: .assetsNeeded
        case .factor: .factor(factor)
        }
        return PlanDebugOptions(
            planner: PlannerPlanEngine.options(for: .base(.full), focusAge: nil, asOf: asOf),
            retirementAge: retirementAge, startScale: startScale,
            paths: .automatic(count: max(0, pathCount)), tracesExpectedPath: true, runDate: runDate)
    }
}

/// How the debugger's words read.
enum PlanDebugText {
    /// Before the first calculation.
    static let introduction = "Shows every calculation behind the plan's answer: how it read the plan and your "
        + "accounts, the assumptions, the year-by-year schedule, both searches, percentiles and a few runs traced "
        + "year by year. It runs the whole plan again, which takes a few seconds, and only when you ask."

    /// While it runs.
    static let calculating = "Calculating… This runs the whole plan again and traces a few runs; it takes a few "
        + "seconds."

    /// Above the diagnosis.
    static let diagnosisNote = "What weighs most on the result, worked out from the figures below. These are facts "
        + "about the plan as entered, not advice."

    /// What anonymizing removes, in one line.
    static let anonymizeNote = "Replaces account, instrument, plan, pension and event names and IDs with neutral "
        + "labels, leaves out notes and the birth date (ages stay), and rounds amounts."

    /// Under the export's buttons while amounts are hidden.
    static let hiddenAmountsNote = "The file and the copy hold the amounts, even while they're hidden on screen."

    /// The rounding's name.
    static func title(_ rounding: PlanDebugAnonymization.Rounding) -> String {
        switch rounding {
        case .significantFigures: "3 significant figures"
        case .hundreds: "Nearest 100"
        case .none: "Exact"
        }
    }

    /// "Retiring at 38 (today's age)".
    static func retiring(_ header: PlanDebugReport.Header) -> String {
        let why = switch header.retirementAgeChoice {
        case "today": " (today's age)"
        case "target": " (the plan's target)"
        default: ""
        }
        return "Retiring at \(header.retirementAge)\(why)"
    }

    /// "20 times today's plan assets, the most the search for what retiring
    /// today needs tries" when the runs start from a multiple; `nil` from today's.
    static func scale(_ report: PlanDebugReport) -> String? {
        let header = report.header
        guard abs(header.startScale - 1) > 1e-9 else { return nil }
        let times = "\(number((header.startScale * 100).rounded() / 100)) times today's plan assets"
        switch header.startScaleChoice {
        case "assetsNeeded":
            return report.simulation.assetsNeeded?.outcome == "moreThanMaximum"
                ? times + ", the most the search for what retiring today needs tries (it still falls short)"
                : times + ": what retiring today needs"
        default:
            return times
        }
    }

    /// A number without needless decimals, as the report writes it: `20`, `2.5`.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "?" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// "× 2.5".
    static func times(_ value: Double) -> String {
        "× " + number(value)
    }

    /// A class or category name: "Real estate", "Equity fund".
    static func className(_ raw: String) -> String {
        var words = ""
        for character in raw {
            if character.isUppercase, !words.isEmpty { words += " " + character.lowercased() } else { words.append(character) }
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// `a`, `a and b`, `a, b and c`.
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    /// A mix as words: "equity 43%, crypto 33%".
    static func mix(_ shares: [String: Double]) -> String {
        shares.filter { $0.value > 0 }.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .map { "\($0.key) \(Int(($0.value * 100).rounded()))%" }.joined(separator: ", ")
    }

    /// The plan's options as words: "coefficient: 0.67, startedIn: 2029".
    static func options(_ options: [String: JSONValue]) -> String {
        options.keys.sorted().map { "\($0): \(json(options[$0]!))" }.joined(separator: ", ")
    }

    private static func json(_ value: JSONValue) -> String {
        switch value {
        case .null: "null"
        case .bool(let value): String(value)
        case .number(let value): value.description
        case .string(let value): value
        case .array(let values): "[" + values.map(json).joined(separator: ", ") + "]"
        case .object(let object): "{" + options(object) + "}"
        }
    }

    /// An amount in the report's own words (`12,345`), for the few places
    /// money sits inside a sentence of the report; ``masked(_:currency:)``
    /// hides it with the eye.
    static func money(_ value: Double) -> String {
        guard value.isFinite else { return "?" }
        let whole = Int64(max(-1e15, min(1e15, value.rounded())))
        let digits = String(abs(whole))
        var grouped = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        return (whole < 0 ? "-" : "") + grouped
    }

    // MARK: Hidden amounts

    /// `text` with the amounts in it hidden (`•••••`), for the eye: the
    /// report's sentences write money as `3,230,110` or `310 EUR`, and a
    /// plan's options as written (`montante: 92000`). Numbers grouped by
    /// commas, numbers before the currency's code and whole numbers of five
    /// digits or more are hidden; percentages, ages, years, rates and
    /// multiples stay.
    static func masked(_ text: String, currency: String) -> String {
        let characters = Array(text)
        let code = Array(" " + currency)
        var result = ""
        var index = 0
        func isDigit(_ character: Character) -> Bool { character >= "0" && character <= "9" }
        while index < characters.count {
            let character = characters[index]
            let startsNumber = isDigit(character)
                && (index == 0 || !(characters[index - 1].isLetter || isDigit(characters[index - 1])
                    || characters[index - 1] == "." || characters[index - 1] == ","))
            guard startsNumber else {
                result.append(character)
                index += 1
                continue
            }
            var end = index
            while end < characters.count {
                if isDigit(characters[end]) {
                    end += 1
                } else if characters[end] == "," || characters[end] == ".", end + 1 < characters.count,
                          isDigit(characters[end + 1]) {
                    end += 1
                } else {
                    break
                }
            }
            let token = String(characters[index..<end])
            let percent = end < characters.count && characters[end] == "%"
            let beforeCode = end + code.count <= characters.count && Array(characters[end..<(end + code.count)]) == code
                && (end + code.count == characters.count || !characters[end + code.count].isLetter)
            let large = !token.contains(",") && token.prefix { $0 != "." }.count >= 5
            if !percent && (isGrouped(token) || beforeCode || large) {
                if let last = result.last, last == "-" || last == "\u{2212}" { result.removeLast() }
                result += AmountFormat.hidden
            } else {
                result += token
            }
            index = end
        }
        return result
    }

    /// Whether `token` is grouped by commas: `3,230,110`, `1,234.5`.
    private static func isGrouped(_ token: String) -> Bool {
        let whole = token.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let groups = whole.split(separator: ",", omittingEmptySubsequences: false)
        guard groups.count >= 2, (1...3).contains(groups[0].count) else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 }
    }
}
