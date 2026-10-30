import Foundation

public struct PhotoLocation: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }
    public func distance(to other: Self) -> Double {
        let radians = Double.pi / 180
        let a = pow(sin((other.latitude - latitude) * radians / 2), 2)
            + cos(latitude * radians) * cos(other.latitude * radians) * pow(sin((other.longitude - longitude) * radians / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, a))))
    }
}

public struct LocationReviewItem: Identifiable, Sendable {
    public var id: String { photo.id }
    public let photo: PhotoRecord
    public let references: [PhotoRecord]
    public var conflictingLocations: Bool {
        guard references.count == 2, let a = references[0].location, let b = references[1].location else { return false }
        return a.distance(to: b) > 1_000
    }
}

public enum LocationReview {
    /// Nearest located photo on each side, within the chosen elapsed-time window.
    /// Time proximity is evidence to review, never proof of a shared location.
    public static func items(in photos: [PhotoRecord], window: TimeInterval = 3_600) -> [LocationReviewItem] {
        let main = photos.filter { $0.availability != .shared }
        let anchors = main.filter { $0.location != nil && $0.captureDate != nil }
            .sorted { $0.captureDate! < $1.captureDate! }
        return main.filter { !$0.hasLocation }.map { photo in
            guard let date = photo.captureDate else { return LocationReviewItem(photo: photo, references: []) }
            var low = 0, high = anchors.count
            while low < high {
                let mid = (low + high) / 2
                if anchors[mid].captureDate! < date { low = mid + 1 } else { high = mid }
            }
            let refs = [low - 1, low].filter { anchors.indices.contains($0) }.map { anchors[$0] }
                .filter { abs($0.captureDate!.timeIntervalSince(date)) <= max(0, window) }
            return LocationReviewItem(photo: photo, references: refs)
        }.sorted { ($0.photo.captureDate ?? .distantPast) > ($1.photo.captureDate ?? .distantPast) }
    }
}
