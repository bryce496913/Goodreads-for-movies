import XCTest
@testable import MovieTracker

@MainActor
final class TMDBBrowseTests: XCTestCase {
    func testDocumentedEndpointsLanguageRegionAndTypedIdentity() async throws {
        let cases: [(MediaID.Kind, MetadataBrowseRequest.Category, String)] = [
            (.movie, .trending, "trending/movie/week"), (.tvShow, .trending, "trending/tv/week"),
            (.movie, .popular, "movie/popular"), (.tvShow, .popular, "tv/popular"),
            (.movie, .topRated, "movie/top_rated"), (.tvShow, .topRated, "tv/top_rated"),
            (.movie, .genre("tmdb:18"), "discover/movie"), (.tvShow, .genre("tmdb:35"), "discover/tv"),
            (.movie, .similar(.init(kind: .movie, value: "tmdb:7")), "movie/7/similar"),
            (.tvShow, .similar(.init(kind: .tvShow, value: "tmdb:7")), "tv/7/similar")
        ]
        var identities = Set<MediaID>()
        for (kind, category, path) in cases {
            let transport = BrowseHTTPTransport([.success(payload(kind))])
            let service = try makeService(transport)
            let page = try await service.browse(.init(kind: kind, category: category, language: "fr-FR", region: "FR"), page: 1)
            let item = try XCTUnwrap(page.items.first.map(SearchItem.init))
            identities.insert(item.id)
            XCTAssertEqual(item.id.kind, kind)
            XCTAssertNotNil(item.metadataRetrievedAt)
            XCTAssertNil(item.year)
            XCTAssertNil(item.posterReference)
            let requests = await transport.requests
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.url?.path, "/3/" + path)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-not-a-credential")
            let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query["language"], "fr-FR")
            XCTAssertEqual(query["page"], category == .trending ? nil : "1")
            let supportsRegion = kind == .movie && [MetadataBrowseRequest.Category.popular, .topRated, .genre("tmdb:18")].contains(category)
            XCTAssertEqual(query["region"], supportsRegion ? "FR" : nil)
            if case .genre(let genre) = category {
                XCTAssertEqual(query["with_genres"], String(genre.dropFirst(5)))
                XCTAssertEqual(query["sort_by"], "popularity.desc")
            }
        }
        XCTAssertEqual(identities.count, 2) // Same numeric ID, separate movie/TV identity.
    }

    func testInvalidPageIdentifierLanguageAndKindNeverReachTransport() async throws {
        let transport = BrowseHTTPTransport([])
        let service = try makeService(transport)
        let cases: [(MetadataBrowseRequest, Int, MetadataError)] = [
            (.init(kind: .movie, category: .trending), 2, .invalidPage),
            (.init(kind: .movie, category: .popular), 501, .invalidPage),
            (.init(kind: .movie, category: .genre("tmdb:018")), 1, .invalidIdentifier),
            (.init(kind: .movie, category: .similar(.init(kind: .tvShow, value: "tmdb:7"))), 1, .invalidIdentifier),
            (.init(kind: .movie, category: .popular, language: "invalid"), 1, .invalidQuery)
        ]
        for (request, page, expected) in cases {
            do { _ = try await service.browse(request, page: page); XCTFail("Expected validation failure") }
            catch { XCTAssertEqual(error as? MetadataError, expected) }
        }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testMovieAndTVGenreListsRemainSeparate() async throws {
        let transport = BrowseHTTPTransport([
            .success(.init(data: Data(#"{"genres":[{"id":18,"name":"Drama"}]}"#.utf8), status: 200, retryAfter: nil)),
            .success(.init(data: Data(#"{"genres":[{"id":35,"name":"Comedy"}]}"#.utf8), status: 200, retryAfter: nil))
        ])
        let service = try makeService(transport)
        let movies = try await service.discoveryGenres(for: .movie, language: "en-US")
        let tv = try await service.discoveryGenres(for: .tvShow, language: "en-US")
        XCTAssertEqual(movies.first?.id, "tmdb:18")
        XCTAssertEqual(tv.first?.id, "tmdb:35")
        let paths = await transport.requests.compactMap { $0.url?.path }
        XCTAssertEqual(paths, ["/3/genre/movie/list", "/3/genre/tv/list"])
    }

    func testHTTPFailuresAndMalformedResponsesUseSharedTypedErrors() async throws {
        let fixtures: [(MetadataHTTPResponse, MetadataError)] = [
            (.init(data: Data(), status: 401, retryAfter: nil), .unauthorized),
            (.init(data: Data(), status: 403, retryAfter: nil), .forbidden),
            (.init(data: Data(), status: 429, retryAfter: "30"), .rateLimited(retryAfter: "30")),
            (.init(data: Data("invalid".utf8), status: 200, retryAfter: nil), .invalidPayload),
            (.init(data: Data(), status: 200, retryAfter: nil), .emptyResponse)
        ]
        for (response, expected) in fixtures {
            let transport = BrowseHTTPTransport([.success(response)])
            do { _ = try await makeService(transport).browse(.init(kind: .movie, category: .popular), page: 1); XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? MetadataError, expected) }
            let count = await transport.requests.count
            XCTAssertEqual(count, 1)
        }
    }

    func testMismatchedMediaTypeAndIncorrectPageAreRejected() async throws {
        for json in [
            #"{"page":1,"total_pages":1,"total_results":1,"results":[{"id":7,"title":"Story","media_type":"tv"}]}"#,
            #"{"page":2,"total_pages":2,"total_results":0,"results":[]}"#
        ] {
            let transport = BrowseHTTPTransport([.success(.init(data: Data(json.utf8), status: 200, retryAfter: nil))])
            do { _ = try await makeService(transport).browse(.init(kind: .movie, category: .popular), page: 1); XCTFail("Expected failure") }
            catch { XCTAssertEqual(error as? MetadataError, .invalidPayload) }
        }
    }

    private func makeService(_ transport: BrowseHTTPTransport) throws -> TMDBMetadataService {
        TMDBMetadataService(configuration: try TMDBConfiguration(readAccessToken: "fixture-not-a-credential"), transport: transport, retryPolicy: .none)
    }
    private func payload(_ kind: MediaID.Kind) -> MetadataHTTPResponse {
        let field = kind == .movie ? "title" : "name"
        let json = "{\"page\":1,\"total_pages\":2,\"total_results\":21,\"results\":[{\"id\":7,\"\(field)\":\"Story\",\"poster_path\":null}]}"
        return .init(data: Data(json.utf8), status: 200, retryAfter: nil)
    }
}

private actor BrowseHTTPTransport: MetadataTransport {
    private var responses: [Result<MetadataHTTPResponse, Error>]
    var requests: [URLRequest] = []
    init(_ responses: [Result<MetadataHTTPResponse, Error>]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> MetadataHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw MetadataError.transport }
        return try responses.removeFirst().get()
    }
}
