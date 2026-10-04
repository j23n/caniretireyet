import Foundation
import Model

extension ImportLayout {
    /// Whether each row of a file in this layout is one record (long and
    /// trades), rather than one date (wide).
    public var rowIsRecord: Bool { self == .long || self == .trades }
}

extension ImportField {
    /// Whether a column holding this field holds numbers.
    public var holdsNumbers: Bool {
        [.value, .quantity, .price, .amount, .gross, .fees, .tax, .ratio].contains(self)
    }

    /// The fields of the trades layout, in menu order.
    public static let tradeFields: [ImportField] = [
        .type, .account, .instrument, .quantity, .price, .currency, .amount, .gross, .fees, .tax, .ratio, .note,
        .settlement,
    ]
}

/// The trades layout (IMPORT.md, "Broker transactions"): a row per trade,
/// the file's type words mapped to trade types.
extension ImportSession {
    // MARK: - Types

    /// The file column holding the trades' types, if one does.
    public var tradeTypeColumn: Int? {
        guard profile.layout == .trades else { return nil }
        return bindings.columns.sorted { $0.key < $1.key }.first { profile.columns[$0.value].field == .type }?.key
    }

    /// The trade type a value of the type column is read as, and why: the
    /// profile's `tradeTypes`, else the default words, else nothing.
    public func tradeType(for value: String) -> (type: TradeType?, source: TradeTypeValue.Source) {
        if let type = TradeTypeWords.lookup(value, in: profile.tradeTypes) { return (type, .profile) }
        if let type = TradeTypeWords.suggestion(for: value) { return (type, .suggested) }
        return (nil, .unmapped)
    }

    /// Every value of the type column, in the order the file first has them
    /// (spellings that differ only in case and accents are one value), with
    /// the trade type it's read as.
    public var tradeTypeValues: [TradeTypeValue] {
        guard let column = tradeTypeColumn else { return [] }
        var values: [TradeTypeValue] = []
        var index: [String: Int] = [:]
        for (_, text) in table.values(inColumn: column) {
            let folded = TextTools.fold(text)
            if let at = index[folded] {
                values[at].count += 1
                continue
            }
            let (type, source) = tradeType(for: text)
            index[folded] = values.count
            values.append(TradeTypeValue(value: text, count: 1, type: type, source: source,
                                         suggestion: TradeTypeWords.suggestion(for: text)))
        }
        return values
    }

    /// Maps a value of the type column to a trade type (``TradeTypeWords/ignore``
    /// leaves its rows out), remembered in the profile's `tradeTypes`; `nil`
    /// forgets it, so the default words apply again.
    public mutating func setTradeType(_ type: TradeType?, for value: String) {
        let folded = TextTools.fold(value)
        for key in profile.tradeTypes.keys where TextTools.fold(key) == folded {
            profile.tradeTypes[key] = nil
        }
        if let type { profile.tradeTypes[value] = type }
    }

    // MARK: - Detecting a transactions file

    /// Whether the file looks like a broker's transactions export: a text
    /// column whose values are mostly trade types (`Acquisto`, `Dividend`),
    /// or a quantity column with negative values (sells), next to a
    /// quantity or price column.
    public var looksLikeTransactions: Bool {
        Self.transactionsEvidence(detection.columns, table: table) != nil
    }

    /// The type column (or `0` when the quantities' signs are the only
    /// evidence), if the file looks like transactions.
    static func transactionsEvidence(_ columns: [ColumnAnalysis], table: ImportTable) -> Int? {
        let numbers = columns.filter { $0.kind == .number }
        let hasQuantity = numbers.contains { Keywords.header(tradeHeader($0.header), has: Keywords.quantity) }
        let hasPrice = numbers.contains { Keywords.header(tradeHeader($0.header), has: Keywords.price) }
        guard hasQuantity || hasPrice else { return nil }
        if let column = typeColumn(columns, table: table) { return column }
        // No type column: sells written as negative quantities (Degiro), next to prices.
        guard hasQuantity, hasPrice else { return nil }
        for analysis in numbers where Keywords.header(tradeHeader(analysis.header), has: Keywords.quantity) {
            let parser = NumberParser(format: analysis.number ?? ImportNumberFormat())
            let values = table.values(inColumn: analysis.column).compactMap { try? parser.parse($0.text).get().value }
            if values.contains(where: { $0 < 0 }), values.contains(where: { $0 > 0 }) { return 0 }
        }
        return nil
    }

    /// The text column most of whose values are trade types (at least half,
    /// and two different types), else one whose header names types.
    static func typeColumn(_ columns: [ColumnAnalysis], table: ImportTable) -> Int? {
        var best: (column: Int, share: Double)?
        for analysis in columns where analysis.kind == .text {
            let values = table.values(inColumn: analysis.column).map(\.text)
            guard !values.isEmpty else { continue }
            let types = values.compactMap(TradeTypeWords.suggestion(for:))
            let share = Double(types.count) / Double(values.count)
            guard share >= 0.5, Set(types).count >= 2 else { continue }
            if share > (best?.share ?? 0) { best = (analysis.column, share) }
        }
        if let best { return best.column }
        return columns.first {
            $0.kind == .text && Keywords.header(tradeHeader($0.header), has: Keywords.tradeType)
        }?.column
    }

