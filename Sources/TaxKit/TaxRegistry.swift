/// The tax systems available to the app or the CLI, registered in one place:
///
///     let registry = TaxRegistry([ItalyTaxSystem(), GenericTaxSystem()])
///
/// The planner looks systems up by the IDs in a plan's residence timeline.
public struct TaxRegistry: Sendable {
    /// The registered systems, in registration order.
    public let systems: [any TaxSystem]

    /// Registers systems. If two share an ID, the later one wins.
    public init(_ systems: [any TaxSystem]) {
        var seen: Set<String> = []
        self.systems = systems.reversed().filter { seen.insert($0.id).inserted }.reversed()
    }

    /// The IDs of the registered systems.
    public var ids: [String] {
        systems.map(\.id)
    }

    /// The system with this ID.
    public func system(_ id: String) -> (any TaxSystem)? {
        systems.first { $0.id == id }
    }

    public subscript(id: String) -> (any TaxSystem)? {
        system(id)
    }

    /// The regime with this ID in any system, with its system.
    public func regime(_ id: String) -> (system: any TaxSystem, regime: RegimeDescriptor)? {
        for system in systems {
            if let regime = system.regime(id) { return (system, regime) }
        }
        return nil
    }

    /// The wrapper with this ID in any system. Used when an account's wrapper
    /// belongs to a system other than the current residence's.
    public func wrapper(_ id: String) -> WrapperRule? {
        systems.lazy.compactMap { $0.wrapper(id) }.first
    }

    /// The pension scheme with this ID in any system.
    public func pensionScheme(_ id: String) -> (any PensionScheme)? {
        systems.lazy.compactMap { $0.pensionScheme(id) }.first
    }
}
