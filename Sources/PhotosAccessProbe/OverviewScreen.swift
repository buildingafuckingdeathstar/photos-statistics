import SwiftUI

struct OverviewScreen: View {
    @ObservedObject var model: LibraryModel
    let overview: LibraryOverview
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your main library, at a glance").font(.largeTitle.bold())
                    Text("Scanned \(overview.scanDate.formatted(date: .abbreviated, time: .shortened))").foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    SummaryTile(title: "Photos", value: overview.photos.count.formatted(), icon: "photo")
                    SummaryTile(title: "Videos", value: overview.videoCount.formatted(), icon: "video")
                    SummaryTile(title: "Photos without location", value: (overview.photos.count - overview.locatedCount).formatted(), icon: "mappin.slash")
                }
                if let start = overview.firstDate, let end = overview.lastDate {
                    Label("Photo dates: \(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Library storage").font(.title2.bold())
                    Text("Main-library originals only. A local preview does not count as an original.").font(.callout).foregroundStyle(.secondary)
                    ForEach(OriginalAvailability.allCases.filter { $0 != .shared }, id: \.self) { status in
                        Button {
                            if status == .review { model.showReview(nil) } else { model.showPhotos(status) }
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: status.icon).font(.title2).foregroundStyle(status.tint).frame(width: 30)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(status.title).font(.headline)
                                    Text(status.detail).font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(overview.count(status).formatted()).font(.title2.monospacedDigit().bold())
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(18).background(status.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("What needs a closer look?").font(.title2.bold())
                    Text("Uncertain availability does not mean a photo is damaged. Select a reason to inspect the matching photos.").font(.callout).foregroundStyle(.secondary)
                    ForEach(ReviewReason.allCases.filter { overview.count($0) > 0 }) { reason in
                        Button { model.showReview(reason) } label: {
                            HStack {
                                Text(reason.title)
                                Spacer()
                                Text(overview.count(reason).formatted()).monospacedDigit().foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption)
                            }.padding(.vertical, 7)
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
                Text("Shared Albums excluded: \(overview.excludedSharedPhotoCount.formatted()) photos and \(overview.excludedSharedVideoCount.formatted()) videos. Main-library counts include hidden photos and burst members. A photo saved into the main library still counts there. The metadata scan does not change your library.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
}

struct SummaryTile: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension OriginalAvailability {
    var icon: String {
        switch self { case .local: "internaldrive"; case .remote: "icloud"; case .shared: "person.2.crop.square.stack"; case .review: "questionmark.folder" }
    }
    var tint: Color {
        switch self { case .local: .green; case .remote: .blue; case .shared: .purple; case .review: .orange }
    }
    var detail: String {
        switch self {
        case .local: "Photos and file presence agree that the managed original is local."
        case .remote: "The managed original is absent; Photos reports a remote copy."
        case .shared: "Photos identifies these as Shared Album copies, which do not establish full-original availability."
        case .review: "The current checks cannot confidently classify these originals."
        }
    }
}
