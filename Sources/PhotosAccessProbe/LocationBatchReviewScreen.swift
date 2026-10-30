import SwiftUI

struct LocationReviewScreen: View {
    @ObservedObject var model: LibraryModel
    let overview: LibraryOverview
    @AppStorage("locationReviewPresentation") private var presentation = "groups"
    var body: some View {
        VStack(spacing: 0) {
            Picker("Review", selection: $presentation) {
                Text("Review groups").tag("groups")
                Text("Individual photos").tag("individual")
            }.pickerStyle(.segmented).frame(width: 320).padding(.top, 12)
            if presentation == "groups" {
                LocationBatchReviewScreen(model: model, overview: overview).id(overview.reviewScope)
            } else {
                IndividualLocationReviewScreen(model: model, overview: overview)
            }
        }
    }
}

struct LocationBatchReviewScreen: View {
    @ObservedObject var model: LibraryModel
    let overview: LibraryOverview
    @AppStorage("locationBatchReferenceWindow") private var window = 3_600
    @State private var groups: [LocationReviewGroup] = []
    @State private var progress = LocationBatchProgress()
    @State private var selectedGroupID: String?
    @State private var referenceID: String?
    @State private var available: [LocationReviewGroup] = []
    private var applied: Set<String> { model.locationAppliedKeys }
    @State private var showSkipped = false
    @State private var calculating = true
    @State private var working = false
    @State private var message: String?
    @State private var proposal: Proposal?
    @State private var enlarged: PhotoRecord?
    @State private var restored = false
    private let columns = [GridItem(.adaptive(minimum: 115, maximum: 180), spacing: 10)]
    private var storageKey: String { "locationBatchReview.v1.\(overview.reviewScope)" }
    private var sessionFinished: Bool { progress.reviewedGroups >= 10 }
    private var reviewDisabled: Bool { working || progress.isPaused || sessionFinished }

