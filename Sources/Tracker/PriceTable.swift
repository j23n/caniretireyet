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

    /// All prices of `instrument`, sorted by date.
    public func history(for instrument: InstrumentID) -> [PriceRecord] {
        byInstrument[instrument] ?? []
    }
}

extension Array {
    /// For an array sorted by date: the index of the last element dated on or
    /// before `limit`, found by binary search.
    func lastIndex(onOrBefore limit: CalendarDate, date: (Element) -> CalendarDate) -> Int? {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if date(self[mid]) <= limit { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }
}
