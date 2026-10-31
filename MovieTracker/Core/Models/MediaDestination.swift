import Foundation

/// One route shared with future full details; the snapshot keeps navigation stable during search changes.
struct MediaDestination: Hashable, Sendable {
    let id: MediaID
    let title: String
    let year: Int?
}
