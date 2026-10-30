import XCTest
@testable import LibraryProbe

final class LocationReviewTests: XCTestCase {
    private func photo(_ id: String, _ seconds: Double?, latitude: Double? = nil,
                       longitude: Double = 0, shared: Bool = false) -> PhotoRecord {
        let location = latitude.flatMap { PhotoLocation(latitude: $0, longitude: longitude) }
        return PhotoRecord(id: id, filename: id, captureDate: seconds.map { Date(timeIntervalSinceReferenceDate: $0) },
                           camera: nil, hasLocation: location != nil, availability: shared ? .shared : .remote,
                           reason: nil, evidence: "", location: location, assetUUID: nil, pixelWidth: nil, pixelHeight: nil)
    }

    func testNearestReferenceOnEachSideAndInclusiveWindow() throws {
        let result = LocationReview.items(in: [photo("older", 0, latitude: 1), photo("before", 100, latitude: 1),
                                              photo("target", 200), photo("after", 300, latitude: 1),
                                              photo("later", 400, latitude: 1)], window: 100)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].references.map(\.id), ["before", "after"])
        XCTAssertFalse(result[0].conflictingLocations)
        XCTAssertTrue(LocationReview.items(in: [photo("ref", 0, latitude: 1), photo("target", 101)], window: 100)[0].references.isEmpty)
    }

    func testMissingDatesAndSharedCopiesCannotSupplyEvidence() throws {
        let result = LocationReview.items(in: [photo("missing-date", nil), photo("target", 100),
                                              photo("shared-reference", 100, latitude: 1, shared: true),
                                              photo("undated-reference", nil, latitude: 1),
                                              photo("shared-target", 100, shared: true)])
        XCTAssertEqual(Set(result.map(\.id)), ["missing-date", "target"])
        XCTAssertTrue(result.allSatisfy { $0.references.isEmpty })
    }

    func testOneSidedAndConflictingReferencesRemainReviewable() throws {
        let target = photo("target", 100)
        let before = photo("before", 0, latitude: 1)
        let after = photo("after", 200, latitude: 2)
        XCTAssertEqual(LocationReview.items(in: [target, before])[0].references.map(\.id), ["before"])
        XCTAssertTrue(LocationReview.items(in: [target, before, after])[0].conflictingLocations)
        XCTAssertEqual(LocationReview.items(in: [target, photo("same-time", 100, latitude: 1)], window: 0)[0].references.count, 1)
    }

    func testCoordinateValidationAndDistance() throws {
        XCTAssertNil(PhotoLocation(latitude: -180, longitude: -180))
        XCTAssertNil(PhotoLocation(latitude: .nan, longitude: 0))
        let origin = try XCTUnwrap(PhotoLocation(latitude: 0, longitude: 0))
        XCTAssertEqual(origin.distance(to: origin), 0)
        XCTAssertEqual(origin.distance(to: try XCTUnwrap(PhotoLocation(latitude: 0, longitude: 1))), 111_195, accuracy: 10)
    }
}
