import Foundation

public enum OriginalAvailability: String, CaseIterable, Codable, Sendable {
    case local, remote, shared, review

    public var title: String {
        switch self {
        case .local: "Original on this Mac"
        case .remote: "Original absent, remote reported"
        case .shared: "Shared Album copies"
        case .review: "Availability to review"
        }
    }
}

public enum ReviewReason: String, CaseIterable, Codable, Sendable, Identifiable {
    case unsupportedPath, inaccessibleFile, missingFingerprint, noMatchingResource
    case incompleteAvailability, conflictingResources, unrecognizedState
    case fileAbsentButReportedLocal, filePresentButReportedAbsent, remoteNotConfirmed

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .unsupportedPath: "Alternative or unrecognized original path"
        case .inaccessibleFile: "File presence could not be checked"
        case .missingFingerprint: "Original reference unavailable"
        case .noMatchingResource: "No matching original resource"
        case .incompleteAvailability: "Availability information incomplete"
        case .conflictingResources: "Original resources disagree"
        case .unrecognizedState: "Availability state not yet understood"
        case .fileAbsentButReportedLocal: "Reported local, file not found"
        case .filePresentButReportedAbsent: "File present, reported unavailable"
        case .remoteNotConfirmed: "Remote availability not confirmed"
        }
    }
    public var explanation: String {
        switch self {
        case .unsupportedPath: "The original may be referenced outside the library or stored in another Photos layout. This version only checks managed originals."
        case .inaccessibleFile: "The file check was inconclusive. Restricted access or an unexpected file type can cause this; it does not prove the original is missing."
        case .missingFingerprint: "The information used to link this photo to its original resource is missing. We need another way to determine where its original is stored; this does not mean the photo is lost."
        case .noMatchingResource: "No resource matched both the photo asset and its original fingerprint. Alternative resource relationships need investigation."
        case .incompleteAvailability: "Some matching resource records have no availability value. They remain unclassified."
        case .conflictingResources: "Multiple resources matching this original report different availability states. We do not choose one arbitrarily."
        case .unrecognizedState: "Photos uses an availability value this adapter does not yet interpret. This is a compatibility question, not evidence of damage."
        case .fileAbsentButReportedLocal: "Photos reports the original as local, but the managed file was not found at scan time. Sync timing or another storage layout may explain this."
        case .filePresentButReportedAbsent: "A managed file exists, but Photos reports its original as unavailable locally. It may be a placeholder or a database timing difference."
        case .remoteNotConfirmed: "The managed original was not found and local availability is negative, but all matching records did not confirm remote availability."
        }
    }
}

public struct PhotoRecord: Identifiable, Sendable {
    public let id: String
    public let filename: String
    public let captureDate: Date?
    public let camera: String?
    public let hasLocation: Bool
    public let availability: OriginalAvailability
    public let reason: ReviewReason?
    public let evidence: String
    public var location: PhotoLocation? = nil
    public let assetUUID: String?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
}

public enum PreviewIdentity {
    // PhotoKit identifiers are opaque. Recognize only the observed UUID form,
    // retain the full fetched identifier, and fail closed if this format changes.
    public static func uuidComponent(of identifier: String) -> String? {
        guard let component = identifier.split(separator: "/").first,
              let uuid = UUID(uuidString: String(component)) else { return nil }
        return uuid.uuidString
    }

    public static func matches(_ photo: PhotoRecord, identifier: String, date: Date?, width: Int, height: Int) -> Bool {
        guard let sourceUUID = photo.assetUUID.flatMap(UUID.init(uuidString:)),
              uuidComponent(of: identifier) == sourceUUID.uuidString,
              let sourceDate = photo.captureDate, let date,
              abs(sourceDate.timeIntervalSince(date)) < 2,
              let sourceWidth = photo.pixelWidth, let sourceHeight = photo.pixelHeight,
              sourceWidth > 0, sourceHeight > 0,
              sourceWidth == width, sourceHeight == height else { return false }
        return true
    }
}

public struct LibraryOverview: Sendable {
    public let photos: [PhotoRecord]
    public let excludedSharedPhotoCount: Int
    public let excludedSharedVideoCount: Int
    public let videoCount: Int
    public let scanDate: Date
    public let fingerprint: String

    public var locatedCount: Int { photos.lazy.filter(\.hasLocation).count }
    public var firstDate: Date? { photos.compactMap(\.captureDate).min() }
    public var lastDate: Date? { photos.compactMap(\.captureDate).max() }
    public func count(_ status: OriginalAvailability) -> Int { photos.lazy.filter { $0.availability == status }.count }
    public func count(_ reason: ReviewReason) -> Int { photos.lazy.filter { $0.reason == reason }.count }

    // Only aggregates are written to disk for diagnostics. Per-photo rows stay in memory.
    public func summaryJSON() throws -> Data {
        struct Summary: Encodable {
            let generated: Date
            let fingerprint: String
            let photos: Int
            let excludedSharedPhotoCount: Int
            let excludedSharedVideoCount: Int
            let videos: Int
            let locatedPhotos: Int
            let availability: [String: Int]
            let reviewReasons: [String: Int]
        }
        let summary = Summary(generated: scanDate, fingerprint: fingerprint, photos: photos.count,
                              excludedSharedPhotoCount: excludedSharedPhotoCount,
                              excludedSharedVideoCount: excludedSharedVideoCount,
                              videos: videoCount, locatedPhotos: locatedCount,
                              availability: Dictionary(uniqueKeysWithValues: OriginalAvailability.allCases.map { ($0.rawValue, count($0)) }),
                              reviewReasons: Dictionary(uniqueKeysWithValues: ReviewReason.allCases.map { ($0.rawValue, count($0)) }))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(summary)
    }
}
