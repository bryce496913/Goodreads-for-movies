import Foundation
import SQLite3

/// SQLite's online backup includes committed WAL pages. Never copy a live .store file alone.
/// This path is intentionally fail-closed: a backup failure prevents opening/migrating the source.
enum StoreSafetyBackup {
    struct Failure: Error { let code: Int32 }

    static func create(for source: URL) throws -> URL {
        guard let input = InputStream(url: source) else { throw Failure(code: SQLITE_CANTOPEN) }
        input.open()
        var header = [UInt8](repeating: 0, count: 16)
        let count = input.read(&header, maxLength: header.count)
        input.close()
        guard count == 16, header == Array("SQLite format 3\0".utf8) else { throw Failure(code: SQLITE_NOTADB) }
        let files = FileManager.default
        let directory = source.deletingLastPathComponent().appendingPathComponent("StoreSafetyBackups", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        var sourceDB: OpaquePointer?
        let opened = sqlite3_open_v2(source.path, &sourceDB, SQLITE_OPEN_READONLY, nil)
        guard opened == SQLITE_OK, let sourceDB else {
            if let sourceDB { sqlite3_close_v2(sourceDB) }
            throw Failure(code: opened)
        }
        defer { sqlite3_close_v2(sourceDB) }
        var backupDB: OpaquePointer?
        let created = sqlite3_open_v2(destination.path, &backupDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard created == SQLITE_OK, let backupDB else {
            if let backupDB { sqlite3_close_v2(backupDB) }
            throw Failure(code: created)
        }
        defer { sqlite3_close_v2(backupDB) }
        guard let backup = sqlite3_backup_init(backupDB, "main", sourceDB, "main") else {
            throw Failure(code: sqlite3_errcode(backupDB))
        }
        let copied = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard copied == SQLITE_DONE, finished == SQLITE_OK else {
            throw Failure(code: copied == SQLITE_DONE ? finished : copied)
        }
        // A complete marker is written only after a coherent backup succeeds. Failed attempts remain incomplete.
        try Data("SQLite online backup complete; contains private local data.\n".utf8)
            .write(to: directory.appendingPathComponent("COMPLETE"), options: .atomic)
        return directory
    }
}
