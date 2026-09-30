import Foundation

extension URL {
    /// This URL with percent-encoded path segments and query items appended,
    /// e.g. a symbol such as `^GSPC` or `EURUSD=X`.
    func appending(segments: [String], query: [(String, String)] = []) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        var path = components.percentEncodedPath
        for segment in segments {
            if !path.hasSuffix("/") { path += "/" }
            path += segment.addingPercentEncoding(withAllowedCharacters: .pathSegmentAllowed) ?? segment
        }
        components.percentEncodedPath = path
        if !query.isEmpty {
            components.percentEncodedQuery = query.map { name, value in
                "\(name.addingPercentEncoding(withAllowedCharacters: .queryValueAllowed) ?? name)="
                    + (value.addingPercentEncoding(withAllowedCharacters: .queryValueAllowed) ?? value)
            }.joined(separator: "&")
        }
        return components.url!
    }
}

extension CharacterSet {
    /// Characters left as they are in one path segment: unreserved, plus
    /// sub-delimiters and `:@`, but not `/`.
    static let pathSegmentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove("/")
        return set
    }()

    /// Characters left as they are in a query name or value: unreserved, plus `,`.
    static let queryValueAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~,")
}
