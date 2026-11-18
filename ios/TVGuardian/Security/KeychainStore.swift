import Foundation
import Security
import CryptoKit

enum KeychainStore {
    private static let service = "com.tvguardian.secrets.v1"
    static func scopedAccount(_ namespace: String, origin: URL, identity: String = "") throws -> String {
        guard origin.scheme == "https", let host = origin.host else { throw GuardianError.invalid("A validated HTTPS origin is required for credential storage.") }
        let scope: [Any] = ["https", host.lowercased(), origin.port ?? 443, identity]
        let bytes = try JSONSerialization.data(withJSONObject: scope)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return namespace + "." + digest
    }
    static func read(_ account: String) throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw GuardianError.unavailable("Keychain read failed (\(status)). Unlock the iPhone and try again.") }
        guard let data = value as? Data else { throw GuardianError.protocolError("Unexpected Keychain data.") }
        return data
    }

    static func write(_ data: Data, account: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw GuardianError.unavailable("Keychain write failed (\(status)).") }
        } else if update != errSecSuccess { throw GuardianError.unavailable("Keychain update failed (\(update)).") }
    }

    static func string(_ account: String) throws -> String? {
        guard let data = try read(account) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else { throw GuardianError.protocolError("Invalid Keychain text.") }
        return value
    }
    static func writeString(_ value: String, account: String) throws { try write(Data(value.utf8), account: account) }
    static func remove(_ account: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw GuardianError.unavailable("Keychain deletion failed (\(status)).") }
    }
    static func random(count: Int) throws -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard result == errSecSuccess else { throw GuardianError.unavailable("Secure random generator failed.") }
        return data
    }
}