    private struct Proposal: Identifiable {
        let id = UUID()
        let photos: [PhotoRecord]
        let reference: PhotoRecord
    }
    private var expandedGroups: [LocationReviewGroup] {
        groups.flatMap { group in
            group.photos.contains(where: { progress.splitPhotos.contains($0.reviewKey) })
                ? group.items.map { LocationReviewGroup(items: [$0]) } : [group]
        }
    }
    private func remaining(_ group: LocationReviewGroup, skipped: Bool) -> LocationReviewGroup? {
        let items = group.items.filter {
            !applied.contains($0.photo.reviewKey) && progress.skipped.contains($0.photo.reviewKey) == skipped
        }
        return items.isEmpty ? nil : items.count == group.items.count ? group : LocationReviewGroup(items: items)
    }
    private var visible: [LocationReviewGroup] {
        available.filter { $0.evidence == progress.queue }
    }
    private var current: LocationReviewGroup? { visible.first { $0.id == selectedGroupID } }
    private func checked(_ group: LocationReviewGroup) -> [PhotoRecord] {
        group.photos.filter { !progress.deselected.contains($0.reviewKey) }
    }
    private func reference(_ group: LocationReviewGroup) -> PhotoRecord? {
        group.references.first { $0.id == referenceID } ?? group.references.first
    }
    private func queueCount(_ evidence: LocationEvidence) -> Int {
        available.filter { $0.evidence == evidence }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review missing locations in groups").font(.title2.bold())
            Text("Up to 30 photos over 30 minutes, using the same nearby references. Deselect exceptions or split a group before applying a location.")
                .font(.callout).foregroundStyle(.secondary)
            sessionBar
            HStack {
                Picker("References within", selection: $window) {
                    Text("15 minutes").tag(900)
                    Text("1 hour").tag(3_600)
                    Text("3 hours").tag(10_800)
                }.frame(width: 240)
                Picker("Queue", selection: $progress.queue) {
                    ForEach(LocationEvidence.allCases, id: \.self) { queue in
                        Text("\(queue.title) (\(queueCount(queue)))").tag(queue)
                    }
                }
                Toggle("Skipped", isOn: $showSkipped).toggleStyle(.checkbox)
                if calculating { ProgressView().controlSize(.small) }
            }.disabled(working)
            PreviewConnectionBar(store: model.previews, overview: overview)
            if let message { Text(message).font(.callout).textSelection(.enabled) }
            HSplitView {
                List(selection: $selectedGroupID) {
                    ForEach(visible) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(group.photos.count) photo\(group.photos.count == 1 ? "" : "s")").font(.headline)
                            Text(timeRange(group)).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5).tag(group.id)
                    }
                }.frame(minWidth: 180, idealWidth: 220, maxWidth: 270).disabled(reviewDisabled)
                if let group = current {
                    groupReview(group).disabled(reviewDisabled)
                } else {
                    ContentUnavailableView("Choose a group", systemImage: "photo.stack", description: Text(visible.isEmpty ? "No groups in this queue. Try another queue or reference window." : "Compare the photos with located references, then apply to your selection or skip."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }.padding(20)
        .task(id: "\(overview.scanDate)-\(window)") {
            if !restored {
                if !overview.reviewScope.isEmpty, let data = UserDefaults.standard.data(forKey: storageKey),
                   let saved = try? JSONDecoder().decode(LocationBatchProgress.self, from: data) { progress = saved }
                restored = true
            }
            calculating = true
            let photos = overview.photos
            let interval = TimeInterval(window)
            let result = await Task.detached(priority: .userInitiated) {
                LocationReviewGroups.make(LocationReview.items(in: photos, window: interval))
            }.value
            guard !Task.isCancelled else { return }
            groups = result
            rebuild()
            calculating = false
            selectedGroupID = visible.first { $0.id == progress.lastGroupID }?.id ?? visible.first?.id
        }
        .task(id: overview.scanDate) { await model.previews.prepare(overview) }
        .onChange(of: selectedGroupID) {
            referenceID = nil
            progress.lastGroupID = selectedGroupID
            save()
        }
        .onChange(of: progress.queue) { selectedGroupID = visible.first?.id; save() }
        .onChange(of: showSkipped) { rebuild(); selectedGroupID = visible.first?.id }
        .onChange(of: model.locationAppliedKeys) { rebuild() }
        .sheet(item: $proposal) { confirmation($0) }
        .sheet(item: $enlarged) { photo in
            VStack(spacing: 14) {
                Text(photo.filename).font(.headline)
                PhotoPreview(store: model.previews, photo: photo).frame(width: 700, height: 480)
                Text(photo.captureDate?.formatted() ?? "No capture date").foregroundStyle(.secondary)
                Button("Done") { enlarged = nil }.keyboardShortcut(.cancelAction)
            }.padding(20)
        }
    }

    private var sessionBar: some View {
        HStack(spacing: 16) {
            ProgressView(value: Double(min(10, progress.reviewedGroups)), total: 10).frame(width: 110)
            Text("\(progress.reviewedGroups) of 10 groups reviewed · \(progress.updatedPhotos) photos updated").font(.callout)
            Spacer()
            if sessionFinished {
                Button("Start next 10 groups") {
                    progress.reviewedGroups = 0; progress.updatedPhotos = 0; progress.isPaused = false; save()
                    selectedGroupID = visible.first?.id
                }
            } else {
                Button(progress.isPaused ? "Resume review" : "Stop for now") {
                    progress.isPaused.toggle(); save()
                }
            }
        }.disabled(working)
    }

    private func groupReview(_ group: LocationReviewGroup) -> some View {
        VStack(spacing: 0) {
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("\(checked(group).count) of \(group.photos.count) selected").font(.headline)
                            Spacer()
                            Button("All") { for photo in group.photos { progress.deselected.remove(photo.reviewKey) }; save() }
                            Button("None") { progress.deselected.formUnion(group.photos.map(\.reviewKey)); save() }
                        }
                        Text("Click a checkmark to include or exclude a photo. Click its preview to enlarge it.").font(.caption).foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(group.photos) { photo in
                                VStack(alignment: .leading, spacing: 5) {
                                    Button { enlarged = photo } label: {
                                        PhotoPreview(store: model.previews, photo: photo).frame(height: 105).clipShape(RoundedRectangle(cornerRadius: 8))
                                    }.buttonStyle(.plain)
                                    Toggle(isOn: Binding(get: { !progress.deselected.contains(photo.reviewKey) }, set: { value in
                                        if value { progress.deselected.remove(photo.reviewKey) } else { progress.deselected.insert(photo.reviewKey) }; save()
                                    })) { Text(photo.filename).font(.caption).lineLimit(1) }.toggleStyle(.checkbox)
                                    Text(photo.captureDate?.formatted(date: .omitted, time: .shortened) ?? "No date").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if group.photos.count > 1 {
                            Button("Split into individual photos") {
                                progress.splitPhotos.formUnion(group.photos.map(\.reviewKey)); save(); rebuild()
                                selectedGroupID = visible.first?.id
                            }
                        }
                    }.padding(12)
                }.frame(minWidth: 230)
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.evidence.title).font(.headline)
                    Text(evidenceExplanation(group.evidence)).font(.caption).foregroundStyle(group.evidence == .conflicting ? .orange : .secondary)
                    if !group.references.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(group.references) { ref in
                                Button { referenceID = ref.id } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        PhotoPreview(store: model.previews, photo: ref).frame(height: 100).clipShape(RoundedRectangle(cornerRadius: 6))
                                        Label(ref.filename, systemImage: reference(group)?.id == ref.id ? "checkmark.circle.fill" : "circle").font(.caption).lineLimit(1)
                                        Text(ref.captureDate?.formatted(date: .abbreviated, time: .shortened) ?? "No date").font(.caption2)
                                    }.padding(6).background(reference(group)?.id == ref.id ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                                    .contextMenu { Button("Enlarge reference") { enlarged = ref } }
                            }
                        }
                        if let location = reference(group)?.location {
                            LocationMap(location: location).frame(minHeight: 120, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 8))
                            Text("\(location.latitude, specifier: "%.6f"), \(location.longitude, specifier: "%.6f") · Scroll to zoom; drag to move.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } else { Spacer() }
                }.padding(12).frame(minWidth: 270, idealWidth: 330)
            }
            Divider()
            HStack {
                if showSkipped {
                    Button("Return group to review") {
                        progress.skipped.subtract(group.photos.map(\.reviewKey)); save(); rebuild(); selectedGroupID = visible.first?.id
                    }
                } else {
                    Button("Skip group") {
                        progress.skipped.formUnion(group.photos.map(\.reviewKey)); progress.reviewedGroups += 1
                        advance()
                    }
                    Spacer()
                    if let ref = reference(group) {
                        Button("Apply to \(checked(group).count) selected photos…") {
                            proposal = Proposal(photos: checked(group), reference: ref)
                        }.buttonStyle(.borderedProminent).disabled(checked(group).isEmpty)
                    }
                }
            }.padding(12)
        }.frame(minWidth: 530)
    }

    private func confirmation(_ proposed: Proposal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Apply one location to \(proposed.photos.count) photos?").font(.title2.bold())
            Text("Reference: \(proposed.reference.filename)")
            PhotoPreview(store: model.previews, photo: proposed.reference).frame(height: 150)
            if let location = proposed.reference.location {
                Text("\(location.latitude, specifier: "%.6f"), \(location.longitude, specifier: "%.6f")").font(.callout)
            }
            ScrollView {
                LazyVGrid(columns: columns) {
                    ForEach(proposed.photos) { photo in
                        VStack {
                            PhotoPreview(store: model.previews, photo: photo).frame(height: 90)
                            Text(photo.filename).font(.caption).lineLimit(1)
                        }
                    }
                }
            }.frame(height: 200)
            Text("Confirm that every selected photo belongs at this location. Photos will update your System Photo Library and may sync to iCloud. If any photo fails validation, the whole batch is stopped. The database stays read-only.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { proposal = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply location to \(proposed.photos.count) photos") {
                    proposal = nil; working = true; message = "Validating and updating the selected photos…"
                    Task {
                        do {
                            try await model.previews.applyLocations(to: proposed.photos, from: proposed.reference)
                            model.locationAppliedKeys.formUnion(proposed.photos.map(\.reviewKey))
                            progress.updatedPhotos += proposed.photos.count
                            progress.reviewedGroups += 1
                            message = "Updated \(proposed.photos.count) photos. Refresh the library to update overview counts. Deselected photos remain in the queue."
                            advance()
                        } catch { message = "Batch not applied: \(error.localizedDescription)" }
                        working = false
                    }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 620)
    }

    private func evidenceExplanation(_ evidence: LocationEvidence) -> String {
        switch evidence {
        case .matching: "Located photos before and after are within 1 km of each other. Confirm visually; times alone do not prove a shared location."
        case .oneSided: "Only one side has a nearby located reference. Review carefully before applying."
        case .conflicting: "The references are over 1 km apart. Choose the correct reference or split this group."
        case .none: "No nearby located references, or no capture date. These photos need manual investigation."
        }
    }
    private func timeRange(_ group: LocationReviewGroup) -> String {
        let dates = group.photos.compactMap(\.captureDate).sorted()
        guard let first = dates.first, let last = dates.last else { return "No capture date" }
        return "\(first.formatted(date: .abbreviated, time: .shortened)) – \(last.formatted(date: .omitted, time: .shortened))"
    }
    private func rebuild() {
        available = expandedGroups.compactMap { remaining($0, skipped: showSkipped) }
    }
    private func advance() {
        rebuild()
        selectedGroupID = visible.first?.id
        progress.lastGroupID = selectedGroupID
        save()
    }
    private func save() {
        guard !overview.reviewScope.isEmpty else { return }
        do { UserDefaults.standard.set(try JSONEncoder().encode(progress), forKey: storageKey) }
        catch { message = "Review progress could not be saved. Keep this window open to retain the current session." }
    }
}
