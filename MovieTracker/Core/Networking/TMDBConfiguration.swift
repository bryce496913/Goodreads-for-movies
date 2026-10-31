import Foundation

struct TMDBConfiguration: Sendable {
    // Intentionally not CustomStringConvertible, Codable, or persisted in app resources.
    let readAccessToken: String

    init(readAccessToken: String) throws {
        let token = readAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~+/=")
        guard !token.isEmpty, token != "YOUR_TMDB_API_READ_ACCESS_TOKEN",
              token.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw MetadataError.missingCredential
        }
        self.readAccessToken = token
    }

    /// Set through the local Xcode Run scheme environment, never Info.plist or source.
    static func localDevelopment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Self {
        try Self(readAccessToken: environment["TMDB_READ_ACCESS_TOKEN"] ?? "")
    }
}
