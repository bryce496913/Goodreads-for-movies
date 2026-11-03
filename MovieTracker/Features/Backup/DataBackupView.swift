import SwiftUI
import UniformTypeIdentifiers

struct PersonalBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents, bytes.count <= BackupCodec.maximumBytes else { throw BackupError.tooLarge }
        self.bytes = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard !bytes.isEmpty, bytes.count <= BackupCodec.maximumBytes else { throw BackupError.exportFailed }
        return FileWrapper(regularFileWithContents: bytes)
    }
}

struct DataBackupView: View {
    @Environment(LibraryStore.self) private var library
    @State private var model = DataBackupModel()
    @State private var exportPresented = false
    @State private var importPresented = false
    @State private var work: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Personal backup") {
                Text("Export your library membership, statuses, favorites, personal ratings, private reviews, viewing diary and episode watched flags. No internet connection is required.")
                Text("Provider titles, artwork, metadata caches and credentials are excluded. Restored titles may show identifiers until you retrieve metadata with an authorized provider configuration.").font(.footnote)
                if model.isBusy { ProgressView("Preparing personal data…").accessibilityIdentifier("backup.busy") }
                Button("Export My Data", systemImage: "square.and.arrow.up") {
                    work = Task {
                        await model.prepareExport(from: library)
                        if model.exportBytes != nil && !Task.isCancelled { exportPresented = true }
                    }
                }.buttonStyle(AppActionStyle()).disabled(model.isBusy).accessibilityIdentifier("backup.export")
                Button("Restore from Backup", systemImage: "square.and.arrow.down") { importPresented = true }
                    .buttonStyle(AppActionStyle())
                    .disabled(model.isBusy).accessibilityIdentifier("backup.import")
            }
            Section("Your privacy") {
                Text("The JSON file is not encrypted and includes private review text and viewing history. Choose a destination you trust and protect the file. The app does not upload it automatically.")
                Text("Export is manual, not automatic backup. Keep the file outside the app before deleting the app. Restore always shows a preview and keeps existing local records unchanged.")
            }
        }
        .appFormScreen("Export & Restore")
        .accessibilityIdentifier("screen.backup")
        .fileExporter(isPresented: $exportPresented, document: model.exportBytes.map { PersonalBackupDocument(bytes: $0) },
                      contentType: .json, defaultFilename: "MovieTracker-Personal-Backup") { model.finishExport($0) }
        .fileImporter(isPresented: $importPresented, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                work = Task { await model.prepareImport(url, into: library) }
            case .failure(let error): model.fileSelectionFailed(error)
            }
        }
        .sheet(isPresented: Binding(get: { model.preview != nil }, set: { if !$0 { model.cancelPreview() } })) {
            if let preview = model.preview {
                NavigationStack {
                    List {
                        Section("New records to add") {
                            Text("Library titles: \(preview.counts.library)")
                            Text("Reviews: \(preview.counts.reviews)")
                            Text("Viewing events: \(preview.counts.viewings)")
                            Text("Episode progress: \(preview.counts.progress)")
                            Text("Season anchors: \(preview.counts.anchors)")
                        }
                        Section("Existing data stays unchanged") {
                            Text("\(preview.kept) existing or conflicting records will be kept or skipped. \(preview.conflicts.count) conflicts need your acknowledgement.")
                            Text("Confirming uses Keep Existing Data for every conflict. Ratings, statuses, text, dates and watched states are never replaced. Cancel to make no changes.")
                            ForEach(Array(preview.conflicts.prefix(50).enumerated()), id: \.offset) { _, conflict in Text(conflict).font(.footnote) }
                            if preview.conflicts.count > 50 { Text("\(preview.conflicts.count - 50) additional conflicts also keep existing data.") }
                        }
                        Section {
                            Button("Confirm Merge — Keep Existing Data") { work = Task { await model.confirmRestore(into: library) } }
                                .disabled(model.isBusy).accessibilityIdentifier("backup.confirm")
                            if model.isBusy { ProgressView("Saving restore…") }
                        }
                    }
                    .appListScreen("Review Restore")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel", role: .cancel) { model.cancelPreview() }.disabled(model.isBusy).accessibilityIdentifier("backup.cancel")
                        }
                    }
                    .interactiveDismissDisabled(model.isBusy)
                }
                .appEditorSheet()
            }
        }
        .alert("Personal Backup", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .onDisappear {
            // Native document pickers can cover the parent screen. Retain their prepared buffer until completion.
            if !exportPresented && !importPresented && model.preview == nil { work?.cancel(); model.cancelWork() }
        }
    }
}
