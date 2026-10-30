import XCTest
@testable import LibraryProbe

final class LocationReviewGroupsTests: XCTestCase {
    private func photo(_ id: String, time: Double?, latitude: Double? = nil) -> PhotoRecord {
        let location = latitude.flatMap { PhotoLocation(latitude: $0, longitude: 0) }
        return PhotoRecord(id: id, filename: id, captureDate: time.map { Date(timeIntervalSinceReferenceDate: $0) }, camera: nil,
                           hasLocation: location != nil, availability: .remote, reason: nil, evidence: "",
                           location: location, assetUUID: nil, pixelWidth: 100, pixelHeight: 100)
    }
    private func item(_ id: String, time: Double?, refs: [PhotoRecord] = []) -> LocationReviewItem {
        LocationReviewItem(photo: photo(id, time: time), references: refs)
    }

    func testTimeChainCannotGrowBeyondMaximumDuration() {
        let input = (0..<7).map { item("\($0)", time: Double($0 * 600)) }
        let groups = LocationReviewGroups.make(input)
        XCTAssertEqual(groups.map { $0.photos.count }, [3, 4])
        XCTAssertEqual(Set(groups.flatMap(\.photos).map(\.id)).count, 7)
        for group in groups {
            let dates = group.photos.compactMap(\.captureDate).sorted()
            XCTAssertLessThanOrEqual(dates.last!.timeIntervalSince(dates.first!), 1_800)
        }
    }

    func testLargeGapChangedReferencesAndMissingDatesSplitGroups() {
        let a = photo("refA", time: 0, latitude: 1)
        let b = photo("refB", time: 20, latitude: 1)
        let groups = LocationReviewGroups.make([
            item("one", time: 10, refs: [a]), item("two", time: 11, refs: [b]),
            item("three", time: 1_000, refs: [b]), item("undated1", time: nil), item("undated2", time: nil)
        ])
        XCTAssertEqual(groups.count, 5)
        XCTAssertTrue(groups.allSatisfy { $0.photos.count == 1 })
    }

    func testGroupsCappedAtThirtyPhotosAndIDsAreStableAcrossInputOrder() {
        let input = (0..<65).map { item("\($0)", time: Double($0)) }
        let groups = LocationReviewGroups.make(input)
        XCTAssertEqual(groups.map { $0.photos.count }, [5, 30, 30])
        XCTAssertEqual(groups.map(\.id), LocationReviewGroups.make(input.reversed()).map(\.id))
        XCTAssertEqual(Set(groups.map(\.id)).count, 3)
    }

    func testEvidenceQueuesSeparateAgreementOneSidedConflictAndNone() {
        let a = photo("before", time: 0, latitude: 1)
        let near = photo("after", time: 200, latitude: 1.001)
        let far = photo("after-far", time: 200, latitude: 2)
        XCTAssertEqual(LocationReviewGroup(items: [item("a", time: 100, refs: [a, near])]).evidence, .matching)
        XCTAssertEqual(LocationReviewGroup(items: [item("b", time: 100, refs: [a])]).evidence, .oneSided)
        XCTAssertEqual(LocationReviewGroup(items: [item("c", time: 100, refs: [a, far])]).evidence, .conflicting)
        XCTAssertEqual(LocationReviewGroup(items: [item("d", time: nil)]).evidence, .none)
    }

    func testProgressRetainsSkipsSelectionsSplitsAndResumeState() throws {
        var progress = LocationBatchProgress()
        progress.skipped = ["skipped-photo"]
        progress.deselected = ["exception"]
        progress.splitPhotos = ["split-photo"]
        progress.lastGroupID = "last-group"
        progress.queue = .oneSided
        progress.isPaused = true
        progress.reviewedGroups = 4
        progress.updatedPhotos = 38
        let restored = try JSONDecoder().decode(LocationBatchProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(restored.skipped, progress.skipped)
        XCTAssertEqual(restored.deselected, progress.deselected)
        XCTAssertEqual(restored.splitPhotos, progress.splitPhotos)
        XCTAssertEqual(restored.lastGroupID, "last-group")
        XCTAssertEqual(restored.queue, .oneSided)
        XCTAssertTrue(restored.isPaused)
        XCTAssertEqual(restored.reviewedGroups, 4)
        XCTAssertEqual(restored.updatedPhotos, 38)
    }
}
