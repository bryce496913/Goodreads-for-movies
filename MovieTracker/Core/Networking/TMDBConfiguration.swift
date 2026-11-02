import Foundation

struct TMDBConfiguration: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    // Not Codable/persisted in resources. Descriptions and mirrors must never expose the raw token.
    var description: String { "TMDBConfiguration(readAccessToken: <redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["readAccessToken": "<redacted>"], displayStyle: .struct) }
    let readAccessToken: String

    init(readAccessToken: String) throws {
        let token = readAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~+/=")
        guard !token.isEmpty, !["YOUR_TMDB_API_READ_ACCESS_TOKEN", "YOUR_TMDB_READ_ACCESS_TOKEN", "ACCESS_TOKEN", "YOUR_TOKEN"].contains(token) else { throw MetadataError.missingCredential }
        guard token.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { throw MetadataError.invalidCredentialFormat }
        self.readAccessToken = token
    }

    /// Set through the local Xcode Run scheme environment, never Info.plist or source.
    static func localDevelopment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        try Self(readAccessToken: environment["TMDB_READ_ACCESS_TOKEN"] ?? "")
    }
}
