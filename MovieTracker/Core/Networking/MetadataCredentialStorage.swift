import Foundation
import Security

@MainActor
protocol MetadataCredentialStorage {
    func read() throws -> String?
    func save(_ token: String) throws
    func remove() throws
}

/// A device-local provider credential, never an Info.plist value, build setting or library field.
@MainActor
struct KeychainMetadataCredentialStorage: MetadataCredentialStorage {
    private let service: String
    init(service: String = (Bundle.main.bundleIdentifier ?? "MovieTracker") + ".metadata") { self.service = service }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "tmdb.read-access-token"]
    }
    func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw MetadataCredentialError.unavailable
        }
        return token
    }
    func save(_ token: String) throws {
        let validated = try TMDBConfiguration(readAccessToken: token).readAccessToken
        let attributes: [String: Any] = [kSecValueData as String: Data(validated.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = query.merging(attributes) { _, new in new }
            guard SecItemAdd(added as CFDictionary, nil) == errSecSuccess else { throw MetadataCredentialError.unavailable }
        } else if status != errSecSuccess { throw MetadataCredentialError.unavailable }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MetadataCredentialError.unavailable }
    }
}

enum MetadataCredentialError: Error, LocalizedError {
    case unavailable
    var errorDescription: String? { "The device credential store could not be accessed. Unlock this device and try again. No library data was changed." }
}

#if DEBUG
/// UI tests must never read or overwrite a real credential in the simulator/device Keychain.
@MainActor
final class UITestMetadataCredentialStorage: MetadataCredentialStorage {
    static let shared = UITestMetadataCredentialStorage()
    private var token: String?
    func read() throws -> String? { token }
    func save(_ token: String) throws { self.token = try TMDBConfiguration(readAccessToken: token).readAccessToken }
    func remove() throws { token = nil }
}
#endif
