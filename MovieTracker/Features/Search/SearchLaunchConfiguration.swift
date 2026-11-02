import Foundation

@MainActor
enum SearchLaunchConfiguration {
    static func makeModel() -> SearchModel {
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing-search")
        #else
        let testing = false
        #endif
        let resolved = resolveService()
        return SearchModel(service: resolved.service, usesTestData: testing, configurationError: resolved.error)
    }

    static func resolveService() -> (service: (any MediaMetadataService)?, error: MetadataError) {
        do { return (try makeService(), .missingCredential) }
        catch { return (nil, (error as? MetadataError) ?? .credentialUnavailable) }
    }
    static func reconfigure(_ model: SearchModel) {
        let resolved = resolveService()
        model.replaceService(resolved.service, configurationError: resolved.error)
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
