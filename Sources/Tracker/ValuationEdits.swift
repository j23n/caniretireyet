import Foundation
import Model

// Editing history after the fact: a value added in the past, corrected,
// moved or removed. A valuation's flow is the money added since the
// valuation before it (PROGRESS.md, "Data this needs from day one"), so an
// edit can change what the next valuation's flow should be.

/// How ``Library/editValuations(_:)`` kept the flows of the valuations after
/// an edit in step.
public struct FlowFollowUp: Hashable, Sendable {
    /// Valuations whose flow was the automatic one for their account's kind,
    /// worked out again from the valuation now before them; as saved now,
    /// sorted by date, then account.
    public var recomputed: [Valuation] = []
    /// Valuations whose flow was typed by hand, kept although the valuation
    /// before them changed; sorted by date, then account.
    public var kept: [Valuation] = []

    public init() {}

    /// Whether no other valuation's flow was concerned.
    public var isEmpty: Bool {
        recomputed.isEmpty && kept.isEmpty
    }
}

/// What saving one value with ``Library/saveValue(_:replacing:)`` did
/// besides writing it.
public struct ValueEdit: Hashable, Sendable {
    /// The account's opening date before the save, when the value was dated
    /// before it: the opening date moved back to the value's date.
    public var movedOpeningFrom: CalendarDate?
    /// The flows of the account's later values that were worked out again or kept.
    public var flows: FlowFollowUp

    public init(movedOpeningFrom: CalendarDate? = nil, flows: FlowFollowUp = FlowFollowUp()) {
        self.movedOpeningFrom = movedOpeningFrom
        self.flows = flows
    }
}

extension Library {
    /// Makes `edit` to the library's history and keeps the flows of the
    /// valuations that follow the ones it changed in step.
    ///
    /// When the valuation an account's valuation follows changes (a value
    /// inserted before it, the one before it corrected, moved or removed),
    /// its flow is worked out again from the new previous valuation if it was
    /// the automatic one: the default for the account's kind measured from
    /// the old previous valuation, as a check-in would have filled it in
    /// (``Valuator/defaultFlow(for:previous:paid:)``, with what was paid read
    /// from the cost bases). A flow typed by hand (one that differs from
    /// that default) is kept. The valuations `edit` writes keep what it gave
    /// them.
    @discardableResult
    public mutating func editValuations(_ edit: (inout Library) throws -> Void) rethrows -> FlowFollowUp {
        let before = self
        try edit(&self)
        return followFlows(from: before)
    }

    /// Adds or replaces one account's value outside a check-in (*Update
    /// Value*, the valuation editor): writes `valuation`, in place of the one
    /// at `old` when given, moves the account's opening date back to the
    /// value's date when it's earlier (with a pension fund's joining date
    /// that was the opening date, see ``Account/moveOpening(to:)``), and
    /// keeps the flows of the values after it in step (see ``editValuations(_:)``).
    @discardableResult
    public mutating func saveValue(_ valuation: Valuation, replacing old: ValuationKey? = nil) -> ValueEdit {
        var movedFrom: CalendarDate?
        let flows = editValuations { library in
            if let old { library.removeValuation(old) }
            library.upsert(valuation)
            if let opened = library.accounts[valuation.account]?.opened, valuation.date < opened {
                library.accounts[valuation.account]?.moveOpening(to: valuation.date)
                movedFrom = opened
            }
        }
        return ValueEdit(movedOpeningFrom: movedFrom, flows: flows)
    }

    /// What ``saveValue(_:replacing:)`` would do, without doing it: for a
    /// form to say it before saving.
    public func previewSavingValue(_ valuation: Valuation, replacing old: ValuationKey? = nil) -> ValueEdit {
        var copy = self
        return copy.saveValue(valuation, replacing: old)
    }

    /// Removes one value and keeps the flow of the value after it in step
    /// (see ``editValuations(_:)``). The account's opening date stays.
    @discardableResult
    public mutating func removeValue(_ key: ValuationKey) -> FlowFollowUp {
        editValuations { $0.removeValuation(key) }
    }

    // MARK: - Internals

    /// Brings the flows of the valuations that follow changed ones in step,
    /// comparing each account's history with `before`.
    mutating func followFlows(from before: Library) -> FlowFollowUp {
        let old = Dictionary(grouping: before.allValuations, by: \.account)
        let new = Dictionary(grouping: allValuations, by: \.account)
        var oldValuator = LazyValuator(library: before)
        var newValuator = LazyValuator(library: self)
        var result = FlowFollowUp()
        for account in new.keys.sorted() {
            let newList = new[account] ?? []
            let oldList = old[account] ?? []
            guard newList != oldList else { continue }
            let oldIndices = Dictionary(oldList.enumerated().map { ($1.key, $0) }, uniquingKeysWith: { first, _ in first })
            for (index, valuation) in newList.enumerated() {
                // A valuation the edit wrote keeps what the edit gave it.
                guard let oldIndex = oldIndices[valuation.key], oldList[oldIndex] == valuation else { continue }
                let oldPrevious = oldIndex > 0 ? oldList[oldIndex - 1] : nil
                let newPrevious = index > 0 ? newList[index - 1] : nil
                guard oldPrevious != newPrevious else { continue }
                let automatic = oldValuator.valuator.defaultFlow(
                    for: valuation, previous: oldPrevious, paid: CheckInRow.paid(in: valuation, since: oldPrevious))
                guard automatic == valuation.flow else {
                    result.kept.append(valuation)
                    continue
                }
                var updated = valuation
                updated.flow = newValuator.valuator.defaultFlow(
                    for: valuation, previous: newPrevious, paid: CheckInRow.paid(in: valuation, since: newPrevious))
                guard updated != valuation else { continue }
                upsert(updated)
                result.recomputed.append(updated)
            }
        }
        result.recomputed = result.recomputed.sortedByKey()
        result.kept = result.kept.sortedByKey()
        return result
    }
}
