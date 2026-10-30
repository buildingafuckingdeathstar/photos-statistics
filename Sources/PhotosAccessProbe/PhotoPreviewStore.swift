import AppKit
import SwiftUI
@preconcurrency import Photos

@MainActor
final class PhotoPreviewStore: ObservableObject {
    enum State { case disconnected, indexing, ready, denied }
    @Published private(set) var state: State = .disconnected
    @Published private(set) var message = "Enable local previews to see matching photos from your System Photo Library."
    @Published private(set) var revision = 0
    private let manager = PHCachingImageManager()
    private let cache = NSCache<NSString, NSImage>()
    private var assets: [String: PHAsset] = [:]
    private var indexedScan: Date?
    private var generation = UUID()

    init() {
        cache.countLimit = 160
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    func prepare(_ overview: LibraryOverview) async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            if status == .denied || status == .restricted {
                state = .denied
                message = "Photos access is not available. You can allow Photos Statistics in System Settings → Privacy & Security → Photos."
            }
            return
        }
        guard indexedScan != overview.scanDate else { return }
        await index(overview)
    }

    func connect(_ overview: LibraryOverview) async {
        guard state != .indexing else { return }
        state = .indexing
        message = "Waiting for Photos permission…"
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            state = .denied
            indexedScan = nil
            message = "Photos access was not granted. You can keep using the list without previews."
            return
        }
        await prepare(overview)
    }

    private func index(_ overview: LibraryOverview) async {
        indexedScan = overview.scanDate
        let token = UUID()
        generation = token
        state = .indexing
        message = "Matching your library to Photos…"
        assets.removeAll()
        cache.removeAllObjects()
        manager.stopCachingImagesForAllAssets()
        revision += 1
        let records = Dictionary(grouping: overview.photos.compactMap { photo -> (String, PhotoRecord)? in
            guard let uuid = photo.assetUUID.flatMap(UUID.init(uuidString:)) else { return nil }
            return (uuid.uuidString, photo)
        }, by: { $0.0 })
        let options = PHFetchOptions()
        options.includeHiddenAssets = true
        options.includeAllBurstAssets = true
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
        let fetched = PHAsset.fetchAssets(with: .image, options: options)
        var candidates: [String: PHAsset] = [:]
        var ambiguous = Set<String>()
        for index in 0..<fetched.count {
            if index % 500 == 0 {
                message = "Matching photos: \(index.formatted()) of \(fetched.count.formatted())…"
                await Task.yield()
                guard generation == token else { return }
            }
            let asset = fetched.object(at: index)
            guard let uuid = PreviewIdentity.uuidComponent(of: asset.localIdentifier),
                  let matches = records[uuid], matches.count == 1,
                  PreviewIdentity.matches(matches[0].1, identifier: asset.localIdentifier,
                                          date: asset.creationDate, width: asset.pixelWidth, height: asset.pixelHeight) else { continue }
            if candidates[uuid] != nil { ambiguous.insert(uuid) }
            else { candidates[uuid] = asset }
        }
        guard generation == token else { return }
        for uuid in ambiguous { candidates.removeValue(forKey: uuid) }
        assets = candidates
        state = .ready
        revision += 1
        message = "\(assets.count.formatted()) of \(overview.photos.count.formatted()) photo records matched. Local previews only; downloads are off."
    }

    // NSImage is passed immutably between the PhotoKit callback and the main actor.
    private struct Delivery: @unchecked Sendable {
        let image: NSImage?
        let unavailable: Bool
        let cancelled: Bool
    }

    func request(_ photo: PhotoRecord, completion: @escaping @MainActor (NSImage?, String) -> Void) -> PHImageRequestID? {
        let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if state == .ready && authorization != .authorized && authorization != .limited {
            generation = UUID()
            assets.removeAll()
            cache.removeAllObjects()
            indexedScan = nil
            state = .denied
            message = "Photos access is no longer available."
            revision += 1
        }
        guard state == .ready else {
            completion(nil, state == .indexing ? "Matching photos…" : "Previews are not enabled")
            return nil
        }
        guard let uuid = photo.assetUUID.flatMap(UUID.init(uuidString:))?.uuidString,
              let asset = assets[uuid] else {
            completion(nil, "No confirmed match in the accessible System Photo Library")
            return nil
        }
        if let image = cache.object(forKey: uuid as NSString) {
            completion(image, "")
            return nil
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.version = .current
        let token = generation
        return manager.requestImage(for: asset, targetSize: CGSize(width: 480, height: 480), contentMode: .aspectFill, options: options) { [weak self] image, info in
            let result = Delivery(image: image,
                                  unavailable: (info?[PHImageResultIsInCloudKey] as? Bool == true) || info?[PHImageErrorKey] != nil,
                                  cancelled: info?[PHImageCancelledKey] as? Bool == true)
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, !result.cancelled else { return }
                if let image = result.image {
                    self.cache.setObject(image, forKey: uuid as NSString, cost: 480 * 480 * 4)
                    completion(image, "")
                } else {
                    completion(nil, result.unavailable ? "Preview is not available locally" : "No local preview returned")
                }
            }
        }
    }

    /// Uses actual fetched PhotoKit identifiers, then rechecks both assets immediately
    /// before requesting one atomic batch of metadata edits. Never opens SQLite for writing.
    func applyLocation(to photo: PhotoRecord, from reference: PhotoRecord) async throws {
        try await applyLocations(to: [photo], from: reference)
    }

    func applyLocations(to photos: [PhotoRecord], from reference: PhotoRecord) async throws {
        func failure(_ text: String) -> NSError {
            NSError(domain: "PhotosStatistics.Location", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
        }
        guard state == .ready, PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            throw failure("Full Photos access is required. Enable previews and check Photos access first.")
        }
        func fresh(_ record: PhotoRecord) throws -> PHAsset {
            guard let uuid = record.assetUUID.flatMap(UUID.init(uuidString:))?.uuidString,
                  let mapped = assets[uuid], cache.object(forKey: uuid as NSString) != nil,
                  let asset = PHAsset.fetchAssets(withLocalIdentifiers: [mapped.localIdentifier], options: nil).firstObject,
                  asset.sourceType == .typeUserLibrary,
                  PreviewIdentity.matches(record, identifier: asset.localIdentifier, date: asset.creationDate,
                                          width: asset.pixelWidth, height: asset.pixelHeight) else {
                throw failure("Every selected photo and the reference must have a confirmed main-library match and a locally available preview. Review all thumbnails, then try again.")
            }
            return asset
        }
        guard !photos.isEmpty, photos.count <= 30, Set(photos.map(\.reviewKey)).count == photos.count else {
            throw failure("Choose between 1 and 30 different photos for one batch.")
        }
        let targets = try photos.map(fresh)
        let source = try fresh(reference)
        guard Set(targets.map(\.localIdentifier)).count == targets.count,
              targets.allSatisfy({ $0.localIdentifier != source.localIdentifier && $0.location == nil && $0.canPerform(.properties) }),
              let location = source.location,
              let expected = reference.location,
              let actual = PhotoLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
              actual.distance(to: expected) < 1 else {
            throw failure("The photo or reference changed, already has a location, or cannot be edited. Refresh the library and review again.")
        }
        try await PhotoChangeTransaction.perform(assets: targets, change: { @Sendable target in
            PHAssetChangeRequest(for: target).location = location
        }, submit: { @Sendable changes, completion in
            PHPhotoLibrary.shared().performChanges(changes, completionHandler: completion)
        })
    }

    func cancel(_ request: PHImageRequestID?) {
        if let request { manager.cancelImageRequest(request) }
    }
}

struct PhotoPreview: View {
    @ObservedObject var store: PhotoPreviewStore
    let photo: PhotoRecord
    @State private var image: NSImage?
    @State private var message = "Loading preview…"
    @State private var request: PHImageRequestID?
    @State private var token = UUID()

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.45))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "photo").font(.title2)
                    Text(message).font(.caption2).multilineTextAlignment(.center).lineLimit(3)
                }.foregroundStyle(.secondary).padding(10)
            }
        }
        .clipped()
        .task(id: "\(photo.id)-\(store.revision)") {
            store.cancel(request)
            token = UUID()
            let current = token
            image = nil
            request = store.request(photo) { value, status in
                guard token == current else { return }
                if let value { image = value }
                if image == nil { message = status }
            }
        }
        .onDisappear { token = UUID(); store.cancel(request); request = nil }
    }
}
