import Foundation
import Model

/// Reads one journal file line by line: transactions, postings, prices and
/// directives. Includes are handed to the ``LedgerLoader``, which reads them
/// in place with the directives in effect.
struct LedgerFileParser {
    let url: URL
    let name: String
    var state: LedgerFileState

    /// What indented lines belong to.
    private enum Block {
        case none
        /// A transaction being read.
        case transaction
        /// Lines of something skipped: a bad or unsupported entry.
        case skipping
        /// Sub-directives of `account` (types) or `commodity` (`format`).
        case account(String)
        case commodity(String)
        /// `comment` … `end comment`, `test` … `end test`.
        case comment
    }

    private var block = Block.none
    private var current: RawTransaction?

    init(url: URL, name: String, state: LedgerFileState) {
        self.url = url
        self.name = name
        self.state = state
    }

    mutating func parse(_ text: String, loader: inout LedgerLoader, fileIndex: Int) {
        var number = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            number += 1
            var line = rawLine
            if line.last == "\r" { line = line.dropLast() }
            let location = LedgerLocation(file: name, line: number)

            if case .comment = block {
                let word = line.trimmingCharacters(in: .whitespaces).lowercased()
                if word.hasPrefix("end comment") || word.hasPrefix("end test") { block = .none }
                continue
            }
            guard let first = line.first, !line.allSatisfy({ $0 == " " || $0 == "\t" }) else {
                finishTransaction(&loader, fileIndex: fileIndex)
                block = .none
                continue
            }
            if first == " " || first == "\t" {
                indented(line.drop { $0 == " " || $0 == "\t" }, at: location, loader: &loader)
                continue
            }
            finishTransaction(&loader, fileIndex: fileIndex)
            block = .none
            if ";#%|*".contains(first) { continue }
            if TextTools.isDigit(first) {
                header(line, at: location, loader: &loader)
            } else if first == "=" {
                loader.diagnostics.append(LedgerDiagnostic(
                    .warning, "Automated transactions (`=`) aren't supported; this one was skipped.", at: location))
                block = .skipping
            } else if first == "~" {
                loader.diagnostics.append(LedgerDiagnostic(
                    .warning, "Periodic transactions (`~`) aren't supported; this one was skipped.", at: location))
                block = .skipping
            } else {
                directive(line, at: location, loader: &loader)
            }
        }
        finishTransaction(&loader, fileIndex: fileIndex)
    }

    private mutating func finishTransaction(_ loader: inout LedgerLoader, fileIndex: Int) {
        guard var transaction = current else { return }
        current = nil
        transaction.sequence = loader.sequence
        loader.sequence += 1
        loader.transactions.append(transaction)
        loader.sourceFiles[fileIndex].transactions += 1
    }

    // MARK: - Transactions

    private mutating func header(_ line: Substring, at location: LedgerLocation, loader: inout LedgerLoader) {
        var rest = line[...]
        let dateText = rest.prefix { TextTools.isDigit($0) || "-/.".contains($0) }
        rest = rest.dropFirst(dateText.count)
        if rest.first == "=" {
            rest = rest.dropFirst()
            rest = rest.drop { TextTools.isDigit($0) || "-/.".contains($0) }
        }
        if let next = rest.first, next != " ", next != "\t" {
            fail("“\(line.prefix { $0 != " " && $0 != "\t" })” isn't a date.", at: location, loader: &loader)
            return
        }
        let date: CalendarDate
        switch Self.date(String(dateText), year: state.year) {
        case .success(let value): date = value
        case .failure(let problem):
            fail(problem.message, at: location, loader: &loader)
            return
        }
        rest = rest.drop { $0 == " " || $0 == "\t" }
        var status: LedgerTransaction.Status?
        if let mark = rest.first, mark == "*" || mark == "!" {
            status = mark == "*" ? .cleared : .pending
            rest = rest.dropFirst().drop { $0 == " " || $0 == "\t" }
        }
        var code: String?
        if rest.first == "(", let close = rest.firstIndex(of: ")") {
            code = String(rest[rest.index(after: rest.startIndex)..<close])
            rest = rest[rest.index(after: close)...].drop { $0 == " " || $0 == "\t" }
        }
        if let comment = rest.firstIndex(of: ";") { rest = rest[..<comment] }
        current = RawTransaction(date: date, status: status, code: code,
                                 description: rest.trimmingCharacters(in: .whitespaces), location: location)
        block = .transaction
    }

    private struct DateProblem: Error {
        var message: String
    }

    /// `YYYY-MM-DD` with `-`, `/` or `.`, or `M/D` after a `year` directive.
    private static func date(_ text: String, year: Int?) -> Result<CalendarDate, DateProblem> {
        let parts = text.split(whereSeparator: { "-/.".contains($0) }).map(String.init)
        var components: (Int, Int, Int)?
        if parts.count == 3, parts[0].count == 4, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) {
            components = (y, m, d)
        } else if parts.count == 2, let m = Int(parts[0]), let d = Int(parts[1]) {
            guard let year else {
                return .failure(DateProblem(message: "“\(text)” has no year; add a `year` directive before it."))
            }
            components = (year, m, d)
        }
        guard let (y, m, d) = components else { return .failure(DateProblem(message: "“\(text)” isn't a date.")) }
        guard let date = CalendarDate(year: y, month: m, day: d) else {
            return .failure(DateProblem(message: "“\(text)” is no such date."))
        }
        return .success(date)
    }

    private mutating func indented(_ content: Substring, at location: LedgerLocation, loader: inout LedgerLoader) {
        switch block {
        case .transaction:
            if content.hasPrefix(";") || content.hasPrefix("#") { return }
            switch posting(content, at: location, loader: &loader) {
            case .success(let posting): current?.postings.append(posting)
            case .failure(let problem):
                current = nil
                fail(problem.message + " The transaction was skipped.", at: location, loader: &loader)
            }
        case .account(let account):
            if let type = Self.accountType(in: content) { loader.types[account] = type }
        case .commodity(let symbol):
            let text = content.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("format ") { commodityFormat(String(text.dropFirst(7)), symbol: symbol, loader: &loader) }
        case .skipping, .comment:
            break
        case .none:
            if content.hasPrefix(";") || content.hasPrefix("#") { return }
            loader.diagnostics.append(LedgerDiagnostic(
                .warning, "An indented line outside a transaction was skipped.", at: location))
            block = .skipping
        }
    }

    private mutating func fail(_ message: String, at location: LedgerLocation, loader: inout LedgerLoader) {
        loader.diagnostics.append(LedgerDiagnostic(.error, message, at: location))
        block = .skipping
    }

    /// Where a posting's account name ends: at a tab or two spaces.
    static func separatorIndex(in text: Substring) -> Substring.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\t" { return index }
            let next = text.index(after: index)
            if text[index] == " ", next < text.endIndex, text[next] == " " { return index }
            index = next
        }
        return nil
    }

    private struct PostingProblem: Error {
        var message: String
    }

    private func posting(_ content: Substring, at location: LedgerLocation,
                         loader: inout LedgerLoader) -> Result<RawPosting, PostingProblem> {
        var text = content
        if let mark = text.first, mark == "*" || mark == "!", text.dropFirst().first == " " || text.dropFirst().first == "\t" {
            text = text.dropFirst().drop { $0 == " " || $0 == "\t" }
        }
        var accountPart = text
        var amountPart: Substring = ""
        if let separator = Self.separatorIndex(in: text) {
            accountPart = text[..<separator]
            amountPart = text[separator...]
        }
        if let comment = accountPart.range(of: " ;") {
            accountPart = accountPart[..<comment.lowerBound]
            amountPart = ""
        }
        var account = accountPart.trimmingCharacters(in: .whitespaces)
        var kind = LedgerPosting.Kind.real
        if account.count > 2, account.hasPrefix("("), account.hasSuffix(")") {
            kind = .unbalancedVirtual
            account = String(account.dropFirst().dropLast())
        } else if account.count > 2, account.hasPrefix("["), account.hasSuffix("]") {
            kind = .balancedVirtual
            account = String(account.dropFirst().dropLast())
        }
        guard !account.isEmpty else { return .failure(PostingProblem(message: "A posting has no account.")) }
        var posting = RawPosting(account: state.fullName(account), kind: kind, location: location)
        let amounts = Self.withoutComment(amountPart).trimmingCharacters(in: .whitespaces)
        guard !amounts.isEmpty else { return .success(posting) }
        do {
            try parseAmounts(amounts, into: &posting, loader: &loader)
        } catch {
            return .failure(PostingProblem(message: "The amount “\(amounts)” can't be read: \(error.message)."))
        }
        return .success(posting)
    }

    private struct AmountProblem: Error {
        var message: String
    }

    /// `AMOUNT [{LOT}] [[DATE]] [(NOTE)] [@ PRICE | @@ TOTAL] [= ASSERTION]`.
    private func parseAmounts(_ text: String, into posting: inout RawPosting,
                              loader: inout LedgerLoader) throws(AmountProblem) {
        var rest = Substring(text)
        if let equals = Self.topLevelIndex(of: "=", in: rest) {
            var assertion = rest[rest.index(after: equals)...]
            rest = rest[..<equals]
            var isExact = false, isInclusive = false
            if assertion.first == "=" {
                isExact = true
                assertion = assertion.dropFirst()
            }
            if assertion.first == "*" {
                isInclusive = true
                assertion = assertion.dropFirst()
            }
            let written = assertion.trimmingCharacters(in: .whitespaces)
            let amount = try amount(written, loader: &loader, isPosting: false)
            let hasCommodity = (try? LedgerAmountParser.split(written).get().commodity.isEmpty == false) ?? false
            posting.assertion = RawAssertion(amount: amount, isExact: isExact, isInclusive: isInclusive,
                                             isAnyCommodity: amount.quantity == 0 && !hasCommodity)
        }
        if let at = Self.topLevelIndex(of: "@", in: rest) {
            var price = rest[rest.index(after: at)...]
            rest = rest[..<at]
            let isTotal = price.first == "@"
            if isTotal { price = price.dropFirst() }
            if price.first == "=" { price = price.dropFirst() }
            posting.price = RawPrice(amount: try amount(price.trimmingCharacters(in: .whitespaces), loader: &loader,
                                                        isPosting: false),
                                     isTotal: isTotal)
        }
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("(") {
            throw AmountProblem(message: "value expressions in brackets aren't supported")
        }
        var amountText = Substring(trimmed)
        let annotationStarts: [Character] = ["{", "[", "("]
        if let annotation = annotationStarts.compactMap({ Self.topLevelIndex(of: $0, in: amountText) }).min() {
            let annotations = amountText[annotation...]
            amountText = amountText[..<annotation]
            if let open = annotations.firstIndex(of: "{") {
                var inner = annotations[annotations.index(after: open)...]
                let isTotal = inner.first == "{"
                if isTotal { inner = inner.dropFirst() }
                guard let close = inner.firstIndex(of: "}") else {
                    throw AmountProblem(message: "a lot price without its closing brace")
                }
                var lot = inner[..<close]
                if lot.first == "=" { lot = lot.dropFirst() }
                posting.lot = RawPrice(amount: try amount(lot.trimmingCharacters(in: .whitespaces), loader: &loader,
                                                          isPosting: false),
                                       isTotal: isTotal)
            }
        }
        let written = amountText.trimmingCharacters(in: .whitespaces)
        if !written.isEmpty {
            posting.amount = try amount(written, loader: &loader, isPosting: true)
        } else if posting.price != nil || posting.lot != nil {
            throw AmountProblem(message: "a price without an amount")
        }
    }

    private func amount(_ text: String, loader: inout LedgerLoader, isPosting: Bool) throws(AmountProblem) -> ParsedAmount {
        let parts: AmountText
        switch LedgerAmountParser.split(text) {
        case .success(let value): parts = value
        case .failure(let error): throw AmountProblem(message: error.description)
        }
        let commodity = parts.commodity.isEmpty ? (state.defaultCommodity ?? "") : parts.commodity
        let mark = loader.commodityMarks[commodity] ?? state.decimalMark
        guard let (value, decimals) = LedgerAmountParser.value(of: parts.number, negative: parts.negative, mark: mark,
                                                               fallback: state.fallbackMark) else {
            throw AmountProblem(message: AmountError.badNumber(parts.number).description)
        }
        if isPosting { loader.precision[commodity] = max(loader.precision[commodity] ?? 0, decimals) }
        return ParsedAmount(quantity: value, commodity: commodity, decimals: decimals)
    }

    /// The text before a `;` comment (outside quotes).
    static func withoutComment(_ text: Substring) -> Substring {
        var quoted = false
        for index in text.indices {
            if text[index] == "\"" { quoted.toggle() }
            if !quoted, text[index] == ";" { return text[..<index] }
        }
        return text
    }

    /// The first `character` outside quotes and brackets.
    private static func topLevelIndex(of character: Character, in text: Substring) -> Substring.Index? {
        var quoted = false
        var depth = 0
        for index in text.indices {
            let current = text[index]
            if current == "\"" { quoted.toggle(); continue }
            if quoted { continue }
            if current == character, depth == 0 { return index }
            if "{[(".contains(current) { depth += 1 }
            if "}])".contains(current) { depth = max(0, depth - 1) }
        }
        return nil
    }

    // MARK: - Directives

    private mutating func directive(_ line: Substring, at location: LedgerLocation, loader: inout LedgerLoader) {
        let content = Self.withoutComment(line).trimmingCharacters(in: .whitespaces)
        let word = content.prefix { $0 != " " && $0 != "\t" }
        let argument = content.dropFirst(word.count).trimmingCharacters(in: .whitespaces)
        switch word {
        case "include", "!include":
            loader.include(argument, from: url, at: location, state: state)
        case "P":
            price(argument, at: location, loader: &loader)
        case "account":
            let account = state.fullName(String(Substring(argument).prefix { $0 != "\t" }
                .components(separatedBy: "  ").first ?? "").trimmingCharacters(in: .whitespaces))
            guard !account.isEmpty else { return unsupported("`account` without a name", at: location, &loader) }
            if !loader.declared.contains(account) { loader.declared.append(account) }
            if let type = Self.accountType(in: line) { loader.types[account] = type }
            block = .account(account)
        case "commodity":
            if argument.contains(where: TextTools.isDigit) {
                commodityFormat(argument, symbol: nil, loader: &loader)
                block = .skipping
            } else {
                block = .commodity(argument.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
            }
        case "D":
            if let symbol = commodityFormat(argument, symbol: nil, loader: &loader) {
                state.defaultCommodity = symbol
            } else {
                unsupported("`D` without a sample amount", at: location, &loader)
            }
        case "alias":
            guard let alias = LedgerAlias(argument) else {
                return unsupported("“alias \(argument)” isn't an alias", at: location, &loader)
            }
            state.aliases.append(alias)
        case "apply", "!account":
            let words = argument.split(separator: " ", maxSplits: 1).map(String.init)
            if word == "!account" {
                state.parents.append(argument)
            } else if words.first == "account", words.count == 2 {
                state.parents.append(words[1].trimmingCharacters(in: .whitespaces))
            } else if words.first == "year", words.count == 2, let year = Int(words[1]) {
                state.year = year
            } else {
                loader.diagnostics.append(LedgerDiagnostic(.note, "“apply \(argument)” was ignored.", at: location))
            }
        case "end", "!end":
            let what = argument.lowercased()
            if what.hasPrefix("aliases") {
                state.aliases = []
            } else if what.isEmpty || what.hasPrefix("apply account") || what == "apply" {
                if !state.parents.isEmpty { state.parents.removeLast() }
            }
        case "Y", "year":
            guard let year = Int(argument) else { return unsupported("“\(content)” isn't a year", at: location, &loader) }
            state.year = year
        case "decimal-mark":
            guard argument == "." || argument == "," else {
                return unsupported("`decimal-mark` must be . or ,", at: location, &loader)
            }
            state.decimalMark = argument.first
        case "comment", "test":
            block = .comment
        default:
            if word.count > 1, word.first == "Y", let year = Int(word.dropFirst()) {
                state.year = year
                return
            }
            let skipped = ["define", "tag", "payee", "assert", "check", "bucket", "A", "N", "C", "eval", "expr", "value",
                           "python", "import", "def", "capture", "i", "o", "I", "O", "b", "h"]
            if skipped.contains(String(word)) || word.hasPrefix("--") {
                loader.diagnostics.append(LedgerDiagnostic(
                    .warning, "The `\(word)` directive isn't supported; it was skipped.", at: location))
            } else {
                loader.diagnostics.append(LedgerDiagnostic(
                    .warning, "“\(content.prefix(40))” isn't understood; it was skipped.", at: location))
            }
            block = .skipping
        }
    }

    private mutating func unsupported(_ message: String, at location: LedgerLocation, _ loader: inout LedgerLoader) {
        loader.diagnostics.append(LedgerDiagnostic(.warning, message + "; it was skipped.", at: location))
        block = .skipping
    }

    /// A format sample (`1.000,00 EUR`): remembers the commodity's decimal
    /// mark. Returns the commodity.
    @discardableResult
    private func commodityFormat(_ sample: String, symbol: String?, loader: inout LedgerLoader) -> String? {
        guard case .success(let parts) = LedgerAmountParser.split(sample) else { return nil }
        let commodity = symbol ?? parts.commodity
        if let mark = LedgerAmountParser.formatMark(parts.number) { loader.commodityMarks[commodity] = mark }
        return commodity
    }

    /// `P DATE [TIME] COMMODITY PRICE`.
    private func price(_ argument: String, at location: LedgerLocation, loader: inout LedgerLoader) {
        var rest = Substring(argument)
        func token() -> Substring {
            rest = rest.drop { $0 == " " || $0 == "\t" }
            if rest.first == "\"", let close = rest.dropFirst().firstIndex(of: "\"") {
                let quoted = rest[rest.index(after: rest.startIndex)..<close]
                rest = rest[rest.index(after: close)...]
                return quoted
            }
            let word = rest.prefix { $0 != " " && $0 != "\t" }
            rest = rest.dropFirst(word.count)
            return word
        }
        let dateText = token()
        guard case .success(let date) = Self.date(String(dateText), year: state.year) else {
            loader.diagnostics.append(LedgerDiagnostic(.error, "“\(dateText)” isn't a date; the price was skipped.",
                                                       at: location))
            return
        }
        var commodity = token()
        if commodity.contains(":") { commodity = token() }
        let priceText = rest.trimmingCharacters(in: .whitespaces)
        guard !commodity.isEmpty, !priceText.isEmpty else {
            loader.diagnostics.append(LedgerDiagnostic(.error, "A `P` directive needs a commodity and a price.",
                                                       at: location))
            return
        }
        do {
            let price = try amount(priceText, loader: &loader, isPosting: false)
            let record = LedgerMarketPrice(date: date, commodity: String(commodity), price: price.amount,
                                           location: location)
            loader.prices.append((record, loader.sequence))
            loader.sequence += 1
        } catch {
            loader.diagnostics.append(LedgerDiagnostic(
                .error, "The price “\(priceText)” can't be read: \(error.message).", at: location))
        }
    }

    /// hledger's `type:` tag in an `account` directive's comment.
    private static func accountType(in text: Substring) -> LedgerAccountType? {
        guard let comment = text.firstIndex(of: ";") else { return nil }
        let lowered = text[comment...].lowercased()
        guard let range = lowered.range(of: "type:") else { return nil }
        let value = lowered[range.upperBound...].drop { $0 == " " }.prefix { $0.isLetter }
        switch value {
        case "a", "asset", "assets": return .asset
        case "l", "liability", "liabilities": return .liability
        case "e", "equity": return .equity
        case "r", "revenue", "revenues", "income": return .revenue
        case "x", "expense", "expenses": return .expense
        case "c", "cash": return .cash
        case "v", "conversion": return .conversion
        default: return nil
        }
    }
}
