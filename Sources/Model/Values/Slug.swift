import Foundation

/// Creates and checks the lowercase slugs used as IDs and file names
/// (`[a-z0-9-]+`).
public enum Slug {
    /// A slug made from a display name: diacritics are folded, letters
    /// lowercased, and every run of other characters becomes one hyphen.
    ///
    ///     Slug.make(from: "Conto Fineco") == "conto-fineco"
    ///     Slug.make(from: "Più Crédit")   == "piu-credit"
    ///
    /// A name with no usable letters or digits gives `"untitled"`.
    public static func make(from name: String) -> String {
        var slug = ""
        var pendingHyphen = false
        for scalar in name.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark { continue }
            let folded = specialFolds[scalar] ?? String(scalar)
            for character in folded.unicodeScalars {
                if isSlugCharacter(character), character != "-" {
                    if pendingHyphen, !slug.isEmpty { slug.append("-") }
                    pendingHyphen = false
                    slug.unicodeScalars.append(character)
                } else {
                    pendingHyphen = true
                }
            }
        }
        return slug.isEmpty ? "untitled" : slug
    }

    /// `slug` itself if it isn't taken, otherwise `slug-2`, `slug-3`, … — the
    /// first one not in `existing`.
    public static func unique(_ slug: String, among existing: some Sequence<String>) -> String {
        let taken = Set(existing)
        guard taken.contains(slug) else { return slug }
        var counter = 2
        while taken.contains("\(slug)-\(counter)") { counter += 1 }
        return "\(slug)-\(counter)"
    }

    /// Whether `string` is a valid slug: one or more of `a-z`, `0-9` and `-`.
    public static func isValid(_ string: String) -> Bool {
        !string.isEmpty && string.unicodeScalars.allSatisfy(isSlugCharacter)
    }

    private static func isSlugCharacter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
    }

    /// Lowercase letters that canonical decomposition doesn't reduce to ASCII.
    private static let specialFolds: [Unicode.Scalar: String] = [
        "ß": "ss", "æ": "ae", "œ": "oe", "ø": "o", "ł": "l", "đ": "d", "ð": "d", "þ": "th", "ı": "i",
    ]
}

/// A typed ID that is a slug, unique within its folder and equal to the
/// file name (without `.json`). An ID never changes once created.
public protocol SlugID: StringValue {}

extension SlugID {
    /// A new ID made from a display name, unique among `existing`.
    public static func make(from name: String, existing: some Sequence<Self>) -> Self {
        Self(rawValue: Slug.unique(Slug.make(from: name), among: existing.lazy.map(\.rawValue)))
    }
}
