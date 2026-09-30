/// Splits delimited text into rows of fields.
///
/// Follows RFC 4180 (quoted fields, `""` for a quote inside one, line breaks
/// inside quotes) and forgives what spreadsheets get wrong: `\n`, `\r\n` or
/// `\r` line ends, spaces before an opening quote, text after a closing
/// quote, and a quote that never closes (read as a literal character).
public enum CSVParser {
    /// The delimiters the importer detects, in order of preference when two
    /// read a file equally well.
    public static let delimiters = ["\t", ";", "|", ","]

    /// The rows of `text`. Fields are returned as written, untrimmed.
    public static func parse(_ text: String, delimiter: Character) -> [[String]] {
        parseDetailed(text, delimiter: delimiter).rows
    }

    /// The delimiter that splits `text` into the most rows of the same
    /// width, and any others that do equally well.
    public static func detectDelimiter(in text: String) -> (delimiter: String, alternatives: [String]) {
        let sample = String(text.unicodeScalars.prefix(65_536))
        var scores: [(delimiter: String, rows: Int, width: Int)] = []
        for delimiter in delimiters {
            let rows = parseDetailed(sample, delimiter: Character(delimiter)).rows
                .filter { $0.contains { !TextTools.trim($0).isEmpty } }
            var widths: [Int: Int] = [:]
            for row in rows where row.count >= 2 { widths[row.count, default: 0] += 1 }
            guard let modal = widths.max(by: { ($0.value, $0.key) < ($1.value, $1.key) }) else { continue }
            scores.append((delimiter, modal.value, modal.key))
        }
        guard let best = scores.max(by: { $0.rows < $1.rows }) else { return (",", []) }
        let tied = scores.filter { $0.rows == best.rows }
        return (tied[0].delimiter, tied.dropFirst().map(\.delimiter))
    }

    /// The rows, plus the 1-based rows where a quote was never closed.
    static func parseDetailed(_ text: String, delimiter: Character) -> (rows: [[String]], brokenQuoteRows: [Int]) {
        let scalars = Array(text.unicodeScalars)
        let delimiterScalar = delimiter.unicodeScalars.first ?? ","
        var literalQuotes = Set<Int>()
        var broken: [Int] = []
        while true {
            switch attempt(scalars, delimiter: delimiterScalar, literalQuotes: literalQuotes) {
            case .rows(let rows):
                return (rows, broken)
            case .unterminated(let quoteIndex, let row):
                literalQuotes.insert(quoteIndex)
                broken.append(row)
            }
        }
    }

    private enum Attempt {
        case rows([[String]])
        case unterminated(quoteIndex: Int, row: Int)
    }

    private static func attempt(_ scalars: [Unicode.Scalar], delimiter: Unicode.Scalar,
                                literalQuotes: Set<Int>) -> Attempt {
        let quote: Unicode.Scalar = "\""
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var fieldIsQuoted = false
        var inQuotes = false
        var quoteStart = 0
        var index = 0
        let count = scalars.count

        func endField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
            fieldIsQuoted = false
        }
        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while index < count {
            let scalar = scalars[index]
            if inQuotes {
                if scalar == quote {
                    if index + 1 < count, scalars[index + 1] == quote {
                        field.append(quote)
                        index += 2
                    } else {
                        inQuotes = false
                        index += 1
                    }
                } else {
                    field.append(scalar)
                    index += 1
                }
                continue
            }
            switch scalar {
            case quote where !fieldIsQuoted && !literalQuotes.contains(index)
                && field.allSatisfy(TextTools.isSpace):
                field = String.UnicodeScalarView()
                fieldIsQuoted = true
                inQuotes = true
                quoteStart = index
                index += 1
            case delimiter:
                endField()
                index += 1
            case "\r":
                endRow()
                index += index + 1 < count && scalars[index + 1] == "\n" ? 2 : 1
            case "\n":
                endRow()
                index += 1
            default:
                field.append(scalar)
                index += 1
            }
        }
        if inQuotes { return .unterminated(quoteIndex: quoteStart, row: rows.count + 1) }
        if !row.isEmpty || !field.isEmpty || fieldIsQuoted { endRow() }
        return .rows(rows)
    }
}
