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
        if ProcessInfo.processInfo.environment["TMDB_READ_ACCESS_TOKEN"] != nil {
            return TMDBMetadataService(configuration: try TMDBConfiguration.localDevelopment())
        }
        #endif
        let token = try credentialStorage().read() ?? ""
        return TMDBMetadataService(configuration: try TMDBConfiguration(readAccessToken: token))
    }
}
