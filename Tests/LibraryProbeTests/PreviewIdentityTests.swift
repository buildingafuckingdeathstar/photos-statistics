import XCTest
@testable import LibraryProbe

final class PreviewIdentityTests: XCTestCase {
    let uuid = "8D590D24-4B3F-4CB1-A8F0-244581C5BE9D"
    let date = Date(timeIntervalSinceReferenceDate: 12345)

    func photo(uuid: String? = "8D590D24-4B3F-4CB1-A8F0-244581C5BE9D", date: Date? = Date(timeIntervalSinceReferenceDate: 12345)) -> PhotoRecord {
        PhotoRecord(id: "1", filename: "same-name.jpg", captureDate: date, camera: nil, hasLocation: false,
                    availability: .local, reason: nil, evidence: "", assetUUID: uuid, pixelWidth: 6000, pixelHeight: 4000)
    }

    func testObservedIdentifierUsesActualUUIDComponent() {
        XCTAssertEqual(PreviewIdentity.uuidComponent(of: uuid.lowercased() + "/L1/001"), uuid)
        XCTAssertNil(PreviewIdentity.uuidComponent(of: "opaque-non-uuid/L0/001"))
        XCTAssertTrue(PreviewIdentity.matches(photo(), identifier: uuid + "/L1/001", date: date, width: 6000, height: 4000))
    }

    func testIdentityDateAndDimensionsMustAllAgree() {
        XCTAssertFalse(PreviewIdentity.matches(photo(), identifier: UUID().uuidString + "/L0/001", date: date, width: 6000, height: 4000))
        XCTAssertFalse(PreviewIdentity.matches(photo(), identifier: uuid + "/L0/001", date: date.addingTimeInterval(60), width: 6000, height: 4000))
        XCTAssertFalse(PreviewIdentity.matches(photo(), identifier: uuid + "/L0/001", date: date, width: 2048, height: 1365))
        XCTAssertFalse(PreviewIdentity.matches(photo(uuid: nil), identifier: uuid + "/L0/001", date: date, width: 6000, height: 4000))
        XCTAssertFalse(PreviewIdentity.matches(photo(date: nil), identifier: uuid + "/L0/001", date: date, width: 6000, height: 4000))
    }
}