    // MARK: - Proposing a mapping

    /// Proposes the trades layout's columns from the headers and values:
    /// the first date column, the type column, instrument names, tickers and
    /// ISINs, the account and currency, and the numbers by their headers
    /// (quantity, price, net amount, gross value, fees, tax). Each field is
    /// used once, by the column whose header says it most plainly (`Net
    /// cash` over `Amount`), except the instrument, which up to three
    /// columns can give; the rest is ignored.
    mutating func proposeTradesMapping() {
        let columns = detection.columns
        let dateColumn = columns.first { $0.kind == .date }?.column
        let typeColumn = Self.typeColumn(columns, table: table)
        var candidates: [(column: Int, field: ImportField, priority: Int)] = []
        for analysis in columns {
            let column = analysis.column
            if column == dateColumn {
                candidates.append((column, .date, 1))
            } else if column == typeColumn {
                candidates.append((column, .type, 1))
            } else if analysis.kind == .text {
                let field = Self.tradeTextField(analysis, values: table.values(inColumn: column).map(\.text))
                candidates.append((column, field, 1))
            } else if analysis.kind == .number {
                let (field, priority) = Self.tradeNumberField(analysis)
                candidates.append((column, field, priority))
            } else {
                candidates.append((column, .ignore, 0))
            }
        }
        var winners: [ImportField: Int] = [:]
        for candidate in candidates where candidate.field != .ignore && candidate.field != .instrument {
            if let current = winners[candidate.field],
               candidates.first(where: { $0.column == current })!.priority >= candidate.priority { continue }
            winners[candidate.field] = candidate.column
        }
        var instruments = 0
        for candidate in candidates {
            var field = candidate.field
            if field == .instrument {
                instruments += 1
                if instruments > 3 { field = .ignore }
            } else if field != .ignore, winners[field] != candidate.column {
                field = .ignore
            }
            let header = table.header(of: candidate.column)
            profile.columns.append(ImportColumn(header: header, index: header == nil ? candidate.column : nil,
                                                field: field))
        }
    }

    /// A header with camel case and underscores spaced out, for keywords:
    /// `NetCash` → `Net Cash`.
    static func tradeHeader(_ header: String?) -> String? {
        header.map(TextTools.spaced)
    }

    /// What a text column of a trades file holds, by its header, else by its values.
    static func tradeTextField(_ analysis: ColumnAnalysis, values: [String]) -> ImportField {
        let header = tradeHeader(analysis.header)
        if Keywords.header(header, has: Keywords.currency) { return .currency }
        if Keywords.header(header, has: Keywords.tradeInstrument) { return .instrument }
        if Keywords.header(header, has: Keywords.tradeNote) { return .note }
        if Keywords.header(header, has: Keywords.tradeAccount) { return .account }
        if !values.isEmpty, values.allSatisfy({ CurrencyMarkers.currency(in: $0) != nil }) { return .currency }
        if !values.isEmpty, values.allSatisfy(Self.looksLikeISIN) { return .instrument }
        return .ignore
    }

    /// What a number column of a trades file holds, by its header, and how
    /// plainly the header says it (2 for `Netto`, `Lordo`; 1 otherwise).
    static func tradeNumberField(_ analysis: ColumnAnalysis) -> (ImportField, Int) {
        let header = tradeHeader(analysis.header)
        if analysis.number?.percent == true { return (.ignore, 0) }
        // Values in another currency than the account's, and rates.
        if Keywords.header(header, has: Keywords.tradeSkip) { return (.ignore, 0) }
        if Keywords.header(header, has: Keywords.tradeNet) { return (.amount, 2) }
        if Keywords.header(header, has: Keywords.tradeGrossMarkers) { return (.gross, 2) }
        if Keywords.header(header, has: Keywords.tradeFees) { return (.fees, 1) }
        if Keywords.header(header, has: Keywords.tradeTax) { return (.tax, 1) }
        if Keywords.header(header, has: Keywords.quantity) { return (.quantity, 1) }
        if Keywords.header(header, has: Keywords.price) { return (.price, 1) }
        if Keywords.header(header, has: Keywords.tradeGross) { return (.gross, 1) }
        if Keywords.header(header, has: Keywords.tradeAmount) { return (.amount, 1) }
        if Keywords.header(header, has: Keywords.tradeRatio) { return (.ratio, 1) }
        return (.ignore, 0)
    }

    /// `IE00BK5BQT80`: two letters, nine letters or digits, a check digit.
    static func looksLikeISIN(_ text: String) -> Bool {
        let compact = text.filter { !$0.isWhitespace }
        return compact.count == 12 && compact.prefix(2).allSatisfy { $0.isASCII && $0.isUppercase }
            && compact.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
            && compact.last?.isNumber == true
    }
}
