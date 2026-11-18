import Foundation
import ImageIO
import Observation
import SwiftUI
import UIKit

enum ProviderArtworkURL {
    /// Normalize only already allowed, sized provider paths; encoded aliases share a key.
    static func cacheURL(_ url: URL) -> URL? {
        guard isAllowed(url) else { return nil }
        let parts = url.path.split(separator: "/")
        return URL(string: "https://image.tmdb.org/t/p")?
            .appendingPathComponent(String(parts[2])).appendingPathComponent(String(parts[3]))
    }
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
@Observable
final class ProviderArtworkCache {
    static let shared = ProviderArtworkCache()
    private struct Entry { let image: UIImage; let fetched: Date; let cost: Int }
    private var values: [URL: Entry] = [:]
    private var order: [URL] = []
    private let capacity: Int
    private let maximumBytes: Int
    private(set) var byteCount = 0
    private(set) var generation = UUID()
    private(set) var revision = 0
    init(capacity: Int = ProviderArtworkPolicy.memoryEntries, maximumBytes: Int = ProviderArtworkPolicy.memoryBytes) {
        self.capacity = max(1, capacity); self.maximumBytes = max(1, maximumBytes)
    }
    func image(_ url: URL, at now: Date = .now) -> UIImage? {
        guard let url = ProviderArtworkURL.cacheURL(url) else { return nil }
        guard let entry = values[url], MetadataPolicy.isUsable(entry.fetched, at: now) else { remove(url); return nil }
        order.removeAll { $0 == url }; order.append(url)
        return entry.image
    }
    @discardableResult
    func save(_ data: Data, url: URL, at now: Date) -> Bool {
        guard let url = ProviderArtworkURL.cacheURL(url), !data.isEmpty,
              data.count <= ProviderArtworkPolicy.maximumResponseBytes, now.timeIntervalSinceReferenceDate.isFinite,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache as String: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue,
              width > 0, height > 0,
              width <= ProviderArtworkPolicy.maximumPixelDimension, height <= ProviderArtworkPolicy.maximumPixelDimension else { return false }
        // Inspect encoded dimensions/frame count before UIKit can allocate a large decoded image.
        let estimatedCost = data.count + width * height * 4
        guard estimatedCost <= maximumBytes, let image = UIImage(data: data), let pixels = image.cgImage,
              pixels.width == width, pixels.height == height else { return false }
        let cost = data.count + pixels.width * pixels.height * 4
        guard cost <= maximumBytes else { return false }
        remove(url); values[url] = Entry(image: image, fetched: now, cost: cost)
        order.append(url); byteCount += cost; revision += 1
        while order.count > capacity || byteCount > maximumBytes { remove(order[0]) }
        return true
    }
    private func remove(_ url: URL) {
        if let value = values.removeValue(forKey: url) { byteCount -= value.cost; revision += 1 }
        order.removeAll { $0 == url }
    }
    func clear() { values.removeAll(); order.removeAll(); byteCount = 0; generation = UUID(); revision += 1 }
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
            .onChange(of: ProviderArtworkCache.shared.generation) { _, _ in
                phase = .failure(CancellationError())
            }
            .onChange(of: library.metadataReferenceDate) { _, now in
                if let url, ProviderArtworkCache.shared.image(url, at: now) == nil { phase = .failure(MetadataError.metadataExpired) }
            }
    }
}
