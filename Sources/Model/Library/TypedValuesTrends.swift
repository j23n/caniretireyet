import Foundation

extension Library {
    /// Whether `account`'s typed values turn Trends off: an account whose
    /// typed values count there (``Account/typedValuesCountInTrends``) with
    /// a value typed by hand after its first that lacks what moved
    /// (``Account/typedValueLacksWhatMoved(_:)``), so what it saved, or
    /// the pay that came into it, is unknown. Typing what moved into that
    /// value turns Trends back on.
    public func typedValuesTurnOffTrends(_ account: Account) -> Bool {
        guard account.typedValuesCountInTrends else { return false }
        return valuations(for: account.id).dropFirst().contains(where: account.typedValueLacksWhatMoved)
    }

    /// The accounts whose typed values turn Trends off
    /// (``typedValuesTurnOffTrends(_:)``), sorted by name.
    public var accountsTurningOffTrends: [Account] {
        accounts.values.filter(typedValuesTurnOffTrends)
            .sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }
}
