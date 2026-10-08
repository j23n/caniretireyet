import Foundation

/// FNV-1a, the 64-bit Fowler–Noll–Vo hash: the same for the same bytes on
/// every platform and in every version (unlike `Hasher`), for IDs and
/// fingerprints made from content.
public enum FNV1a {
    /// The hash of `data`.
    public static func hash(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// The hash of `data` as 16 lowercase hex digits.
    public static func hexHash(_ data: Data) -> String {
        let digits = String(hash(data), radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}
