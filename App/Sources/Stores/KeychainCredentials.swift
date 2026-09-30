#if canImport(Security)
import Foundation
import Model
import Prices
import Security

/// Price-provider API keys in the Keychain (UI.md, "Settings": "API keys
/// (stored in the Keychain)"). Keys stay on this device and are never
/// written to the library.
struct KeychainCredentials: CredentialsProvider {
    /// The Keychain service the keys are stored under.
    static let service = "caniretireyet.price-api-keys"

    init() {}

    func apiKey(for provider: PriceProvider) async -> String? {
        Self.read(provider)
    }

    /// The stored key for `provider`, if any.
    static func read(_ provider: PriceProvider) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    /// Stores `key` for `provider`; an empty or `nil` key removes it.
    static func write(_ key: String?, for provider: PriceProvider) {
        let query = baseQuery(provider)
        SecItemDelete(query as CFDictionary)
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func baseQuery(_ provider: PriceProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
    }
}
#endif
