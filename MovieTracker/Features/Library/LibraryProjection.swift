import Foundation

/// Only Sendable value snapshots cross to this computation. No SwiftData objects/context.
enum LibraryProjection {
    struct Result: Sendable { let source: [LibraryItem]; let sorted: [LibraryItem]; let visible: [LibraryItem] }
    static func project(source: [LibraryItem], sorted: [LibraryItem]?, query: String, options: LibraryOptions) throws -> Result {
        try Task.checkCancellation()
        let ordered = try sorted ?? sort(source, by: options.sort)
        return Result(source: source, sorted: ordered, visible: try filter(ordered, query: query, options: options))
    }
    static func filter(_ sorted: [LibraryItem], query: String, options: LibraryOptions) throws -> [LibraryItem] {
        let needle = LibraryText.normalize(query)
        return try sorted.filter { item in
            try Task.checkCancellation()
            return (options.media == .all || (options.media == .movies && item.mediaID?.kind == .movie)
                || (options.media == .tvShows && item.mediaID?.kind == .tvShow))
                && (options.status.storedValue == nil || item.rawStatus == options.status.storedValue)
                && (!options.favoritesOnly || item.isFavorite)
                && (needle.isEmpty || item.normalizedTitle.contains(needle))
        }
    }
    static func sort(_ source: [LibraryItem], by sort: LibrarySort) throws -> [LibraryItem] {
        return try source.sorted { lhs, rhs in
            try Task.checkCancellation()
            switch sort {
            case .recentlyAdded:
                if lhs.addedAt != rhs.addedAt { return lhs.addedAt > rhs.addedAt }
            case .title: break
            case .year:
                if lhs.year != rhs.year {
                    if let left = lhs.year, let right = rhs.year { return left > right }
                    return lhs.year != nil
                }
            case .rating:
                if lhs.rating.rank != rhs.rating.rank { return lhs.rating.rank < rhs.rating.rank }
                if lhs.rating.value?.halfStarUnits != rhs.rating.value?.halfStarUnits {
                    return (lhs.rating.value?.halfStarUnits ?? 0) > (rhs.rating.value?.halfStarUnits ?? 0)
                }
            }
            if lhs.normalizedTitle != rhs.normalizedTitle { return lhs.normalizedTitle < rhs.normalizedTitle }
            if lhs.mediaID?.kind.rawValue != rhs.mediaID?.kind.rawValue { return (lhs.mediaID?.kind.rawValue ?? "~") < (rhs.mediaID?.kind.rawValue ?? "~") }
            if lhs.mediaID?.value != rhs.mediaID?.value { return (lhs.mediaID?.value ?? "~") < (rhs.mediaID?.value ?? "~") }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
