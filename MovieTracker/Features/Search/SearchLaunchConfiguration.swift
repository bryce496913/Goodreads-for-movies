import Foundation

@MainActor
enum SearchLaunchConfiguration {
    static func makeModel() -> SearchModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-search") {
            return SearchModel(service: SearchUITestService(), usesTestData: true)
        }
        #endif
        let service = try? TMDBMetadataService(configuration: TMDBConfiguration.localDevelopment())
        return SearchModel(service: service)
    }
}
