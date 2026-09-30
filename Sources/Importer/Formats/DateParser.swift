import Foundation
import Model

/// Reads dates written in one pattern.
///
/// - Patterns use Unicode symbols: `yyyy`, `yy`, `MM`, `M`, `MMM`, `MMMM`,
///   `dd`, `d`, `EEE` (a weekday name, ignored), and literal text, quoted
///   with `'` where it contains letters. Numeric fields accept one or two
///   digits. Month names are English or Italian, full or abbreviated, in
///   any case, with or without accents or a trailing dot (`gen`, `Gennaio`,
///   `Sept.`).
/// - A pattern without a day is a month-only date: it lands on the last day
///   of the month, or the first when `monthOnly` is `start`.
/// - `excel-serial` reads Excel date serial numbers (`45322` is 2024-01-31).
/// - A time after the date (`2024-01-31T18:30:00Z`, `31/01/2024 18:30`) is
///   dropped. If it has a UTC offset and the format names a `timeZone`, the
///   date is the one in that time zone.
public struct DateParser: Sendable {
    public let format: ImportDateFormat
    private let pattern: DatePattern?
    private let isExcelSerial: Bool

    public init(format: ImportDateFormat) {
        self.format = format
        isExcelSerial = format.pattern == ImportDateFormat.excelSerialPattern
        pattern = isExcelSerial ? nil : DatePattern(format.pattern ?? "yyyy-MM-dd")
    }

    /// Whether `pattern` is a pattern this parser understands (or `excel-serial`).
    public static func isValidPattern(_ pattern: String) -> Bool {
        pattern == ImportDateFormat.excelSerialPattern || DatePattern(pattern) != nil
    }

    /// The pattern as shown in messages.
    public var patternDescription: String {
        format.pattern ?? "yyyy-MM-dd"
    }

    /// Reads one cell. The text should be non-empty.
    public func parse(_ text: String) -> Result<CalendarDate, ImportProblem> {
        let value = TextTools.cellValue(text)
        if isExcelSerial { return Self.parseExcelSerial(value, pattern: patternDescription) }
        guard let pattern else { return .failure(.notADate(pattern: patternDescription)) }
        let (datePart, timePart) = Self.splitTime(value)
        guard let fields = pattern.match(datePart) else { return .failure(.notADate(pattern: patternDescription)) }
        let day = fields.day ?? (format.effectiveMonthOnly == .start
            ? 1 : YearMonth.numberOfDays(year: fields.year, month: min(max(fields.month, 1), 12)))
        guard let date = CalendarDate(year: fields.year, month: fields.month, day: day) else {
            return .failure(.noSuchDate)
        }
        guard let timePart else { return .success(date) }
        guard let time = TimeOfDay(timePart) else { return .failure(.notADate(pattern: patternDescription)) }
        guard let zoneName = format.timeZone, let offset = time.utcOffset else { return .success(date) }
        guard let zone = TimeZone(identifier: zoneName) else { return .failure(.unknownTimeZone(zoneName)) }
        let seconds = date.daysSinceEpoch * 86_400 + time.secondsSinceMidnight - offset
        return .success(CalendarDate(Date(timeIntervalSince1970: TimeInterval(seconds)), in: zone))
    }

    /// Excel's day 0 is 1899-12-30 (which absorbs its 1900 leap-year bug for
    /// every date after February 1900). A fraction is the time, dropped.
    static func parseExcelSerial(_ text: String, pattern: String) -> Result<CalendarDate, ImportProblem> {
        let parts = text.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(TextTools.isDigit) }),
              let serial = Int(parts[0]), (61...2_958_465).contains(serial)
        else { return .failure(.notADate(pattern: pattern)) }
        return .success(CalendarDate(year: 1899, month: 12, day: 30)!.adding(days: serial))
    }

    /// Splits `2024-01-31T18:30` or `31/01/2024 18:30:00` into date and time.
    static func splitTime(_ text: String) -> (date: String, time: String?) {
        let scalars = Array(text.unicodeScalars)
        var index = 1
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "T" || TextTools.isSpace(scalar) {
                var start = index + 1
                while start < scalars.count, TextTools.isSpace(scalars[start]) { start += 1 }
                var digits = start
                while digits < scalars.count, TextTools.isDigit(scalars[digits]) { digits += 1 }
                if (1...2).contains(digits - start), digits + 2 < scalars.count, scalars[digits] == ":",
                   TextTools.isDigit(scalars[digits + 1]), TextTools.isDigit(scalars[digits + 2]) {
                    let date = String(String.UnicodeScalarView(scalars[..<index]))
                    let time = String(String.UnicodeScalarView(scalars[start...]))
                    return (TextTools.trim(date), time)
                }
            }
            index += 1
        }
        return (text, nil)
    }
}

