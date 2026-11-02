import Foundation
import Observation

@MainActor
@Observable
final class DashboardModel {
    private(set) var snapshot: DashboardSnapshot?
    private(set) var isLoading = false
    private var revision: Int?
    private var day: Date?
    private var generation = UUID()
    @ObservationIgnored private var worker: Task<DashboardSnapshot, Error>?
    @ObservationIgnored private let aggregate: @Sendable (DashboardInput, Date) async throws -> DashboardSnapshot

    init(aggregate: @escaping @Sendable (DashboardInput, Date) async throws -> DashboardSnapshot = { try DashboardAggregator.aggregate($0, now: $1) }) {
        self.aggregate = aggregate
    }

    func needsRefresh(revision: Int, now: Date) -> Bool {
        self.revision != revision || day != Self.day(now) || snapshot == nil
    }
    func refresh(_ input: DashboardInput, revision: Int, now: Date = .now) async {
        guard needsRefresh(revision: revision, now: now) else { return }
        worker?.cancel()
        generation = UUID(); let token = generation
        isLoading = true
        defer { if generation == token { isLoading = false; worker = nil } }
        let aggregate = aggregate
        let work = Task.detached(priority: .userInitiated) { try await aggregate(input, now) }
        worker = work
        do {
            let value = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            try Task.checkCancellation()
            guard generation == token else { return }
            snapshot = value; self.revision = revision; day = Self.day(now)
        } catch { /* Canceled work keeps the prior consistent snapshot; a newer revision can retry. */ }
    }
    private static func day(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        return calendar.startOfDay(for: date)
    }
}
