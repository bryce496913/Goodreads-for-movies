import Foundation

enum BackupCodec {
    static let maximumBytes = 32 * 1_024 * 1_024
    static func encode(_ value: PersonalBackup) throws -> Data {
        try value.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate // Exact Double seconds since the explicitly named 2001 UTC epoch.
        let canonical = value.canonical()
        let data = try encoder.encode(canonical)
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        guard try decode(data) == canonical else { throw BackupError.exportFailed }
        return data
    }
    static func decode(_ data: Data) throws -> PersonalBackup {
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        do {
            struct Header: Decodable { let format: String; let version: Int }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .deferredToDate
            let header = try decoder.decode(Header.self, from: data)
            guard header.format == "MovieTracker.personal-backup" else { throw BackupError.invalidFormat }
            guard header.version == 1 else { throw BackupError.unsupportedVersion(header.version) }
            let value = try decoder.decode(PersonalBackup.self, from: data)
            try value.validate(); return value
        } catch is CancellationError { throw CancellationError() }
        catch let error as BackupError { throw error }
        catch { throw BackupError.invalidRecords } // Never expose decoder paths/raw private text.
    }
    static func read(_ url: URL) throws -> PersonalBackup {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var bytes = Data()
            while bytes.count <= maximumBytes {
                try Task.checkCancellation()
                let chunk = try handle.read(upToCount: min(1_048_576, maximumBytes + 1 - bytes.count)) ?? Data()
                if chunk.isEmpty { break }
                bytes.append(chunk)
            }
            data = bytes
        } catch is CancellationError { throw CancellationError() }
        catch { throw BackupError.readFailed }
        try Task.checkCancellation()
        return try decode(data)
    }
}
