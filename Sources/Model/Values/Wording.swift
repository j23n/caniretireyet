/// Counts and lists in English sentences, written the same way by the app,
/// the CLI and the messages of the other modules.
public enum Wording {
    /// "1 account", "2 accounts": the noun with an "s" unless there's one,
    /// or `plural` when that isn't it ("1 row skipped", "2 rows skipped").
    public static func count(_ count: Int, _ noun: String, plural: String? = nil) -> String {
        "\(count) \(count == 1 ? noun : plural ?? noun + "s")"
    }

    /// "a", "a and b", "a, b and c" (with `or`, "a, b or c"); "" for none.
    public static func list(_ items: [String], or: Bool = false) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + (or ? " or " : " and ") + last
    }
}

extension String {
    /// The string with its first letter capitalised, for the start of a
    /// sentence: "in 9 of 10 futures" → "In 9 of 10 futures".
    public var capitalizedFirst: String {
        self.prefix(1).uppercased() + self.dropFirst()
    }
}
