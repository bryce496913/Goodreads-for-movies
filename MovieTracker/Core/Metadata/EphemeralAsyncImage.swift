import Foundation
import SwiftUI
import UIKit

@MainActor
final class ProviderArtworkCache {
    static let shared = ProviderArtworkCache()
    private struct Entry { let data: Data; let fetched: Date }
    private var values: [URL: Entry] = [:]
    private var order: [URL] = []
    func image(_ url: URL, at now: Date = .now) -> UIImage? {
        guard let entry = values[url], MetadataPolicy.isUsable(entry.fetched, at: now) else { values[url] = nil; order.removeAll { $0 == url }; return nil }
        return UIImage(data: entry.data)
    }
    func save(_ data: Data, url: URL, at now: Date) {
        guard data.count <= 2_000_000 else { return }
        if values[url] == nil { order.append(url) }; values[url] = Entry(data: data, fetched: now)
        while order.count > 40 { values[order.removeFirst()] = nil }
    }
    func clear() { values.removeAll(); order.removeAll() }
    func expire(at now: Date) {
        for url in order where values[url].map({ !MetadataPolicy.isUsable($0.fetched, at: now) }) == true { values[url] = nil }
        order.removeAll { values[$0] == nil }
    }
}

/// Images use an ephemeral, cache-disabled transport; no app-managed disk artwork survives expiry.
struct EphemeralAsyncImage<Content: View>: View {
    let url: URL?
    let content: (AsyncImagePhase) -> Content
    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) { self.url = url; self.content = content }
    @State private var phase = AsyncImagePhase.empty
    @Environment(LibraryStore.self) private var library
    var body: some View {
        content(phase)
            .task(id: url) {
                phase = .empty
                guard let url, url.scheme == "https", url.host == "image.tmdb.org", url.user == nil,
                      url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else { return }
                if let image = ProviderArtworkCache.shared.image(url) { phase = .success(Image(uiImage: image)); return }
                do {
                    let transport = URLSessionMetadataTransport()
                    let response = try await transport.send(URLRequest(url: url))
                    try Task.checkCancellation()
                    guard response.status == 200, response.data.count <= 2_000_000, let image = UIImage(data: response.data) else { throw MetadataError.invalidPayload }
                    ProviderArtworkCache.shared.save(response.data, url: url, at: .now)
                    phase = .success(Image(uiImage: image))
                } catch { if !Task.isCancelled { phase = .failure(error) } }
            }
            .onChange(of: library.metadataReferenceDate) { _, now in
                if let url, ProviderArtworkCache.shared.image(url, at: now) == nil { phase = .failure(MetadataError.metadataExpired) }
            }
    }
}