/// A time of day after a date: `H:mm[:ss[.fff]]`, optionally `AM`/`PM`, and
/// optionally `Z` or a UTC offset (`+01:00`, `+0100`, `+01`).
struct TimeOfDay: Hashable {
    var hour: Int
    var minute: Int
    var second: Int
    /// Seconds east of UTC, when the text names an offset.
    var utcOffset: Int?

    var secondsSinceMidnight: Int { hour * 3600 + minute * 60 + second }

    init?(_ text: String) {
        var scanner = Array(text.uppercased())[...]
        func number(maxDigits: Int) -> Int? {
            var digits = ""
            while digits.count < maxDigits, let first = scanner.first, TextTools.isDigit(first) {
                digits.append(first)
                scanner = scanner.dropFirst()
            }
            return Int(digits)
        }
        func skipSpaces() { while scanner.first?.isWhitespace == true { scanner = scanner.dropFirst() } }
        guard let hour = number(maxDigits: 2), scanner.first == ":" else { return nil }
        scanner = scanner.dropFirst()
        guard let minute = number(maxDigits: 2) else { return nil }
        var second = 0
        if scanner.first == ":" {
            scanner = scanner.dropFirst()
            guard let value = number(maxDigits: 2) else { return nil }
            second = value
            if scanner.first == "." || scanner.first == "," {
                scanner = scanner.dropFirst()
                guard number(maxDigits: 9) != nil else { return nil }
            }
        }
        skipSpaces()
        var hour24 = hour
        if scanner.starts(with: ["A", "M"]) || scanner.starts(with: ["P", "M"]) {
            guard (1...12).contains(hour) else { return nil }
            hour24 = hour % 12 + (scanner.first == "P" ? 12 : 0)
            scanner = scanner.dropFirst(2)
            skipSpaces()
        }
        guard hour24 < 24, minute < 60, second < 61 else { return nil }
        self.hour = hour24
        self.minute = minute
        self.second = min(second, 59)
        if scanner.first == "Z" {
            utcOffset = 0
            scanner = scanner.dropFirst()
        } else if let sign = scanner.first, sign == "+" || sign == "-" {
            scanner = scanner.dropFirst()
            guard let hours = number(maxDigits: 2) else { return nil }
            if scanner.first == ":" { scanner = scanner.dropFirst() }
            let minutes = number(maxDigits: 2) ?? 0
            utcOffset = (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60)
        }
        skipSpaces()
        guard scanner.isEmpty else { return nil }
    }
}

/// A date pattern split into tokens, and a matcher for it.
struct DatePattern: Hashable, Sendable {
    enum Token: Hashable, Sendable {
        case year(digits: Int)
        case month(width: Int)
        case monthName
        case day(width: Int)
        case weekday
        case literal(Character)
        case space
    }

    let tokens: [Token]

    var hasDay: Bool { tokens.contains { if case .day = $0 { true } else { false } } }

