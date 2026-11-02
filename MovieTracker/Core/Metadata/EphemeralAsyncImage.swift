import Foundation
import SwiftUI
import UIKit

enum ProviderArtworkURL {
    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == "image.tmdb.org", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil else { return false }
        let parts = url.path.split(separator: "/")
        guard parts.count == 4, parts[0] == "t", parts[1] == "p",
              ["w185", "w300", "w342", "w500", "w780"].contains(String(parts[2])) else { return false }
        let name = parts[3]
        return name != "." && name != ".." && name.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
        }
    }
}

@MainActor
final class ProviderArtworkCache {
    static let shared = ProviderArtworkCache()
    private struct Entry { let image: UIImage; let fetched: Date; let cost: Int }
    private var values: [URL: Entry] = [:]
    private var order: [URL] = []
    private let capacity: Int
    private let maximumBytes: Int
    private(set) var byteCount = 0
    private(set) var generation = UUID()
    init(capacity: Int = 40, maximumBytes: Int = 40_000_000) {
        self.capacity = max(1, capacity); self.maximumBytes = max(1, maximumBytes)
    }
    func image(_ url: URL, at now: Date = .now) -> UIImage? {
        guard let entry = values[url], MetadataPolicy.isUsable(entry.fetched, at: now) else { remove(url); return nil }
        order.removeAll { $0 == url }; order.append(url)
        return entry.image
    }
    @discardableResult
    func save(_ data: Data, url: URL, at now: Date) -> Bool {
        guard ProviderArtworkURL.isAllowed(url), data.count <= 2_000_000, now.timeIntervalSinceReferenceDate.isFinite,
              let image = UIImage(data: data), let pixels = image.cgImage,
              pixels.width <= 2_048, pixels.height <= 2_048 else { return false }
        let cost = data.count + pixels.width * pixels.height * 4
        guard cost <= maximumBytes else { return false }
        remove(url); values[url] = Entry(image: image, fetched: now, cost: cost)
        order.append(url); byteCount += cost
        while order.count > capacity || byteCount > maximumBytes { remove(order[0]) }
        return true
    }
    private func remove(_ url: URL) {
        if let value = values.removeValue(forKey: url) { byteCount -= value.cost }
        order.removeAll { $0 == url }
    }
    func clear() { values.removeAll(); order.removeAll(); byteCount = 0; generation = UUID() }
    func expire(at now: Date) {
        for url in order where values[url].map({ !MetadataPolicy.isUsable($0.fetched, at: now) }) == true { remove(url) }
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
                guard let url else { phase = .failure(MetadataError.invalidIdentifier); return }
                do {
                    let image = try await ProviderArtworkLoader.shared.image(url)
                    try Task.checkCancellation()
                    phase = .success(Image(uiImage: image))
                } catch { if !Task.isCancelled { phase = .failure(error) } }
            }
            .onChange(of: library.metadataReferenceDate) { _, now in
                if let url, ProviderArtworkCache.shared.image(url, at: now) == nil { phase = .failure(MetadataError.metadataExpired) }
            }
    }
}
