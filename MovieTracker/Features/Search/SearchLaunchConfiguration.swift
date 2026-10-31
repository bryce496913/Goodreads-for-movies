import Foundation

@MainActor
enum SearchLaunchConfiguration {
    static func makeModel() -> SearchModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-search") {
            let mode = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--detail-fixture=") }
                .map { String($0.dropFirst("--detail-fixture=".count)) } ?? "complete"
            return SearchModel(service: SearchUITestService(detailScenario: mode), usesTestData: true)
        }
        #endif
        let service = try? TMDBMetadataService(configuration: TMDBConfiguration.localDevelopment())
        return SearchModel(service: service)
    }
}
