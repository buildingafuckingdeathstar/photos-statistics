import XCTest
import SQLite3
@testable import LibraryProbe

final class LibraryProbeTests: XCTestCase {
    func withFixture(_ body: (URL, Database) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Synthetic.photoslibrary/database")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = try Database(path: folder.appendingPathComponent("Photos.sqlite").path, readOnly: false)
        _ = try writer.rows("PRAGMA journal_mode=WAL")
        _ = try writer.rows("PRAGMA wal_autocheckpoint=0")
        _ = try writer.rows("CREATE TABLE ZASSET (Z_PK INTEGER PRIMARY KEY, ZWIDTH INTEGER, ZHEIGHT INTEGER)")
        _ = try writer.rows("CREATE TABLE ZEXTENDEDATTRIBUTES (ZCAMERAMODEL TEXT, ZAPERTURE REAL)")
        _ = try writer.rows("INSERT INTO ZASSET VALUES (1, 6000, 4000)")
        _ = try writer.rows("INSERT INTO ZEXTENDEDATTRIBUTES VALUES ('Synthetic Camera', 2.8), (NULL, NULL)")
        try body(root.appendingPathComponent("Synthetic.photoslibrary"), writer)
    }

    func testSnapshotIncludesCommittedWALAndLeavesSourceRowsUnchanged() throws {
        try withFixture { library, writer in
            let db = try LibraryProbe.databaseURL(in: library)
            XCTAssertTrue(FileManager.default.fileExists(atPath: db.path + "-wal"))
            let before = try writer.rows("SELECT * FROM ZEXTENDEDATTRIBUTES")
            let report = try LibraryProbe.inspect(selection: library)
            XCTAssertTrue(report.text.contains("ZASSET: 1 records"))
            XCTAssertTrue(report.text.contains("ZEXTENDEDATTRIBUTES: 2 records"))
            XCTAssertTrue(report.text.contains("ZCAMERAMODEL: 1 non-NULL values"))
            XCTAssertTrue(report.text.contains("ZLENSMODEL: column not found"))
            XCTAssertFalse(report.text.contains("Synthetic Camera"), "Reports must not expose metadata values")
            XCTAssertEqual(try writer.rows("SELECT * FROM ZEXTENDEDATTRIBUTES"), before)
        }
    }

    func testSourceConnectionRejectsWrites() throws {
        try withFixture { library, _ in
            let source = try Database(path: LibraryProbe.databaseURL(in: library).path, readOnly: true)
            XCTAssertThrowsError(try source.rows("DELETE FROM ZASSET"))
        }
    }

    func testFingerprintTracksSchemaRatherThanData() throws {
        try withFixture { library, writer in
            let first = try LibraryProbe.inspect(selection: library).fingerprint
            _ = try writer.rows("INSERT INTO ZASSET VALUES (2, 100, 100)")
            XCTAssertEqual(first, try LibraryProbe.inspect(selection: library).fingerprint)
            _ = try writer.rows("ALTER TABLE ZASSET ADD COLUMN ZDATECREATED REAL")
            XCTAssertNotEqual(first, try LibraryProbe.inspect(selection: library).fingerprint)
        }
    }

    func testMissingDatabaseFailsWithoutCreatingOne() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try LibraryProbe.inspect(selection: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testMalformedDatabaseFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("Not a database".utf8).write(to: root.appendingPathComponent("Photos.sqlite"))
        XCTAssertThrowsError(try LibraryProbe.inspect(selection: root))
    }
}
