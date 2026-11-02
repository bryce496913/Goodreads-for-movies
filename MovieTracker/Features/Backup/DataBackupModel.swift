import Foundation
import Observation

@MainActor
@Observable
final class DataBackupModel {
    private(set) var exportBytes: Data?
    private(set) var preview: BackupMergePlan?
    private(set) var isBusy = false
    var message: String?
    private var generation = UUID()

    func prepareExport(from store: LibraryStore) async {
        generation = UUID(); let token = generation
        isBusy = true; message = nil; exportBytes = nil
        defer { if generation == token { isBusy = false } }
        do {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            let snapshot = try store.capturePersonalBackup(applicationVersion: version)
            let worker = Task.detached(priority: .userInitiated) { try BackupCodec.encode(snapshot) }
            let bytes = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard generation == token else { return }
            exportBytes = bytes
        } catch {
            guard generation == token, !(error is CancellationError), !Task.isCancelled else { return }
            message = BackupError.exportFailed.localizedDescription
        }
    }
    func prepareImport(_ url: URL, into store: LibraryStore) async {
        generation = UUID(); let token = generation
        isBusy = true; message = nil; preview = nil
        defer { if generation == token { isBusy = false } }
        do {
            let local = try store.capturePersonalBackup(includeAllAnchors: true), revision = store.revision
            let worker = Task.detached(priority: .userInitiated) {
                try BackupMergePlanner.prepare(BackupCodec.read(url), local: local, revision: revision)
            }
            let plan = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            try Task.checkCancellation()
            guard generation == token else { return }
            guard store.revision == revision else { throw BackupError.libraryChanged }
            preview = plan
        } catch {
            guard generation == token, !(error is CancellationError), !Task.isCancelled else { return }
            message = ((error as? BackupError) ?? .invalidRecords).localizedDescription
        }
    }
    func confirmRestore(into store: LibraryStore) async {
        guard let preview, !isBusy else { return }
        generation = UUID(); let token = generation
        isBusy = true; message = nil
        defer { if generation == token { isBusy = false } }
        do {
            await Task.yield() // Permit the saving indicator before the serial transaction; no suspension inside it.
            try Task.checkCancellation()
            guard generation == token else { return }
            try store.restorePersonalBackup(preview)
            self.preview = nil
            message = "Restore saved: \(preview.counts.total) new records added; \(preview.kept) existing or conflicting records kept."
        } catch {
            guard generation == token, !(error is CancellationError), !Task.isCancelled else { return }
            self.preview = nil
            message = ((error as? BackupError) ?? .saveFailed).localizedDescription
        }
    }
    func cancelPreview() { if !isBusy { preview = nil } }
    func cancelWork() { generation = UUID(); isBusy = false; exportBytes = nil; preview = nil }
    func finishExport(_ result: Result<URL, Error>) {
        exportBytes = nil
        switch result {
        case .success: message = "Personal backup exported. Keep a separate copy somewhere you control."
        case .failure(let error):
            let value = error as NSError
            if value.domain != NSCocoaErrorDomain || value.code != CocoaError.Code.userCancelled.rawValue {
                message = BackupError.exportFailed.localizedDescription
            }
        }
    }
    func fileSelectionFailed(_ error: Error) {
        let value = error as NSError
        if value.domain != NSCocoaErrorDomain || value.code != CocoaError.Code.userCancelled.rawValue { message = BackupError.readFailed.localizedDescription }
    }
}
