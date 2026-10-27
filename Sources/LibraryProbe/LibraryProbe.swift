import Foundation
import CryptoKit
import SQLite3

public struct ProbeFailure: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
}

// Every connection has one owner and is used only on the probe's worker task.
final class Database {
    let handle: OpaquePointer

    init(path: String, readOnly: Bool) throws {
        var connection: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let status = sqlite3_open_v2(path, &connection, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let connection else {
            let reason = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "No connection"
            if let connection { sqlite3_close(connection) }
            throw ProbeFailure(message: "Cannot open database (SQLite \(status)): \(reason)")
        }
        handle = connection
        sqlite3_busy_timeout(handle, 2_000)
        if readOnly {
            guard sqlite3_db_readonly(handle, "main") == 1 else {
                throw ProbeFailure(message: "Source connection is not read-only.")
            }
        }
    }

    deinit { sqlite3_close(handle) }

    func rows(_ sql: String) throws -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw failure("Prepare query")
        }
        defer { sqlite3_finalize(statement) }
        var result: [[String?]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw failure("Read query") }
            result.append((0..<sqlite3_column_count(statement)).map { index in
                sqlite3_column_text(statement, index).map { String(cString: $0) }
            })
        }
    }

    func failure(_ operation: String) -> ProbeFailure {
        ProbeFailure(message: "\(operation): \(String(cString: sqlite3_errmsg(handle)))")
    }

    func snapshot(to destination: Database) throws {
        guard let backup = sqlite3_backup_init(destination.handle, "main", handle, "main") else {
            throw destination.failure("Start consistent snapshot")
        }
        // A bounded attempt avoids hanging indefinitely on a busy library.
        let deadline = Date().addingTimeInterval(15)
        var status: Int32 = SQLITE_OK
        repeat {
            status = sqlite3_backup_step(backup, 256)
            if status == SQLITE_BUSY || status == SQLITE_LOCKED { Thread.sleep(forTimeInterval: 0.05) }
        } while [SQLITE_OK, SQLITE_BUSY, SQLITE_LOCKED].contains(status) && Date() < deadline
        let finish = sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE, finish == SQLITE_OK else {
            throw ProbeFailure(message: "Snapshot did not complete (SQLite \(status), finish \(finish)). The library may be busy; try again.")
        }
    }
}

public struct ProbeReport: Sendable {
    public let text: String
    public let fingerprint: String
    public let overview: LibraryOverview?
}

public enum LibraryProbe {
    public static func databaseURL(in selection: URL) throws -> URL {
        // The user grants access to the whole package/directory, including WAL sidecars.
        let candidates = ["database/Photos.sqlite", "database/photos.db", "Photos.sqlite", "photos.db"]
        for relative in candidates {
            let url = selection.appendingPathComponent(relative)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return url
            }
        }
        throw ProbeFailure(message: "No Photos database was found or accessible. Select the .photoslibrary package or its database folder. macOS may separately restrict access to Photos data; this probe will not bypass that restriction.")
    }

    public static func inspect(selection: URL, progress: @Sendable (String) -> Void = { _ in }) throws -> ProbeReport {
        progress("Opening a read-only database snapshot…")
        let databaseURL = try databaseURL(in: selection)
        let source = try Database(path: databaseURL.path, readOnly: true)
        // SQLite backup includes committed WAL transactions; copying just Photos.sqlite can lose them.
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let snapshot = try Database(path: temporary.appendingPathComponent("snapshot.sqlite").path, readOnly: false)
        try source.snapshot(to: snapshot)
        progress("Checking the snapshot and library schema…")
        guard try snapshot.rows("PRAGMA quick_check").first?.first == "ok" else {
            throw ProbeFailure(message: "The database snapshot failed its consistency check.")
        }

        let tableNames = try snapshot.rows("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            .compactMap { $0.first ?? nil }
        var schema: [String: [String]] = [:]
        for table in tableNames {
            schema[table] = try snapshot.rows("PRAGMA table_info(\(quote(table)))").compactMap { $0[1] }
        }
        let definition = schema.keys.sorted().map { "\($0):\(schema[$0]!.sorted().joined(separator: ","))" }.joined(separator: "\n")
        let fingerprint = SHA256.hash(data: Data(definition.utf8)).map { String(format: "%02x", $0) }.joined()
        let userVersion = try snapshot.rows("PRAGMA user_version").first?.first ?? nil
        var lines = [
            "Photos database access probe",
            "Probe revision: library-overview-v1",
            "System: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Source opened read-only: yes",
            "Consistent snapshot and quick_check: passed",
            "Database file: \(databaseURL.lastPathComponent)",
            "SQLite user_version: \(userVersion ?? "unknown") (not the Photos schema version)",
            "Schema fingerprint: \(fingerprint)",
            "Tables: \(tableNames.count)",
            "",
            "Compatibility: experimental probe; no production Photos adapter has been approved yet.",
            "Inventory counts below describe database records. Per-photo coverage follows for recognized schemas.",
            "Missing columns do not prove metadata is absent from the original image.",
            ""
        ]
        let candidates: [(String, [String])] = [
            ("ZASSET", ["ZWIDTH", "ZHEIGHT", "ZLATITUDE", "ZLONGITUDE", "ZDATECREATED"]),
            ("ZEXTENDEDATTRIBUTES", ["ZCAMERAMAKE", "ZCAMERAMODEL", "ZLENSMODEL", "ZAPERTURE", "ZSHUTTERSPEED", "ZFOCALLENGTH", "ZISO", "ZFLASHFIRED", "ZMETERINGMODE", "ZWHITEBALANCE", "ZEXPOSUREBIAS"])
        ]
        for (table, fields) in candidates {
            guard let columns = schema[table] else {
                lines.append("\(table): not found; schema requires investigation.")
                continue
            }
            let present = fields.filter { columns.contains($0) }
            let expressions = ["COUNT(*)"] + present.map { "COUNT(\(quote($0)))" }
            let counts = try snapshot.rows("SELECT \(expressions.joined(separator: ",")) FROM \(quote(table))").first ?? []
            lines.append("\(table): \(counts.first.flatMap { $0 } ?? "unknown") records")
            for field in fields {
                if let index = present.firstIndex(of: field) {
                    lines.append("  \(field): \(counts[index + 1] ?? "unknown") non-NULL values")
                } else { lines.append("  \(field): column not found") }
            }
        }
        var overview: LibraryOverview?
        if fingerprint == PhotoCoverage.observedFingerprint {
            let library = databaseURL.deletingLastPathComponent().lastPathComponent == "database"
                ? databaseURL.deletingLastPathComponent().deletingLastPathComponent() : selection
            let coverage = try PhotoCoverage.inspect(db: snapshot, schema: schema, library: library, progress: progress)
            lines += coverage.lines
            overview = coverage.overview
        } else {
            lines += ["", "Per-photo analysis skipped: unrecognized schema fingerprint."]
        }
        lines += ["", "No image files were opened. No network requests were made.",
                  "Temporary snapshot is removed after inspection.",
                  "Technical access does not establish Mac App Store acceptance."]
        return ProbeReport(text: lines.joined(separator: "\n"), fingerprint: fingerprint, overview: overview)
    }

    static func quote(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
