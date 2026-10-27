import SwiftUI

struct ReviewScreen: View {
    @ObservedObject var model: LibraryModel
    let overview: LibraryOverview
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Understand uncertain availability").font(.title2.bold())
                Spacer()
                Picker("Reason", selection: $model.reviewReason) {
                    Text("All reasons").tag(ReviewReason?.none)
                    ForEach(ReviewReason.allCases.filter { overview.count($0) > 0 }) { reason in
                        Text("\(reason.title) (\(overview.count(reason).formatted()))").tag(Optional(reason))
                    }
                }.labelsHidden().frame(maxWidth: 360)
            }
            Text(model.reviewReason?.explanation ?? "These are observations to investigate, not a repair queue. Select a photo to see the evidence.")
                .font(.callout).foregroundStyle(.secondary)
            PhotoBrowser(overview: overview, status: .constant(.review), reason: model.reviewReason, previews: model.previews, allowsStatusFilter: false)
        }.padding(20)
    }
}

struct PhotoBrowser: View {
    let overview: LibraryOverview
    @Binding var status: OriginalAvailability?
    let reason: ReviewReason?
    @ObservedObject var previews: PhotoPreviewStore
    var allowsStatusFilter = true
    enum Presentation { case photos, list }
    @State private var presentation = Presentation.photos
    @State private var thumbnailSize = 160.0
    @State private var search = ""
    @State private var matches: [PhotoRecord] = []
    @State private var selectedID: String?
    @State private var limit = 500
    @State private var filtering = false
    private var filterKey: String { "\(overview.scanDate.timeIntervalSince1970)|\(status?.rawValue ?? "all")|\(reason?.rawValue ?? "all")|\(search)" }
    private var selected: PhotoRecord? { matches.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search photo name or camera", text: $search).textFieldStyle(.roundedBorder)
                if allowsStatusFilter {
                    Picker("Availability", selection: $status) {
                        Text("All originals").tag(OriginalAvailability?.none)
                        ForEach(OriginalAvailability.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }.labelsHidden().frame(maxWidth: 280)
                }
            }
            HStack(spacing: 0) {
                TabView(selection: $presentation) {
                    VStack(spacing: 12) {
                        PreviewConnectionBar(store: previews, overview: overview)
                        HStack {
                            Text("Photo size").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $thumbnailSize, in: 110...230).frame(width: 140)
                            Spacer()
                        }
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize + 45), spacing: 10)], spacing: 12) {
                                ForEach(matches) { photo in
                                    Button { selectedID = photo.id } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            PhotoPreview(store: previews, photo: photo).frame(height: thumbnailSize)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedID == photo.id ? Color.accentColor : .clear, lineWidth: 3))
                                            Text(photo.filename).font(.caption).lineLimit(1).foregroundStyle(.primary)
                                        }.padding(3)
                                    }.buttonStyle(.plain).accessibilityLabel(photo.filename)
                                }
                            }.padding(6)
                        }
                    }.padding(12).tabItem { Label("Photos", systemImage: "square.grid.3x3") }.tag(Presentation.photos)
                    Table(Array(matches.prefix(limit)), selection: $selectedID) {
                    TableColumn("Photo") { photo in Text(photo.filename).lineLimit(1) }.width(min: 140, ideal: 220)
                    TableColumn("Capture date") { photo in
                        Text(photo.captureDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")
                    }.width(110)
                    TableColumn("Camera") { photo in Text(photo.camera ?? "Unknown").lineLimit(1) }.width(min: 85, ideal: 130)
                    TableColumn("Availability") { photo in
                        Text(photo.reason?.title ?? photo.availability.title).font(.callout).foregroundStyle(.secondary)
                    }.width(min: 140, ideal: 220)
                    }.tabItem { Label("List", systemImage: "list.bullet") }.tag(Presentation.list)
                }
                if let selected {
                    Divider()
                    PhotoDetails(photo: selected, previews: previews).frame(width: 270)
                }
            }
            HStack {
                Text("\(matches.count.formatted()) photos · newest first").font(.caption).foregroundStyle(.secondary)
                if filtering { ProgressView().controlSize(.small) }
                Spacer()
                if presentation == .list && matches.count > limit {
                    Text("Showing \(min(limit, matches.count).formatted())").font(.caption).foregroundStyle(.secondary)
                    Button("Show 500 more") { limit += 500 }
                }
            }
        }
        .padding(allowsStatusFilter ? 20 : 0)
        .task(id: overview.scanDate) { await previews.prepare(overview) }
        .task(id: filterKey) {
            filtering = true
            let photos = overview.photos
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let requestedStatus = status
            let requestedReason = reason
            let result = await Task.detached(priority: .userInitiated) {
                photos.filter { photo in
                    (requestedStatus == nil || photo.availability == requestedStatus)
                    && (requestedReason == nil || photo.reason == requestedReason)
                    && (query.isEmpty || photo.filename.localizedCaseInsensitiveContains(query)
                        || photo.camera?.localizedCaseInsensitiveContains(query) == true)
                }
            }.value
            guard !Task.isCancelled else { return }
            matches = result
            selectedID = nil
            limit = 500
            filtering = false
        }
    }
}

struct PhotoDetails: View {
    let photo: PhotoRecord
    @ObservedObject var previews: PhotoPreviewStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PhotoPreview(store: previews, photo: photo).frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(photo.filename).font(.headline).textSelection(.enabled)
                LabeledContent("Camera", value: photo.camera ?? "Unknown")
                LabeledContent("Location", value: photo.hasLocation ? "Coordinates available" : "No valid coordinates")
                if let date = photo.captureDate {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Library capture date").font(.caption).foregroundStyle(.secondary)
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                        Text("Shown in this Mac's time zone").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text(photo.reason?.title ?? photo.availability.title).font(.headline)
                Text(photo.reason?.explanation ?? photo.availability.detail).font(.callout).foregroundStyle(.secondary)
                DisclosureGroup("Technical evidence") {
                    Text(photo.evidence).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                Text("Local previews only. No photos or albums have been changed.").font(.caption).foregroundStyle(.secondary)
            }.padding(18)
        }
    }
}

struct PreviewConnectionBar: View {
    @ObservedObject var store: PhotoPreviewStore
    let overview: LibraryOverview
    var body: some View {
        HStack(spacing: 12) {
            if store.state == .indexing { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 4) {
                Text(store.message).font(.callout)
                Text("Previews use your System Photo Library. Unavailable or unmatched images remain placeholders.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.state == .disconnected {
                Button("Enable local previews") { Task { await store.connect(overview) } }
                    .buttonStyle(.borderedProminent)
                    .help("macOS will ask for Photos access. This version only reads previews.")
            } else if store.state == .denied {
                Button("Check Photos access") { Task { await store.prepare(overview) } }
            }
        }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}
