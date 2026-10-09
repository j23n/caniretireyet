import Model

extension Wording {
    /// Names for a sentence, each once: "A", "A and B", "A, B and C"
    /// (``list(_:or:)`` without the repeats, e.g. two instruments of the
    /// same name).
    static func names(_ names: [String]) -> String {
        list(names.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } })
    }
}
