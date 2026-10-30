import SwiftUI
import MapKit

struct LocationReviewScreen: View {
    @ObservedObject var model: LibraryModel
    let overview: LibraryOverview
    @State private var window = 3_600
    @State private var category = 2
    @State private var items: [LocationReviewItem] = []
    @State private var selected: String?
    @State private var skipped = Set<String>()
    @State private var updated = Set<String>()
    @State private var pending: LocationProposal?
    @State private var message: String?
    @State private var working = false
    @State private var calculating = true
    private var visible: [LocationReviewItem] {
        items.filter { !updated.contains($0.id) && (category == 1 ? $0.references.isEmpty : !$0.references.isEmpty) }
    }
    private var current: LocationReviewItem? { visible.first { $0.id == selected } }
    private struct LocationProposal: Identifiable {
        let id = UUID()
        let photo: PhotoRecord
        let reference: PhotoRecord
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Find a location from nearby photos").font(.title2.bold())
            Text("Only main-library photos without a valid location are included. Capture times can be wrong or belong to different cameras; every suggestion needs your review.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Picker("Look within", selection: $window) {
                    Text("15 minutes").tag(900)
                    Text("1 hour").tag(3_600)
                    Text("3 hours").tag(10_800)
                }.frame(width: 240)
                Picker("Category", selection: $category) {
                    Text("1 · No nearby references (\(items.filter { $0.references.isEmpty && !updated.contains($0.id) }.count))").tag(1)
                    Text("2 · With nearby references (\(items.filter { !$0.references.isEmpty && !updated.contains($0.id) }.count))").tag(2)
                }
                if calculating { ProgressView().controlSize(.small) }
            }.disabled(working)
            PreviewConnectionBar(store: model.previews, overview: overview)
            if let message { Text(message).font(.callout).textSelection(.enabled) }
            HSplitView {
                List(selection: $selected) {
                    ForEach(visible) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.photo.filename).lineLimit(1)
                            Text(item.photo.captureDate?.formatted(date: .abbreviated, time: .shortened) ?? "No capture date")
                                .font(.caption).foregroundStyle(.secondary)
                            if updated.contains(item.id) { Text("Location updated").font(.caption) }
                            else if skipped.contains(item.id) { Text("Skipped · unchanged").font(.caption).foregroundStyle(.secondary) }
                        }.tag(item.id).padding(.vertical, 4)
                    }
                }.frame(minWidth: 220, idealWidth: 270, maxWidth: 320).disabled(working)
                ScrollView {
                    if let item = current {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Photo without a location").font(.headline)
                            preview(item.photo).frame(height: 240)
                            if item.references.isEmpty {
                                Text(item.photo.captureDate == nil
                                     ? "This photo has no capture date, so nearby photos cannot be found."
                                     : "No located photos were found within the selected time window. Try a wider window, or leave this photo for manual review.")
                            } else {
                                Text("Was this taken at the same location as one of these photos?").font(.headline)
                                if item.conflictingLocations {
                                    Label("The reference locations are more than 1 km apart. They may show travel between different places.", systemImage: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                }
                                ForEach(item.references) { reference in
                                    VStack(alignment: .leading, spacing: 10) {
                                        preview(reference).frame(height: 200)
                                        if let date = reference.captureDate, let targetDate = item.photo.captureDate {
                                            let minutes = abs(date.timeIntervalSince(targetDate)) / 60
                                            Text("\(minutes.formatted(.number.precision(.fractionLength(1)))) minutes \(date < targetDate ? "before" : "after") this photo")
                                                .font(.callout)
                                        }
                                        if let location = reference.location {
                                            Map(initialPosition: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude), latitudinalMeters: 2_000, longitudinalMeters: 2_000))) {
                                                Marker("Reference location", coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))
                                            }.frame(height: 160).id(reference.id)
                                            Text("\(location.latitude, specifier: "%.6f"), \(location.longitude, specifier: "%.6f")").font(.caption).textSelection(.enabled)
                                        }
                                        Button("Yes — propose this location") {
                                            pending = LocationProposal(photo: item.photo, reference: reference)
                                        }.buttonStyle(.borderedProminent).disabled(working || skipped.contains(item.id))
                                    }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                                }
                                Button("No — skip this photo") {
                                    skipped.insert(item.id)
                                    message = "Skipped. No location was changed. Skips are kept for this review session."
                                    selected = visible.first { !skipped.contains($0.id) }?.id
                                }.disabled(working)
                                if skipped.contains(item.id) {
                                    Button("Review again") { skipped.remove(item.id) }.disabled(working)
                                }
                            }
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ContentUnavailableView("Choose a photo to review", systemImage: "mappin.and.ellipse", description: Text(visible.isEmpty ? "No photos in this category for the selected time window." : "Select a photo from the list to see it alongside nearby references."))
                    }
                }.frame(minWidth: 480)
            }
        }.padding(20)
        .task(id: "\(overview.scanDate)-\(window)") {
            calculating = true
            let photos = overview.photos
            let interval = TimeInterval(window)
            let result = await Task.detached { LocationReview.items(in: photos, window: interval) }.value
            guard !Task.isCancelled else { return }
            items = result
            calculating = false
            selected = nil
        }
        .task(id: overview.scanDate) { await model.previews.prepare(overview) }
        .onChange(of: category) { selected = nil }
        .sheet(item: $pending) { proposal in
            VStack(alignment: .leading, spacing: 18) {
                Text("Apply this location in Photos?").font(.title2.bold())
                HStack {
                    preview(proposal.photo).frame(width: 250, height: 190)
                    preview(proposal.reference).frame(width: 250, height: 190)
                }
                Text("Copy the location from \(proposal.reference.filename) to \(proposal.photo.filename)?")
                Text("This changes one photo in your System Photo Library through Photos and may sync to iCloud. Confirm that the previews show the correct photos. The library database stays read-only.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { pending = nil }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Apply location to this photo") {
                        pending = nil
                        working = true
                        message = "Updating location through Photos…"
                        Task {
                            do {
                                try await model.previews.applyLocation(to: proposal.photo, from: proposal.reference)
                                updated.insert(proposal.photo.id)
                                selected = nil
                                message = "Location updated in Photos. Refresh the library to update the overview."
                            } catch { message = "Location was not applied: \(error.localizedDescription)" }
                            working = false
                        }
                    }.buttonStyle(.borderedProminent)
                }
            }.padding(24).frame(width: 570)
        }
    }

    private func preview(_ photo: PhotoRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PhotoPreview(store: model.previews, photo: photo).clipShape(RoundedRectangle(cornerRadius: 8))
            Text(photo.filename).font(.caption).lineLimit(1)
            Text(photo.captureDate?.formatted(date: .abbreviated, time: .shortened) ?? "No capture date").font(.caption).foregroundStyle(.secondary)
        }
    }
}
