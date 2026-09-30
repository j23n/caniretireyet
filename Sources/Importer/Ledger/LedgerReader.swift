import Foundation
import Model

/// Reads ledger-cli and hledger journals (IMPORT.md, "Ledger journals").
///
/// Several files can be given at once, e.g. one per year; each can
/// `include` others. They're read as one journal: a file both given and
/// included is read once, includes are resolved relative to the including
/// file (with `*`, `?`, `[…]` and `**` wildcards), and cycles are reported.
/// Reading is lenient: a transaction or directive that can't be read is
/// reported with its file and line and skipped, and the rest is read.
///
/// Transactions are then sorted by date (keeping the files' order within a
/// day) and balanced in that order: a posting without an amount gets what
/// balances the transaction, balance assignments set amounts, and balance
/// assertions are checked, a failed one being a warning.
public enum LedgerReader {
    /// Reads `roots` and everything they include, through `files`.
    public static func read(_ roots: [URL], files: any LedgerFileProvider) -> LedgerJournal {
        var loader = LedgerLoader(files: files, base: commonFolder(of: roots))
        for root in roots {
            do {
                try loader.load(root, state: LedgerFileState(), from: nil)
            } catch {
                loader.diagnostics.append(LedgerDiagnostic(
                    .error, "\(loader.displayName(of: root)) can't be read: \(describe(error))"))
            }
        }
        return loader.finish()
    }

    /// Reads one journal given as text, e.g. in tests. Includes are resolved
    /// in the folder of `path`, through `files`.
    public static func read(text: String, path: String = "/journal.ledger",
                            files: InMemoryLedgerFiles = InMemoryLedgerFiles([:])) -> LedgerJournal {
        var all = files
        all.files[path] = text
        return read([URL(fileURLWithPath: path)], files: all)
    }

    /// The folder file names are shown relative to: the deepest folder
    /// holding every file given.
    static func commonFolder(of roots: [URL]) -> URL {
        let folders = roots.map { $0.standardizedFileURL.deletingLastPathComponent().pathComponents }
        guard var common = folders.first else { return URL(fileURLWithPath: "/") }
        for folder in folders.dropFirst() {
            common = Array(zip(common, folder).prefix { $0 == $1 }.map(\.0))
        }
        return URL(fileURLWithPath: NSString.path(withComponents: common.isEmpty ? ["/"] : common), isDirectory: true)
    }

    static func describe(_ error: any Error) -> String {
        if let error = error as? CocoaError, error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return "there's no such file"
        }
        if let error = error as? CocoaError, error.code == .fileReadNoPermission {
            return "no permission to read it"
        }
        if let error = error as? ImportError { return error.description }
        return error.localizedDescription
    }
}

// MARK: - Parsed, not yet balanced

/// A `{lot price}` or an `@`/`@@` price.
struct RawPrice: Hashable {
    var amount: ParsedAmount
    var isTotal: Bool
}

/// A balance assertion (`= 100 EUR`, `== …`, `=* …`), or with no posting
/// amount, a balance assignment.
struct RawAssertion: Hashable {
    var amount: ParsedAmount
    /// `==`: no other commodity in the account.
    var isExact: Bool
    /// `=*`: including subaccounts.
    var isInclusive: Bool
    /// `= 0` without a commodity: every commodity is zero.
    var isAnyCommodity: Bool
}

struct RawPosting: Hashable {
    var account: String
    var kind: LedgerPosting.Kind
    var amount: ParsedAmount?
    var lot: RawPrice?
    var price: RawPrice?
    var assertion: RawAssertion?
    var location: LedgerLocation
}

struct RawTransaction: Hashable {
    var date: CalendarDate
    var status: LedgerTransaction.Status?
    var code: String?
    var description: String
    var postings: [RawPosting] = []
    var location: LedgerLocation
    /// The order it was read in, to keep a day's transactions in file order.
    var sequence = 0
}

/// Directives that last to the end of the file (and the files it includes).
struct LedgerFileState {
    var year: Int?
    var defaultCommodity: String?
    var decimalMark: Character?
    var aliases: [LedgerAlias] = []
    /// `apply account` prefixes, outermost first.
    var parents: [String] = []
    /// The decimal mark for numbers such as `1.000`, from the file's other numbers.
    var fallbackMark: Character = "."

