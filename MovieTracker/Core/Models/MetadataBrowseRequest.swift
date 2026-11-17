import Foundation

struct MetadataBrowseRequest: Hashable, Sendable {
    enum Category: Hashable, Sendable {
        case trending, popular, topRated, genre(String), similar(MediaID)
    }
    let kind: MediaID.Kind
    let category: Category
    var language = "en-US"
    var region: String? = nil
}
