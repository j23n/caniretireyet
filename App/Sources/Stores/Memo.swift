/// The last value worked out and what it was worked out from: asked again
/// for the same key, it gives the value back without working it out again.
/// Keys are usually the library's revision with whatever else the value
/// reads. Nothing observes it, so filling it while a view draws doesn't
/// draw again.
@MainActor
final class Memo<Key: Equatable, Value> {
    private var last: (key: Key, value: Value)?

    nonisolated init() {}

    /// The value for `key`: the last one when it's for the same key, else `make()`.
    func value(for key: Key, make: () -> Value) -> Value {
        if let last, last.key == key { return last.value }
        let value = make()
        last = (key, value)
        return value
    }
}
