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

    func needsRefresh(revision: Int, now: Date) -> Bool {
        self.revision != revision || day != Self.day(now) || snapshot == nil
    }
    func refresh(_ input: DashboardInput, revision: Int, now: Date = .now) async {
        guard needsRefresh(revision: revision, now: now) else { return }
        generation = UUID(); let token = generation
        isLoading = true
        defer { if generation == token { isLoading = false } }
        let work = Task.detached(priority: .userInitiated) { try DashboardAggregator.aggregate(input, now: now) }
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
