import Foundation
import CryptoKit

public enum LocationEvidence: String, CaseIterable, Codable, Sendable {
    case matching, oneSided, conflicting, none
    public var title: String {
        switch self {
        case .matching: "Matching references"
        case .oneSided: "One-sided references"
        case .conflicting: "Conflicting references"
        case .none: "No references"
        }
    }
}

public struct LocationReviewGroup: Identifiable, Sendable {
    public let items: [LocationReviewItem]
    public let id: String
    public init(items: [LocationReviewItem]) {
        self.items = items
        let keys = items.map { $0.photo.reviewKey }.joined(separator: "|")
        id = SHA256.hash(data: Data(keys.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public var photos: [PhotoRecord] { items.map(\.photo) }
    public var references: [PhotoRecord] { items.first?.references ?? [] }
    public var evidence: LocationEvidence {
        if references.isEmpty { return .none }
        if items.contains(where: \.conflictingLocations) { return .conflicting }
        return references.count == 1 ? .oneSided : .matching
    }
}

extension PhotoRecord {
    /// Scoped to the selected library by the UI; also changes if capture metadata changes.
    public var reviewKey: String {
        "\(assetUUID ?? id):\(captureDate?.timeIntervalSinceReferenceDate.description ?? "undated"):\(pixelWidth ?? 0)x\(pixelHeight ?? 0)"
    }
}

public enum LocationReviewGroups {
    /// The UI's group-span setting controls both the overall duration and allowed
    /// gaps. Reference-search distance is a separate setting on LocationReview.
    public static func make(_ items: [LocationReviewItem], groupSpan: TimeInterval) -> [LocationReviewGroup] {
        let duration = max(0, groupSpan)
        return make(items, maximumGap: duration, maximumDuration: duration)
    }

    public static func make(_ items: [LocationReviewItem], maximumGap: TimeInterval = 900,
                            maximumDuration: TimeInterval = 1_800, maximumCount: Int = 30) -> [LocationReviewGroup] {
        let sorted = items.sorted {
            let a = $0.photo.captureDate ?? .distantPast, b = $1.photo.captureDate ?? .distantPast
            return a == b ? $0.photo.reviewKey < $1.photo.reviewKey : a < b
        }
        var groups: [LocationReviewGroup] = []
        var current: [LocationReviewItem] = []
        for item in sorted {
            let canJoin: Bool
            if let first = current.first, let last = current.last,
               let start = first.photo.captureDate, let previous = last.photo.captureDate,
               let date = item.photo.captureDate {
                canJoin = date.timeIntervalSince(previous) <= maximumGap
                    && date.timeIntervalSince(start) <= maximumDuration
                    && current.count < max(1, maximumCount)
                    // A located photo between targets changes the reference pair and splits the group.
                    && first.references.map(\.id) == item.references.map(\.id)
            } else { canJoin = false }
            if !canJoin && !current.isEmpty { groups.append(LocationReviewGroup(items: current)); current = [] }
            current.append(item)
        }
        if !current.isEmpty { groups.append(LocationReviewGroup(items: current)) }
        return groups.reversed()
    }
}

public struct LocationBatchProgress: Codable, Sendable {
    public var skipped = Set<String>()
    public var deselected = Set<String>()
    public var splitPhotos = Set<String>()
    public var queue = LocationEvidence.matching
    public var isPaused = false
    public var lastGroupID: String?
    public var reviewedGroups = 0
    public var updatedPhotos = 0
    public init() {}
}