    /// Tokenizes a pattern; `nil` when it has no year or month, or unknown
    /// letters. Time fields (`HH:mm`, `a`, `XXX`, …) end the date part.
    init?(_ pattern: String) {
        var tokens: [Token] = []
        let characters = Array(pattern)
        var index = 0
        var endedByTime = false
        scan: while index < characters.count {
            let character = characters[index]
            if character == "'" {
                index += 1
                if index < characters.count, characters[index] == "'" {
                    tokens.append(.literal("'"))
                    index += 1
                    continue
                }
                while index < characters.count {
                    if characters[index] == "'" {
                        if index + 1 < characters.count, characters[index + 1] == "'" {
                            tokens.append(.literal("'"))
                            index += 2
                            continue
                        }
                        index += 1
                        break
                    }
                    tokens.append(characters[index].isWhitespace ? .space : .literal(characters[index]))
                    index += 1
                }
                continue
            }
            if character.isASCII, character.isLetter {
                var run = 1
                while index + run < characters.count, characters[index + run] == character { run += 1 }
                switch character {
                case "y", "u", "Y": tokens.append(.year(digits: run == 2 ? 2 : 4))
                case "M", "L": tokens.append(run >= 3 ? .monthName : .month(width: run))
                case "d": tokens.append(.day(width: run))
                case "E", "e", "c": tokens.append(.weekday)
                case "H", "h", "k", "K", "m", "s", "S", "a", "A", "X", "x", "Z", "z", "O", "v", "V":
                    endedByTime = true
                    break scan
                default: return nil
                }
                index += run
                continue
            }
            if character.isWhitespace {
                if tokens.last != .space { tokens.append(.space) }
            } else {
                tokens.append(.literal(character))
            }
            index += 1
        }
        if endedByTime {
            while let last = tokens.last, last == .space || last == .literal("T") || last == .literal(",") {
                tokens.removeLast()
            }
        }
        let hasYear = tokens.contains { if case .year = $0 { true } else { false } }
        let hasMonth = tokens.contains {
            switch $0 {
            case .month, .monthName: true
            default: false
            }
        }
        guard hasYear, hasMonth else { return nil }
        self.tokens = tokens
    }

    /// The year, month and (unless month-only) day in `text`, or `nil` if
    /// the text doesn't follow the pattern.
    func match(_ text: String) -> (year: Int, month: Int, day: Int?)? {
        let characters = Array(text)
        var index = 0
        var year: Int?, month: Int?, day: Int?

        func digits(min: Int, max: Int) -> Int? {
            var end = index
            while end < characters.count, end - index < max, TextTools.isDigit(characters[end]) { end += 1 }
            guard end - index >= min else { return nil }
            defer { index = end }
            return Int(String(characters[index..<end]))
        }
        func word() -> String {
            var end = index
            while end < characters.count, characters[end].isLetter { end += 1 }
            defer { index = end }
            return String(characters[index..<end])
        }

        for (position, token) in tokens.enumerated() {
            let nextIsNumeric: Bool = {
                guard position + 1 < tokens.count else { return false }
                switch tokens[position + 1] {
                case .year, .month, .day: return true
                default: return false
                }
            }()
            switch token {
            case .year(let count):
                guard let value = digits(min: count, max: count) else { return nil }
                year = count == 2 ? (value < 70 ? 2000 + value : 1900 + value) : value
            case .month(let width), .day(let width):
                let fixed = nextIsNumeric ? Swift.max(width, 2) : nil
                guard let value = digits(min: fixed ?? 1, max: fixed ?? 2) else { return nil }
                if case .month = token { month = value } else { day = value }
            case .monthName:
                guard let value = MonthNames.month(for: word()) else { return nil }
                month = value
                if index < characters.count, characters[index] == ".",
                   position + 1 >= tokens.count || tokens[position + 1] != .literal(".") {
                    index += 1
                }
            case .weekday:
                guard !word().isEmpty else { return nil }
                if index < characters.count, characters[index] == "." || characters[index] == "," { index += 1 }
            case .literal(let expected):
                guard index < characters.count,
                      characters[index] == expected
                      || characters[index].lowercased() == expected.lowercased()
                else { return nil }
                index += 1
            case .space:
                guard index < characters.count, characters[index].isWhitespace else { return nil }
                while index < characters.count, characters[index].isWhitespace { index += 1 }
            }
        }
        guard index == characters.count, let year, let month else { return nil }
        guard (1...12).contains(month) else { return nil }
        return (year, month, hasDay ? day : nil)
    }
}

/// Month names in English and Italian, full and abbreviated, folded.
enum MonthNames {
    static func month(for word: String) -> Int? {
        names[TextTools.fold(word)]
    }

    private static let names: [String: Int] = {
        let lists: [[String]] = [
            ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
             "november", "december"],
            ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"],
            ["gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre",
             "ottobre", "novembre", "dicembre"],
            ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"],
        ]
        var names: [String: Int] = ["sept": 9, "sett": 9]
        for list in lists {
            for (offset, name) in list.enumerated() { names[name] = offset + 1 }
        }
        return names
    }()
}
