import Foundation

struct MetadataPage<Item: Sendable>: Sendable {
    let items: [Item]
    let page: Int
    let totalPages: Int
    let totalResults: Int

    var nextPage: Int? { page < totalPages ? page + 1 : nil }
}

enum MediaSearchResult: Codable, Equatable, Sendable {
    case movie(Movie)
    case tvShow(TVShow)
}

protocol MediaMetadataService: Sendable {
    func searchMovies(query: String, page: Int) async throws -> MetadataPage<Movie>
    func searchTVShows(query: String, page: Int) async throws -> MetadataPage<TVShow>
    func searchAll(query: String, page: Int) async throws -> MetadataPage<MediaSearchResult>
    func movieDetails(id: MediaID) async throws -> Movie
    func tvShowDetails(id: MediaID) async throws -> TVShow
    func genres(for kind: MediaID.Kind) async throws -> [MediaGenre]
    func castPreview(for id: MediaID) async throws -> [CastMember]
    func tvSeasons(for id: MediaID) async throws -> [TVSeasonSummary]
    func tvSeasonDetails(for id: MediaID, number: Int) async throws -> TVSeasonDetails
    func imageResolver() async throws -> MetadataImageResolver
    func expireMetadataMemory(at now: Date) async
}

enum MetadataError: Error, Equatable, Sendable {
    case missingCredential
    case invalidCredentialFormat
    case credentialUnavailable
    case retentionBlocked
    case refreshDeferred
    case metadataExpired
    case invalidQuery
    case invalidPage
    case invalidIdentifier
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfter: String?)
    case server(status: Int)
    case http(status: Int)
    case offline
    case connectionLost
    case connectionFailed
    case dnsFailure
    case secureTransport
    case timedOut
    case transport
    case invalidResponse
    case emptyResponse
    case invalidPayload
}

extension MetadataError {
    var isConfigurationFailure: Bool {
        switch self { case .missingCredential, .invalidCredentialFormat, .credentialUnavailable, .retentionBlocked: true; default: false }
    }
}

extension MetadataError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .refreshDeferred: "Metadata updates are paused after a recent failure. Your saved data remains available; retry when the connection has recovered."
        case .metadataExpired: "Provider metadata expired. Your personal records remain available; retry online to retrieve current metadata."
        case .retentionBlocked: "Provider metadata is paused because a retained safety archive needs review. Your personal library remains available."
        case .credentialUnavailable: "The device credential store is unavailable. Unlock the device and check Profile Settings."
        case .invalidCredentialFormat: "Enter the raw TMDB API Read Access Token without a Bearer prefix or internal whitespace."
        case .forbidden: "The metadata provider refused access to this resource. Check the account’s permissions."
        case .notFound: "The requested metadata is no longer available from the provider. Your personal records are unchanged."
        case .connectionLost: "The connection was interrupted. Try again when it is stable."
        case .connectionFailed: "A connection to the metadata provider could not be established."
        case .dnsFailure: "The metadata provider’s address could not be resolved. Check your connection and try again."
        case .secureTransport: "A secure connection to the metadata provider could not be verified."
        case .missingCredential: "Add an authorized TMDB read access token in Profile Settings to retrieve new metadata."
        case .invalidQuery: "Enter a nonempty search query."
        case .invalidPage: "The requested results page is out of range."
        case .invalidIdentifier: "This title does not have a supported metadata identifier."
        case .unauthorized: "The metadata provider did not authorize this credential."
        case .rateLimited: "The metadata provider is busy. Try again later."
        case .server: "The metadata provider is temporarily unavailable."
        case .http: "The metadata provider could not complete this request."
        case .offline: "An internet connection is required to retrieve metadata."
        case .timedOut: "The metadata request timed out."
        case .transport: "The metadata request could not be completed."
        case .invalidResponse, .emptyResponse, .invalidPayload: "The metadata provider returned an unusable response."
        }
    }
}

// Providers/mocks without credits support may explicitly return an empty preview.
extension MediaMetadataService {
    func expireMetadataMemory(at now: Date) async {}
    func castPreview(for id: MediaID) async throws -> [CastMember] { [] }
    func tvSeasons(for id: MediaID) async throws -> [TVSeasonSummary] { throw MetadataError.invalidPayload }
    func tvSeasonDetails(for id: MediaID, number: Int) async throws -> TVSeasonDetails { throw MetadataError.invalidPayload }
}