    /// An account name as written, with the `apply account` prefix and aliases applied.
    func fullName(_ name: String) -> String {
        var full = parents.isEmpty ? name : (parents + [name]).joined(separator: ":")
        for alias in aliases { full = alias.apply(to: full) }
        return full
    }
}

/// `alias OLD = NEW` (OLD and its subaccounts), or `alias /REGEX/ = NEW`.
struct LedgerAlias {
    var old: String
    var new: String
    var regex: NSRegularExpression?

    init?(_ text: String) {
        guard let equals = text.firstIndex(of: "=") else { return nil }
        old = text[..<equals].trimmingCharacters(in: .whitespaces)
        new = text[text.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard !old.isEmpty else { return nil }
        if old.count > 2, old.hasPrefix("/"), old.hasSuffix("/") {
            guard let regex = try? NSRegularExpression(pattern: String(old.dropFirst().dropLast()),
                                                       options: .caseInsensitive) else { return nil }
            self.regex = regex
            // `\1` in the replacement is a back-reference.
            new = new.replacingOccurrences(of: #"\\(\d)"#, with: "\\$$1", options: .regularExpression)
        }
    }

    func apply(to name: String) -> String {
        if let regex {
            let range = NSRange(name.startIndex..., in: name)
            return regex.stringByReplacingMatches(in: name, range: range, withTemplate: new)
        }
        if name == old { return new }
        if name.hasPrefix(old + ":") { return new + name.dropFirst(old.count) }
        return name
    }
}

// MARK: - Loading files

struct LedgerLoader {
    let files: any LedgerFileProvider
    let base: URL
    var visited = Set<String>()
    var stack: [String] = []
    var sourceFiles: [LedgerSourceFile] = []
    var transactions: [RawTransaction] = []
    var prices: [(price: LedgerMarketPrice, sequence: Int)] = []
    var diagnostics: [LedgerDiagnostic] = []
    var missing: [LedgerMissingInclude] = []
    var declared: [String] = []
    var types: [String: LedgerAccountType] = [:]
    /// Decimal marks from `commodity` and `D` format samples.
    var commodityMarks: [String: Character] = [:]
    /// The most decimals a commodity's posting amounts were written with.
    var precision: [String: Int] = [:]
    var sequence = 0

    init(files: any LedgerFileProvider, base: URL) {
        self.files = files
        self.base = base
    }

    func displayName(of url: URL) -> String {
        let path = url.standardizedFileURL.path
        let folder = base.standardizedFileURL.path
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    /// Reads a file, unless it was read already. Throws when it can't be read.
    mutating func load(_ url: URL, state: LedgerFileState, from include: LedgerLocation?) throws {
        let key = url.standardizedFileURL.path
        guard !visited.contains(key) else { return }
        let data = try files.data(at: url)
        let text = try TextDecoding.decode(data).text
        visited.insert(key)
        stack.append(key)
        defer { stack.removeLast() }
        let index = sourceFiles.count
        sourceFiles.append(LedgerSourceFile(url: url.standardizedFileURL, name: displayName(of: url),
                                            includedFrom: include))
        var state = state
        state.fallbackMark = Self.decimalEvidence(in: text) ?? state.fallbackMark
        var parser = LedgerFileParser(url: url.standardizedFileURL, name: sourceFiles[index].name, state: state)
        parser.parse(text, loader: &self, fileIndex: index)
    }

    /// An `include` directive: one file, or every file a wildcard matches.
    mutating func include(_ argument: String, from url: URL, at location: LedgerLocation, state: LedgerFileState) {
        var path = argument.trimmingCharacters(in: .whitespaces)
        if let colon = path.firstIndex(of: ":"), colon != path.startIndex {
            let format = path[..<colon].lowercased()
            let formats = ["journal", "j", "hledger", "ledger", "timeclock", "timedot", "csv", "ssv", "tsv", "rules"]
            if formats.contains(format) {
                guard ["journal", "j", "hledger", "ledger"].contains(format) else {
                    diagnostics.append(LedgerDiagnostic(
                        .warning, "Only journal files can be included; “\(argument)” was skipped.", at: location))
                    return
                }
                path = String(path[path.index(after: colon)...])
            }
        }
        guard !path.isEmpty else {
            diagnostics.append(LedgerDiagnostic(.error, "`include` needs a file.", at: location))
            return
        }
        let expanded = (path as NSString).expandingTildeInPath
        let target = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded)
            : url.deletingLastPathComponent().appendingPathComponent(expanded)
        var targets: [URL]
        if path.contains(where: { "*?[".contains($0) }) {
            do {
                targets = try glob(target.standardizedFileURL)
                    .filter { $0.standardizedFileURL.path != url.standardizedFileURL.path }
            } catch {
                missing.append(LedgerMissingInclude(path: path, url: target.standardizedFileURL, location: location,
                                                    reason: LedgerReader.describe(error)))
                diagnostics.append(LedgerDiagnostic(
                    .warning, "The files “\(path)” can't be listed: \(LedgerReader.describe(error)).", at: location))
                return
            }
            if targets.isEmpty {
                diagnostics.append(LedgerDiagnostic(.warning, "No files match “\(path)”.", at: location))
            }
        } else {
            targets = [target.standardizedFileURL]
        }
        for file in targets {
            let key = file.standardizedFileURL.path
            if stack.contains(key) {
                let cycle = (stack.drop { $0 != key } + [key]).map { displayName(of: URL(fileURLWithPath: $0)) }
                diagnostics.append(LedgerDiagnostic(
                    .error, "Include cycle: \(cycle.joined(separator: " → ")). It was read once.", at: location))
                continue
            }
            do {
                try load(file, state: state, from: location)
            } catch {
                missing.append(LedgerMissingInclude(path: path, url: file, location: location,
                                                    reason: LedgerReader.describe(error)))
                diagnostics.append(LedgerDiagnostic(
                    .warning, "The included file \(displayName(of: file)) can't be read: \(LedgerReader.describe(error)).",
                    at: location))
            }
        }
    }

    /// The files a wildcard path matches, sorted.
    private func glob(_ pattern: URL) throws -> [URL] {
        let components = pattern.pathComponents
        guard let first = components.firstIndex(where: { $0.contains(where: { "*?[".contains($0) }) }) else {
            return [pattern]
        }
        let root = URL(fileURLWithPath: NSString.path(withComponents: Array(components[..<first])), isDirectory: true)
        let matches = try expand(root, components[first...])
        return Array(Set(matches.map(\.standardizedFileURL))).sorted { $0.path < $1.path }
    }

    private func expand(_ folder: URL, _ components: ArraySlice<String>) throws -> [URL] {
        guard let component = components.first else { return [folder] }
        let rest = components.dropFirst()
        if component == "**" {
            var results = try expand(folder, rest)
            for child in try files.contentsOfDirectory(at: folder)
            where files.isDirectory(child) && !child.lastPathComponent.hasPrefix(".") {
                results += try expand(child, components)
            }
            return results
        }
        guard component.contains(where: { "*?[".contains($0) }) else {
            return try expand(folder.appendingPathComponent(component), rest)
        }
        var results: [URL] = []
        let children = try files.contentsOfDirectory(at: folder).sorted { $0.path < $1.path }
        for child in children where Self.matches(child.lastPathComponent, component) {
            if child.lastPathComponent.hasPrefix("."), !component.hasPrefix(".") { continue }
            let isFolder = files.isDirectory(child)
            if rest.isEmpty {
                if !isFolder { results.append(child) }
            } else if isFolder {
                results += try expand(child, rest)
            }
        }
        return results
    }

    /// Whether a file name matches a wildcard: `*`, `?` and `[abc]`, `[a-z]`, `[!abc]`.
    static func matches(_ name: String, _ pattern: String) -> Bool {
        let name = Array(name), pattern = Array(pattern)
        func match(_ n: Int, _ p: Int) -> Bool {
            if p == pattern.count { return n == name.count }
            switch pattern[p] {
            case "*":
                return (n...name.count).contains { match($0, p + 1) }
            case "?":
                return n < name.count && match(n + 1, p + 1)
            case "[":
                guard n < name.count, let close = pattern[(p + 1)...].firstIndex(of: "]") else {
                    return n < name.count && name[n] == "[" && match(n + 1, p + 1)
                }
                var set = Array(pattern[(p + 1)..<close])
                let negated = set.first == "!" || set.first == "^"
                if negated { set.removeFirst() }
                var found = false
                var index = 0
                while index < set.count {
                    if index + 2 < set.count, set[index + 1] == "-" {
                        if set[index] <= name[n] && name[n] <= set[index + 2] { found = true }
                        index += 3
                    } else {
                        if set[index] == name[n] { found = true }
                        index += 1
                    }
                }
                return found != negated && match(n + 1, close + 1)
            default:
                return n < name.count && name[n] == pattern[p] && match(n + 1, p + 1)
            }
        }
        return match(0, 0)
    }

    /// The decimal mark most numbers in postings and prices show, if any do.
    static func decimalEvidence(in text: String) -> Character? {
        var votes: [Character: Int] = [:]
        let space = UInt8(ascii: " "), tab = UInt8(ascii: "\t"), newline = UInt8(ascii: "\n")
        let dot = UInt8(ascii: "."), comma = UInt8(ascii: ","), apostrophe = UInt8(ascii: "'")
        let semicolon = UInt8(ascii: ";"), hash = UInt8(ascii: "#"), price = UInt8(ascii: "P")
        func isDigit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }
        var number: [UInt8] = []
        func vote() {
            if !number.isEmpty, let mark = LedgerAmountParser.evidence(String(decoding: number, as: UTF8.self)) {
                votes[mark, default: 0] += 1
            }
            number.removeAll(keepingCapacity: true)
        }
        var bytes = text.utf8[...]
        while !bytes.isEmpty {
            let line = bytes.prefix { $0 != newline }
            bytes = bytes.dropFirst(line.count + 1)
            guard let first = line.first else { continue }
            var amounts: Substring.UTF8View.SubSequence
            if first == space || first == tab {
                let content = line.drop { $0 == space || $0 == tab }
                guard let lead = content.first, lead != semicolon, lead != hash else { continue }
                // After the account: two spaces or a tab.
                var index = content.startIndex
                var found: Substring.UTF8View.Index?
                while index < content.endIndex {
                    let next = content.index(after: index)
                    if content[index] == tab || (content[index] == space && next < content.endIndex && content[next] == space) {
                        found = index
                        break
                    }
                    index = next
                }
                guard let found else { continue }
                amounts = content[found...]
            } else if first == price {
                // Skip `P` and the date.
                var rest = line.dropFirst().drop { $0 == space || $0 == tab }
                rest = rest.drop { $0 != space && $0 != tab }
                amounts = rest
            } else {
                continue
            }
            for byte in amounts {
                if byte == semicolon { break }
                if isDigit(byte) || (!number.isEmpty && (byte == dot || byte == comma || byte == apostrophe)) {
                    number.append(byte)
                } else {
                    vote()
                }
            }
            vote()
        }
        guard let best = votes.max(by: { ($0.value, $0.key) < ($1.value, $1.key) }) else { return nil }
        return best.key
    }

    // MARK: Finishing

    /// Sorts and balances the transactions and returns the journal.
    mutating func finish() -> LedgerJournal {
        let sorted = transactions.sorted { ($0.date, $0.sequence) < ($1.date, $1.sequence) }
        var balancer = LedgerBalancer(precision: precision)
        var balanced: [LedgerTransaction] = []
        balanced.reserveCapacity(sorted.count)
        for transaction in sorted {
            if let result = balancer.balance(transaction) { balanced.append(result) }
        }
        return LedgerJournal(
            files: sourceFiles, transactions: balanced,
            prices: prices.sorted { ($0.price.date, $0.sequence) < ($1.price.date, $1.sequence) }.map(\.price),
            declaredAccounts: declared, accountTypes: types, diagnostics: diagnostics + balancer.diagnostics,
            missingIncludes: missing)
    }
}
