/// iCloud Drive on iOS can keep a file that isn't downloaded yet as a hidden
/// placeholder next to where the file will be: `accounts/.directa.json.icloud`
/// stands for `accounts/directa.json`.
///
/// ``CoordinatedFileAccess`` lists such files under their real names, so the
/// library loads them (a coordinated read downloads a file first).
public enum ICloudPlaceholder {
    /// The placeholder's file name for a file name: `directa.json` →
    /// `.directa.json.icloud`.
    public static func placeholderName(for name: String) -> String {
        ".\(name).icloud"
    }

    /// The real file name a placeholder stands for, or `nil` if `name` isn't
    /// a placeholder's: `.directa.json.icloud` → `directa.json`.
    public static func realName(forPlaceholder name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        let real = String(name.dropFirst().dropLast(".icloud".count))
        return real.isEmpty || real.hasPrefix(".") ? nil : real
    }

    /// A path relative to a folder with its last component replaced by the
    /// real name, if it's a placeholder: `accounts/.directa.json.icloud` →
    /// `accounts/directa.json`.
    public static func realPath(forPlaceholderPath path: String) -> String? {
        var parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let last = parts.last, let real = realName(forPlaceholder: last) else { return nil }
        parts[parts.count - 1] = real
        guard parts.dropLast().allSatisfy({ !$0.hasPrefix(".") }) else { return nil }
        return parts.joined(separator: "/")
    }
}
