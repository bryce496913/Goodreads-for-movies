import Foundation
import UIKit

/// Shares one request per sized URL. Canceling a consumer releases its waiter immediately;
/// only the last cancellation stops the transport. No disk files or URLCache are used.
@MainActor
final class ProviderArtworkLoader {
    static let shared = ProviderArtworkLoader(cache: .shared)
    private struct Receipt: Sendable { let data: Data; let fetched: Date }
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<Receipt, Error>]
    }
    private let cache: ProviderArtworkCache
    private let transport: any MetadataTransport
    private let clock: @Sendable () -> Date
    private let didRegister: @MainActor @Sendable (Int) -> Void
    private var flights: [URL: Flight] = [:]

    init(cache: ProviderArtworkCache, transport: any MetadataTransport = URLSessionMetadataTransport(),
         clock: @escaping @Sendable () -> Date = { .now },
         didRegister: @escaping @MainActor @Sendable (Int) -> Void = { _ in }) {
        self.didRegister = didRegister
        self.cache = cache; self.transport = transport; self.clock = clock
    }
    func image(_ url: URL) async throws -> UIImage {
        try Task.checkCancellation()
        guard ProviderArtworkURL.isAllowed(url) else { throw MetadataError.invalidIdentifier }
        let requestEpoch = MetadataRuntimeGate.credentialEpoch, requestCacheGeneration = cache.generation
        try MetadataRuntimeGate.authorize(requestEpoch)
        if let image = cache.image(url, at: clock()) { return image }
        let waiter = UUID()
        let receipt: Receipt = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                if flights[url] != nil {
                    flights[url]?.waiters[waiter] = continuation
                    didRegister(flights[url]?.waiters.count ?? 0)
                    return
                }
                guard flights.count < 20 else { continuation.resume(throwing: MetadataError.rateLimited(retryAfter: nil)); return }
                let id = UUID(), epoch = MetadataRuntimeGate.credentialEpoch, cacheGeneration = cache.generation
                let transport = transport
                let task = Task { [weak self] in
                    do {
                        let response = try await transport.send(URLRequest(url: url))
                        try Task.checkCancellation()
                        guard response.status == 200 else { throw MetadataError.http(status: response.status) }
                        self?.finish(url, id: id, epoch: epoch, cacheGeneration: cacheGeneration, result: .success(response.data))
                    } catch {
                        let failure: Error = error is CancellationError || Task.isCancelled ? CancellationError() : (error as? MetadataError) ?? .transport
                        self?.finish(url, id: id, epoch: epoch, cacheGeneration: cacheGeneration, result: .failure(failure))
                    }
                }
                flights[url] = Flight(id: id, task: task, waiters: [waiter: continuation])
                didRegister(1)
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel(url, waiter: waiter) } })
        try Task.checkCancellation()
        try MetadataRuntimeGate.authorize(requestEpoch)
        guard cache.generation == requestCacheGeneration else { throw CancellationError() }
        guard MetadataPolicy.isUsable(receipt.fetched, at: clock()) else { throw MetadataError.metadataExpired }
        guard let image = cache.image(url, at: clock()) ?? UIImage(data: receipt.data) else { throw MetadataError.invalidPayload }
        return image
    }
    private func cancel(_ url: URL, waiter: UUID) {
        guard let continuation = flights[url]?.waiters.removeValue(forKey: waiter) else { return }
        continuation.resume(throwing: CancellationError())
        if flights[url]?.waiters.isEmpty == true { flights.removeValue(forKey: url)?.task.cancel() }
    }
    private func finish(_ url: URL, id: UUID, epoch: Int, cacheGeneration: UUID, result: Result<Data, Error>) {
        guard let flight = flights[url], flight.id == id else { return }
        flights[url] = nil
        let output: Result<Receipt, Error>
        do {
            try MetadataRuntimeGate.authorize(epoch)
            guard cache.generation == cacheGeneration else { throw CancellationError() }
            let data = try result.get()
            let fetched = clock()
            guard cache.save(data, url: url, at: fetched) else { throw MetadataError.invalidPayload }
            output = .success(Receipt(data: data, fetched: fetched))
        } catch { output = .failure(error) }
        for continuation in flight.waiters.values { continuation.resume(with: output) }
    }
}
