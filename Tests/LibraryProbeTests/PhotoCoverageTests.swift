import XCTest
@testable import LibraryProbe

final class PhotoCoverageTests: XCTestCase {
    func fixture(_ body: (Database, [String: [String]]) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try Database(path: root.appendingPathComponent("test.sqlite").path, readOnly: false)
        _ = try db.rows("CREATE TABLE ZASSET (Z_PK INTEGER PRIMARY KEY, ZKIND INTEGER, ZTRASHEDSTATE INTEGER, ZDIRECTORY TEXT, ZFILENAME TEXT, ZWIDTH INTEGER, ZHEIGHT INTEGER, ZLATITUDE REAL, ZLONGITUDE REAL, ZDATECREATED REAL)")
        _ = try db.rows("CREATE TABLE ZEXTENDEDATTRIBUTES (ZASSET INTEGER, ZCAMERAMAKE TEXT, ZCAMERAMODEL TEXT, ZLENSMODEL TEXT, ZAPERTURE REAL, ZSHUTTERSPEED REAL, ZFOCALLENGTH REAL, ZISO INTEGER)")
        _ = try db.rows("CREATE TABLE ZADDITIONALASSETATTRIBUTES (ZASSET INTEGER, ZORIGINALSTABLEHASH TEXT, ZORIGINALWIDTH INTEGER, ZORIGINALHEIGHT INTEGER)")
        _ = try db.rows("CREATE TABLE ZINTERNALRESOURCE (ZASSET INTEGER, ZFINGERPRINT TEXT, ZLOCALAVAILABILITY INTEGER, ZREMOTEAVAILABILITY INTEGER)")
        for id in 1...7 {
            _ = try db.rows("INSERT INTO ZASSET VALUES (\(id), \(id == 6 ? 1 : 0), \(id == 7 ? 1 : 0), 'A', '\(id).jpg', 6000, 4000, -180, -180, 123)")
            _ = try db.rows("INSERT INTO ZADDITIONALASSETATTRIBUTES VALUES (\(id), 'hash\(id)', 6000, 4000)")
        }
        _ = try db.rows("INSERT INTO ZEXTENDEDATTRIBUTES VALUES (1,'Apple','Phone','Wide',1.8,0.01,6.0,100), (2,' ','Camera','',0,0,-1,NULL), (6,'Video','Video','Lens',2,0.1,20,100), (7,'Trash','Trash','Lens',2,0.1,20,100)")
        _ = try db.rows("INSERT INTO ZINTERNALRESOURCE VALUES (1,'hash1',-1,1), (1,'preview',1,1), (2,'hash2',1,1), (3,'hash3',0,1), (4,'hash4',1,1), (5,'hash5',-1,-1)")
        let tables = ["ZASSET", "ZEXTENDEDATTRIBUTES", "ZADDITIONALASSETATTRIBUTES", "ZINTERNALRESOURCE"]
        var schema: [String: [String]] = [:]
        for table in tables { schema[table] = try db.rows("PRAGMA table_info(\(table))").compactMap { $0[1] } }
        try body(db, schema)
    }

    func testCoverageIsPerPhotoAndUsesOriginalNotPreview() throws {
        try fixture { db, schema in
            let lines = try PhotoCoverage.analyze(db: db, schema: schema, library: URL(fileURLWithPath: "/unused")) { _, name in
                name == "2.jpg" ? .present : .absent
            }
            let report = lines.joined(separator: "\n")
            XCTAssertTrue(report.contains("Photo assets: 5; without an extended-metadata record: 3."))
            XCTAssertTrue(report.contains("Original absent; DB reports remote available: 1 photos"))
            XCTAssertTrue(report.contains("Original present (DB and file agree): 1 photos"))
            XCTAssertTrue(report.contains("Unknown or conflicting availability: 3 photos"))
            XCTAssertTrue(report.contains("Aperture: 1/1 (100.0%)"))
            XCTAssertTrue(report.contains("Aperture: 0/1 (0.0%)"))
            XCTAssertTrue(report.contains("Valid location coordinates: 0/1 (0.0%)"))
        }
    }

    func testConflictingOriginalResourcesRemainUnknown() throws {
        try fixture { db, schema in
            _ = try db.rows("INSERT INTO ZINTERNALRESOURCE VALUES (1,'hash1',1,1)")
            let report = try PhotoCoverage.analyze(db: db, schema: schema, library: URL(fileURLWithPath: "/unused"), checkPresence: { _, _ in .absent }).joined(separator: "\n")
            XCTAssertTrue(report.contains("Original absent; DB reports remote available: 0 photos"))
            XCTAssertTrue(report.contains("Unknown or conflicting availability: 5 photos"))
        }
    }

    func testDuplicateMetadataStopsAnalysisInsteadOfInflatingCounts() throws {
        try fixture { db, schema in
            _ = try db.rows("INSERT INTO ZEXTENDEDATTRIBUTES (ZASSET) VALUES (1)")
            let report = try PhotoCoverage.analyze(db: db, schema: schema, library: URL(fileURLWithPath: "/unused")).joined()
            XCTAssertTrue(report.contains("stopped: duplicate active-photo relationships"))
        }
    }

    func testMissingRequiredSchemaIsReported() throws {
        try fixture { db, _ in
            let report = try PhotoCoverage.analyze(db: db, schema: [:], library: URL(fileURLWithPath: "/unused")).joined()
            XCTAssertTrue(report.contains("required columns missing"))
        }
    }

    func testFileChecksDistinguishAbsentAndUnsafePaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("originals/A")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: directory.appendingPathComponent("fixture.jpg"))
        XCTAssertEqual(PhotoCoverage.presence(library: root, directory: "A", filename: "fixture.jpg"), .present)
        XCTAssertEqual(PhotoCoverage.presence(library: root, directory: "A", filename: "missing.jpg"), .absent)
        XCTAssertEqual(PhotoCoverage.presence(library: root, directory: "../outside", filename: "fixture.jpg"), .unknown)
        XCTAssertEqual(PhotoCoverage.presence(library: root, directory: "/external", filename: "fixture.jpg"), .unknown)
    }
}
