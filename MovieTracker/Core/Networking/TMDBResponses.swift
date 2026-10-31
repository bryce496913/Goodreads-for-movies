import Foundation

// Raw provider objects never enter SwiftData or feature interfaces.
struct TMDBTitle: Decodable, Sendable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?
    let backdropPath: String?
    let genreIDs: [Int]?
    let genres: [TMDBGenre]?
    let runtime: Int?
    let episodeRunTime: [Int]?
    let numberOfSeasons: Int?
    let numberOfEpisodes: Int?
    let status: String?
    let mediaType: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, genres, runtime, status
        case releaseDate = "release_date", firstAirDate = "first_air_date"
        case posterPath = "poster_path", backdropPath = "backdrop_path"
        case genreIDs = "genre_ids", episodeRunTime = "episode_run_time"
        case numberOfSeasons = "number_of_seasons", mediaType = "media_type"
        case numberOfEpisodes = "number_of_episodes"
    }

    func movie() throws -> Movie {
        guard id > 0, let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MetadataError.invalidPayload
        }
        return Movie(
            id: "tmdb:\(id)", title: title, overview: overview ?? "",
            releaseDate: Self.date(releaseDate), posterReference: posterPath,
            genreIDs: mappedGenres, runtimeMinutes: runtime.flatMap { $0 > 0 ? $0 : nil },
            backdropReference: backdropPath, genres: mappedGenreNames
        )
    }

    func tvShow() throws -> TVShow {
        guard id > 0, let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MetadataError.invalidPayload
        }
        return TVShow(
            id: "tmdb:\(id)", title: name, overview: overview ?? "",
            firstAirDate: Self.date(firstAirDate), posterReference: posterPath,
            genreIDs: mappedGenres, seasonCount: numberOfSeasons.flatMap { $0 > 0 ? $0 : nil },
            episodeRuntimeMinutes: episodeRunTime?.first(where: { $0 > 0 }),
            backdropReference: backdropPath, genres: mappedGenreNames,
            episodeCount: numberOfEpisodes.flatMap { $0 > 0 ? $0 : nil },
            seriesStatus: status?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? status : nil
        )
    }

    private var mappedGenreNames: [MediaGenre] {
        var seen = Set<Int>()
        return (genres ?? []).compactMap { genre in
            let name = genre.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard genre.id > 0, !name.isEmpty, seen.insert(genre.id).inserted else { return nil }
            return MediaGenre(id: "tmdb:\(genre.id)", name: name)
        }
    }

    private var mappedGenres: [String] {
        (genreIDs ?? genres?.map(\.id) ?? []).filter { $0 > 0 }.map { "tmdb:\($0)" }
    }

    private static func date(_ value: String?) -> Date? {
        guard let value, value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
}

struct TMDBGenre: Decodable, Sendable { let id: Int; let name: String }
struct TMDBGenreList: Decodable, Sendable { let genres: [TMDBGenre] }

struct TMDBPage: Decodable, Sendable {
    let page: Int
    let totalPages: Int
    let totalResults: Int
    let results: [TMDBTitle]

    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages", totalResults = "total_results"
    }
}

struct TMDBImageConfiguration: Decodable, Sendable {
    let images: Images
    struct Images: Decodable, Sendable {
        let secureBaseURL: URL
        let posterSizes: [String]
        let backdropSizes: [String]
        enum CodingKeys: String, CodingKey {
            case secureBaseURL = "secure_base_url", posterSizes = "poster_sizes", backdropSizes = "backdrop_sizes"
        }
    }
}
