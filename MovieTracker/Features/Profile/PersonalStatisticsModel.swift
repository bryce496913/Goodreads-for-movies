import Foundation
import Observation

@MainActor @Observable
final class PersonalStatisticsModel {
    struct Source: Hashable, Sendable {
        let revision: Int
        let invalidation: Int
        let year: Int
        let timeZone: TimeZone
        let referenceDate: Date
    }
    var year: Int
    private(set) var snapshot: PersonalStatisticsSnapshot?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var prepared: Source?
    private var generation = UUID()
    @ObservationIgnored private var worker: Task<PersonalStatisticsSnapshot, Error>?
    @ObservationIgnored private let aggregate: @Sendable (PersonalStatisticsInput, Int, Date, TimeZone) async throws -> PersonalStatisticsSnapshot

    init(now: Date = .now, timeZone: TimeZone = .current,
         aggregate: @escaping @Sendable (PersonalStatisticsInput, Int, Date, TimeZone) async throws -> PersonalStatisticsSnapshot = {
             try DashboardAggregator.personalStatistics($0, year: $1, now: $2, timeZone: $3)
         }) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        year = calendar.component(.year, from: now); self.aggregate = aggregate
    }
    func isReady(for source: Source) -> Bool {
        guard let prepared, let snapshot, prepared.revision == source.revision,
              prepared.invalidation == source.invalidation, prepared.year == source.year,
              prepared.timeZone == source.timeZone, source.referenceDate >= prepared.referenceDate else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = source.timeZone
        guard calendar.isDate(prepared.referenceDate, inSameDayAs: source.referenceDate) else { return false }
        return snapshot.nextMetadataExpiry.map { $0 > source.referenceDate } ?? true
    }
    func expireMetadata(at now: Date) {
        if snapshot?.nextMetadataExpiry.map({ $0 <= now }) == true { snapshot = nil; prepared = nil }
    }
    /// Check before scalar capture so unrelated renders/minute ticks never recopy the full store.
    func refresh(_ input: PersonalStatisticsInput, source: Source, now: Date? = nil) async {
        guard !isReady(for: source), !Task.isCancelled else { return }
        worker?.cancel(); generation = UUID()
        let token = generation
        let aggregate = self.aggregate
        // The observation key uses the stable maintenance tick; a just-committed episode mark
        // may be newer than that tick, so the view supplies a fresh evaluation instant once.
        let evaluationDate = now ?? source.referenceDate
        isLoading = true; snapshot = nil; errorMessage = nil
        defer { if generation == token { isLoading = false; worker = nil } }
        let work = Task.detached(priority: .userInitiated) {
            try await aggregate(input, source.year, evaluationDate, source.timeZone)
        }
        worker = work
        do {
            let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
            try Task.checkCancellation()
            guard token == generation else { return }
            snapshot = result; prepared = source
        } catch is CancellationError { }
        catch { if token == generation { errorMessage = "Statistics could not be prepared. Reopen this screen to retry. Your saved data is unchanged." } }
    }
}
