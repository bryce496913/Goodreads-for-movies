import Foundation

enum DiscoverySource: Hashable, Sendable { case watchlist, collection(UUID) }

struct DiscoveryFilters: Equatable, Hashable, Sendable {
    var media = LibraryMediaFilter.all
    var genres: Set<String> = [] // OR matching by provider genre identifier.
    var firstYear: Int? = nil
    var lastYear: Int? = nil
    var maximumMovieMinutes: Int? = nil
    var isValid: Bool {
        (firstYear.map { (1...9999).contains($0) } ?? true)
            && (lastYear.map { (1...9999).contains($0) } ?? true)
            && (firstYear == nil || lastYear == nil || firstYear! <= lastYear!)
            && (maximumMovieMinutes.map { $0 > 0 } ?? true)
    }
}

/// Scalar copies only: no ModelContext or live SwiftData objects leave the main actor.
struct DiscoveryInput: Sendable {
    let id: MediaID
    let library: LibraryItemInput?
    let payloads: [Data]
    let seriesPayloads: [Data]
}

struct DiscoveryCandidate: Identifiable, Equatable, Sendable {
    var id: MediaID { item.id }
    let item: SearchItem
    let genres: [MediaGenre]
    let movieMinutes: Int?
    let posterURL: URL?
    let metadataAvailable: Bool

    func retained(at now: Date) -> Self {
        guard MetadataPolicy.isTMDB(id), !MetadataPolicy.isUsable(item.metadataRetrievedAt, at: now) else { return self }
        return Self(item: SearchItem(MetadataPolicy.placeholderMedia(id)), genres: [], movieMinutes: nil,
                    posterURL: nil, metadataAvailable: false)
    }
}

enum WatchDiscoveryProjection {
    static func build(_ inputs: [DiscoveryInput], watchlist: Bool, at now: Date) throws -> [DiscoveryCandidate] {
        let ordered: [DiscoveryInput]
        if watchlist {
            let base = inputs.compactMap { input -> LibraryItem? in
                guard let library = input.library else { return nil }
                return LibraryItem(id: library.id, mediaID: input.id, title: MetadataPolicy.placeholder(input.id), year: nil,
                                   rawStatus: library.status, isFavorite: library.favorite, addedAt: library.addedAt, rating: .unrated)
            }
            let rows = try LibraryProjection.sort(base, by: .recentlyAdded)
            // IDs are deduplicated below, including malformed duplicate source rows.
            let byRecord = Dictionary(inputs.compactMap { input in input.library.map { ($0.id, input) } }, uniquingKeysWith: { first, _ in first })
            ordered = rows.compactMap { byRecord[$0.id] }
        } else { ordered = inputs }
        var seen: Set<MediaID> = []
        return try ordered.compactMap { input in
            try Task.checkCancellation()
            guard seen.insert(input.id).inserted else { return nil }
            let decoder = JSONDecoder()
            var snapshots = input.payloads.compactMap { try? decoder.decode(MediaSearchResult.self, from: $0) }
            snapshots += input.seriesPayloads.compactMap { try? decoder.decode(TVShow.self, from: $0) }.map(MediaSearchResult.tvShow)
            let valid = snapshots.filter { SearchItem($0).id == input.id && MetadataPolicy.mayDisplay($0, at: now) }
            let media = valid.max { ($0.metadataRetrievedAt ?? .distantPast) < ($1.metadataRetrievedAt ?? .distantPast) }
            let value = media ?? MetadataPolicy.placeholderMedia(input.id)
            let genres: [MediaGenre]
            let runtime: Int?
            switch value {
            case .movie(let movie): genres = movie.genres; runtime = movie.runtimeMinutes.flatMap { $0 > 0 ? $0 : nil }
            case .tvShow(let show): genres = show.genres; runtime = nil
            }
            let rawItem = SearchItem(value)
            let title = rawItem.title.trimmingCharacters(in: .whitespacesAndNewlines)
            var item = SearchItem(id: input.id, title: title.isEmpty ? MetadataPolicy.placeholder(input.id) : title,
                                 year: rawItem.year.flatMap { (1...9999).contains($0) ? $0 : nil }, posterReference: rawItem.posterReference)
            item.metadataRetrievedAt = rawItem.metadataRetrievedAt
            // Reuse a saved thumbnail URL only when it refers to this valid snapshot's artwork.
            let posterURL = input.library?.posterURL.flatMap { url -> URL? in
                guard media != nil, let reference = item.posterReference, reference.hasPrefix("/"), reference.count > 1,
                      url.path.hasSuffix(reference) else { return nil }
                return url
            }
            return DiscoveryCandidate(item: item, genres: genres.filter { !$0.id.isEmpty && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                movieMinutes: runtime, posterURL: posterURL, metadataAvailable: media != nil)
        }
    }

    static func filter(_ source: [DiscoveryCandidate], using options: DiscoveryFilters, at now: Date) throws -> [DiscoveryCandidate] {
        guard options.isValid else { return [] }
        // Reuse Library's media semantics. Stable source order is deliberately retained.
        return try source.map { $0.retained(at: now) }.filter { value in
            try Task.checkCancellation()
            guard LibraryProjection.matchesMedia(value.id, filter: options.media) else { return false }
            if !options.genres.isEmpty && options.genres.isDisjoint(with: value.genres.map(\.id)) { return false }
            if let first = options.firstYear, value.item.year.map({ $0 >= first }) != true { return false }
            if let last = options.lastYear, value.item.year.map({ $0 <= last }) != true { return false }
            if let maximum = options.maximumMovieMinutes {
                guard value.id.kind == .movie, let runtime = value.movieMinutes, runtime <= maximum else { return false }
            }
            return true
        }
    }

    /// Int.random uses the system generator with unbiased range sampling. Tests inject indices.
    static func pick(_ pool: [DiscoveryCandidate], index: (Range<Int>) -> Int = { Int.random(in: $0) }) -> DiscoveryCandidate? {
        guard !pool.isEmpty else { return nil }
        let selected = index(pool.indices)
        guard pool.indices.contains(selected) else { return nil }
        return pool[selected]
    }
}
