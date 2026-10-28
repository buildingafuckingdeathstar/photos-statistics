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
        XCTAssertEqual(PhotoCoverage.presence(library: root, directory: "../outside", filename: "fixture.jpg"), .unsupportedPath)
        XCTAssertEqual(PhotoCoverage.presence(library: root, directory: "/external", filename: "fixture.jpg"), .unsupportedPath)
    }

    func testStructuredOverviewAccountsForEveryPhotoAndKeepsSummaryAggregateOnly() throws {
        try fixture { db, schema in
            let result = try PhotoCoverage.inspect(db: db, schema: schema, library: URL(fileURLWithPath: "/unused")) { _, name in
                name == "2.jpg" ? .present : .absent
            }
            let overview = try XCTUnwrap(result.overview)
            XCTAssertEqual(overview.photos.count, 5)
            XCTAssertEqual(overview.videoCount, 1)
            XCTAssertEqual(Set(overview.photos.map(\.id)).count, 5)
            XCTAssertEqual(overview.photos.first { $0.id == "1" }?.camera, "Phone")
            XCTAssertEqual(overview.photos.first { $0.id == "3" }?.reason, .unrecognizedState)
            XCTAssertEqual(overview.photos.first { $0.id == "4" }?.reason, .fileAbsentButReportedLocal)
            XCTAssertEqual(overview.photos.first { $0.id == "5" }?.reason, .remoteNotConfirmed)
            XCTAssertEqual(ReviewReason.allCases.reduce(0) { $0 + overview.count($1) }, overview.count(.review))
            XCTAssertEqual(OriginalAvailability.allCases.reduce(0) { $0 + overview.count($1) }, 5)
            let json = String(decoding: try overview.summaryJSON(), as: UTF8.self)
            XCTAssertFalse(json.contains("1.jpg"))
            XCTAssertFalse(json.contains("Phone"))
            XCTAssertTrue(json.contains("reviewReasons"))
        }
    }

    func testDiagnosticReasonsSeparateMissingRelationshipsAndFileAccess() {
        func reason(_ presence: PhotoCoverage.Presence = .absent, hash: String? = "hash", count: String? = "1",
                    localCount: String? = "1", low: String? = "-1", high: String? = "-1",
                    remoteCount: String? = "1", remoteLow: String? = "1", remoteHigh: String? = "1") -> ReviewReason? {
            PhotoCoverage.classify(presence: presence, fingerprint: hash, resourceCount: count,
                                   localCount: localCount, localMin: low, localMax: high,
                                   remoteCount: remoteCount, remoteMin: remoteLow, remoteMax: remoteHigh).1
        }
        XCTAssertEqual(reason(.unsupportedPath), .unsupportedPath)
        XCTAssertEqual(reason(.inaccessible), .inaccessibleFile)
        XCTAssertEqual(reason(hash: nil), .missingFingerprint)
        XCTAssertEqual(reason(count: nil), .noMatchingResource)
        XCTAssertEqual(reason(localCount: "0", low: nil, high: nil), .incompleteAvailability)
        XCTAssertEqual(reason(low: "-1", high: "1"), .conflictingResources)
        XCTAssertEqual(reason(low: "0", high: "0"), .unrecognizedState)
        XCTAssertEqual(reason(low: "1", high: "1"), .fileAbsentButReportedLocal)
        XCTAssertEqual(reason(.present), .filePresentButReportedAbsent)
        XCTAssertEqual(reason(remoteCount: "0"), .incompleteAvailability)
        XCTAssertEqual(reason(remoteLow: "-1", remoteHigh: "1"), .conflictingResources)
        XCTAssertEqual(reason(remoteLow: "-1", remoteHigh: "-1"), .remoteNotConfirmed)
        XCTAssertNil(reason())
    }

    func testOriginalDisplayNameDoesNotChangeManagedFileLookup() throws {
        try fixture { db, schema in
            _ = try db.rows("ALTER TABLE ZADDITIONALASSETATTRIBUTES ADD COLUMN ZORIGINALFILENAME TEXT")
            _ = try db.rows("UPDATE ZADDITIONALASSETATTRIBUTES SET ZORIGINALFILENAME='IMG_private_fixture.HEIC' WHERE ZASSET=1")
            var updatedSchema = schema
            updatedSchema["ZADDITIONALASSETATTRIBUTES"]?.append("ZORIGINALFILENAME")
            let result = try PhotoCoverage.inspect(db: db, schema: updatedSchema, library: URL(fileURLWithPath: "/unused")) { _, name in
                XCTAssertFalse(name == "IMG_private_fixture.HEIC", "Presence checks must use the managed filename")
                return .absent
            }
            let photo = try XCTUnwrap(result.overview?.photos.first { $0.id == "1" })
            XCTAssertEqual(photo.filename, "IMG_private_fixture.HEIC")
            XCTAssertEqual(photo.availability, .remote)
            XCTAssertEqual(photo.captureDate, Date(timeIntervalSinceReferenceDate: 123))
            XCTAssertFalse(String(decoding: try XCTUnwrap(result.overview).summaryJSON(), as: UTF8.self).contains("IMG_private_fixture"))
        }
    }

    func testUniqueDirectOriginalFallbackDoesNotGuessAmbiguousOrDerivativeResources() throws {
        try fixture { db, schema in
            _ = try db.rows("ALTER TABLE ZINTERNALRESOURCE ADD COLUMN ZDATASTORESUBTYPE INTEGER")
            _ = try db.rows("ALTER TABLE ZINTERNALRESOURCE ADD COLUMN ZRESOURCETYPE INTEGER")
            _ = try db.rows("UPDATE ZADDITIONALASSETATTRIBUTES SET ZORIGINALSTABLEHASH=NULL WHERE ZASSET IN (1,2,3,4)")
            _ = try db.rows("UPDATE ZADDITIONALASSETATTRIBUTES SET ZORIGINALSTABLEHASH='' WHERE ZASSET=1")
            _ = try db.rows("UPDATE ZINTERNALRESOURCE SET ZDATASTORESUBTYPE=1,ZRESOURCETYPE=0 WHERE ZFINGERPRINT IN ('hash1','hash2','hash3','hash4')")
            // A preview must not make the original ambiguous.
            _ = try db.rows("UPDATE ZINTERNALRESOURCE SET ZDATASTORESUBTYPE=4,ZRESOURCETYPE=0 WHERE ZFINGERPRINT='preview'")
            _ = try db.rows("INSERT INTO ZINTERNALRESOURCE VALUES (1,'',1,1,4,0)")
            // Two original candidates must remain unresolved.
            _ = try db.rows("INSERT INTO ZINTERNALRESOURCE VALUES (2,'another',1,1,1,0)")
            var updated = schema
            updated["ZINTERNALRESOURCE"]! += ["ZDATASTORESUBTYPE", "ZRESOURCETYPE"]
            let result = try PhotoCoverage.inspect(db: db, schema: updated, library: URL(fileURLWithPath: "/unused"), checkPresence: { _, _ in .absent })
            let photos = try XCTUnwrap(result.overview).photos
            XCTAssertEqual(photos.first { $0.id == "1" }?.availability, .remote)
            XCTAssertEqual(photos.first { $0.id == "2" }?.reason, .missingFingerprint)
            XCTAssertEqual(photos.first { $0.id == "3" }?.reason, .unrecognizedState)
            XCTAssertEqual(photos.first { $0.id == "4" }?.reason, .fileAbsentButReportedLocal)
            XCTAssertTrue(photos.first { $0.id == "1" }?.evidence.contains("Unique directly linked original") == true)
        }
    }

    func testSharedAlbumsExcludedFromMainLibraryButLibraryScopeRetained() throws {
        try fixture { db, schema in
            _ = try db.rows("ALTER TABLE ZASSET ADD COLUMN ZCOLLECTIONSHARE INTEGER")
            _ = try db.rows("CREATE TABLE ZSHARE (Z_PK INTEGER PRIMARY KEY,Z_ENT INTEGER)")
            _ = try db.rows("CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER,Z_NAME TEXT)")
            _ = try db.rows("INSERT INTO Z_PRIMARYKEY VALUES (11,'CollectionShare'),(12,'LibraryScope')")
            _ = try db.rows("INSERT INTO ZSHARE VALUES (101,11),(102,12)")
            _ = try db.rows("UPDATE ZASSET SET ZCOLLECTIONSHARE=101 WHERE Z_PK IN (1,6)")
            _ = try db.rows("UPDATE ZASSET SET ZCOLLECTIONSHARE=102 WHERE Z_PK=2")
            _ = try db.rows("UPDATE ZADDITIONALASSETATTRIBUTES SET ZORIGINALSTABLEHASH=NULL WHERE ZASSET IN (1,2)")
            var updated = schema
            updated["ZASSET"]!.append("ZCOLLECTIONSHARE")
            updated["ZSHARE"] = ["Z_PK", "Z_ENT"]
            updated["Z_PRIMARYKEY"] = ["Z_ENT", "Z_NAME"]
            let result = try PhotoCoverage.inspect(db: db, schema: updated, library: URL(fileURLWithPath: "/unused"), checkPresence: { _, _ in .absent })
            let overview = try XCTUnwrap(result.overview)
            XCTAssertNil(overview.photos.first { $0.id == "1" })
            XCTAssertEqual(overview.photos.count, 4)
            XCTAssertEqual(overview.excludedSharedPhotoCount, 1)
            XCTAssertEqual(overview.excludedSharedVideoCount, 1)
            XCTAssertEqual(overview.videoCount, 0)
            XCTAssertEqual(overview.photos.first { $0.id == "2" }?.reason, .missingFingerprint)
            XCTAssertEqual(overview.count(.shared), 0)
            let summary = try XCTUnwrap(JSONSerialization.jsonObject(with: overview.summaryJSON()) as? [String: Any])
            XCTAssertEqual(summary["photos"] as? Int, 4)
            XCTAssertEqual(summary["excludedSharedPhotoCount"] as? Int, 1)
        }
    }
}
