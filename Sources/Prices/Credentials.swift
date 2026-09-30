import Foundation
import Model

/// Supplies API keys to providers that accept one. The app backs it with the
/// Keychain; keys are never written to the library.
public protocol CredentialsProvider: Sendable {
    /// The API key for `provider`, or `nil` to use the provider without one.
    func apiKey(for provider: PriceProvider) async -> String?
}

/// API keys held in memory: for tests, previews, and the CLI (which reads
/// them from environment variables).
public struct StaticCredentials: CredentialsProvider {
    public var keys: [PriceProvider: String]

    /// Credentials with the given keys; none by default.
    public init(_ keys: [PriceProvider: String] = [:]) {
        self.keys = keys
    }

    /// The key for `provider`; an empty or blank key counts as none.
    public func apiKey(for provider: PriceProvider) async -> String? {
        guard let key = keys[provider]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        return key
    }
}
