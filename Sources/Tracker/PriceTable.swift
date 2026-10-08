import Model

/// Prices by instrument, for "latest price on or before a date" lookups.
public struct PriceTable: Sendable {
    private let byInstrument: [InstrumentID: [PriceRecord]]

    /// Indexes price records. For duplicate keys the last record wins.
    public init(_ records: some Sequence<PriceRecord>) {
        var byKey: [PriceKey: PriceRecord] = [:]
        for record in records { byKey[record.key] = record }
        byInstrument = Dictionary(grouping: byKey.values, by: \.instrument).mapValues { $0.sortedByKey() }
    }

    /// Indexes every price in the library.
    public init(library: Library) {
        self.init(library.months.values.lazy.flatMap(\.prices))
    }

    /// The latest price of `instrument` dated on or before `date`.
    public func latest(for instrument: InstrumentID, onOrBefore date: CalendarDate) -> PriceRecord? {
        guard let records = byInstrument[instrument],
              let index = records.lastIndex(onOrBefore: date, date: \.date)
        else { return nil }
        return records[index]
    }
}
