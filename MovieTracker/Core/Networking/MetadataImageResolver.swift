import Foundation

/// Built from provider configuration, with no downloads or custom image cache.
struct MetadataImageResolver: Sendable {
    enum PosterSize: String, Sendable { case thumbnail = "w185", card = "w342", detail = "w500" }
    enum BackdropSize: String, Sendable { case card = "w300", detail = "w780" }

    private let baseURL: URL
    private let posterSizes: Set<String>
    private let backdropSizes: Set<String>

    init(baseURL: URL, posterSizes: [String], backdropSizes: [String]) throws {
        guard baseURL.scheme == "https", baseURL.host == "image.tmdb.org",
              baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil,
              baseURL.port == nil else { throw MetadataError.invalidPayload }
        self.baseURL = baseURL
        self.posterSizes = Set(posterSizes)
        self.backdropSizes = Set(backdropSizes)
    }

    func posterURL(reference: String?, size: PosterSize = .thumbnail) -> URL? {
        resolve(reference, size: size.rawValue, available: posterSizes)
    }

    func backdropURL(reference: String?, size: BackdropSize = .card) -> URL? {
        resolve(reference, size: size.rawValue, available: backdropSizes)
    }

    private func resolve(_ reference: String?, size: String, available: Set<String>) -> URL? {
        guard available.contains(size), let reference,
              reference.hasPrefix("/"), !reference.hasPrefix("//") else { return nil }
        let name = String(reference.dropFirst())
        // TMDB image paths are single filenames; reject absolute URLs and traversal.
        guard !name.isEmpty, name != ".", name != "..",
              name.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
              }) else { return nil }
        return baseURL.appendingPathComponent(size).appendingPathComponent(name)
    }
}
