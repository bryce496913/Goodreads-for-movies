import Foundation

@MainActor
enum SearchLaunchConfiguration {
    static func makeModel() -> SearchModel {
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing-search")
        #else
        let testing = false
        #endif
        return SearchModel(service: try? makeService(), usesTestData: testing)
    }

    static func credentialStorage() -> any MetadataCredentialStorage {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-search") { return UITestMetadataCredentialStorage.shared }
        #endif
        return KeychainMetadataCredentialStorage()
    }

    static func makeService() throws -> any MediaMetadataService {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-search") {
            let mode = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--detail-fixture=") }
                .map { String($0.dropFirst("--detail-fixture=".count)) } ?? "complete"
            return SearchUITestService(detailScenario: mode)
        }
        guard MetadataRuntimeGate.blockingReason == nil else { throw MetadataError.retentionBlocked }
        if ProcessInfo.processInfo.environment["TMDB_READ_ACCESS_TOKEN"] != nil {
            return authorizedService(try TMDBConfiguration.localDevelopment())
        }
        #endif
        guard MetadataRuntimeGate.blockingReason == nil else { throw MetadataError.retentionBlocked }
        let token = try credentialStorage().read() ?? ""
        return authorizedService(try TMDBConfiguration(readAccessToken: token))
    }
    private static func authorizedService(_ configuration: TMDBConfiguration) -> TMDBMetadataService {
        let epoch = MetadataRuntimeGate.credentialEpoch
        return TMDBMetadataService(configuration: configuration, authorization: { try await MetadataRuntimeGate.authorize(epoch) })
    }
}
