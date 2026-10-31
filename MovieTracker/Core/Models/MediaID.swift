import Foundation

/// The media kind is part of identity: movie "42" and TV show "42" are distinct.
/// Values belong to the app's domain; external provider IDs will be mapped at the boundary.
struct MediaID: Hashable, Codable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case movie
        case tvShow
    }

    let kind: Kind
    let value: String
}
