import SwiftUI
import AppKit

@main
struct PhotosStatisticsApp: App {
    @StateObject private var model = LibraryModel()
    var body: some Scene {
        WindowGroup("Photos Statistics") {
            LibraryWindow(model: model).task { model.restoreLibrary() }
        }.defaultSize(width: 1220, height: 800)
    }
}

enum LibrarySection: String, CaseIterable, Identifiable {
    case overview, photos, review, diagnostics
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .photos: "All photos"
        case .review: "Availability review"
        case .diagnostics: "Diagnostics"
        }
    }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .photos: "photo.on.rectangle"
        case .review: "checklist"
        case .diagnostics: "wrench.and.screwdriver"
        }
    }
}

@MainActor
final class LibraryModel: ObservableObject {
    @Published var overview: LibraryOverview?
    @Published var report = "No library has been scanned yet."
    @Published var busy = false
    @Published var progress = ""
    @Published var notice: String?
    @Published var libraryName = "Your Photos library"
    @Published var section: LibrarySection? = .overview
    @Published var photoFilter: OriginalAvailability?
    @Published var reviewReason: ReviewReason?
    let previews = PhotoPreviewStore()
    private var selectedURL: URL?
    private var restored = false

    func chooseLibrary() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose your Photos library"
        panel.message = "Your library will be opened read-only. No originals will be downloaded."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: "libraryBookmark")
        } catch { UserDefaults.standard.removeObject(forKey: "libraryBookmark") }
        scan(url)
    }

    func restoreLibrary() {
        guard !restored else { return }
        restored = true
        guard let data = UserDefaults.standard.data(forKey: "libraryBookmark") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale else {
                notice = "Choose your library again to renew its saved read-only access."
                return
            }
            scan(url)
        } catch { notice = "Saved library access could not be restored. Choose your library again." }
    }

    func refresh() { if let selectedURL, !busy { scan(selectedURL) } }
    func showPhotos(_ status: OriginalAvailability) { photoFilter = status; section = .photos }
    func showReview(_ reason: ReviewReason?) { reviewReason = reason; section = .review }

    private func scan(_ url: URL) {
        busy = true
        notice = nil
        overview = nil
        selectedURL = url
        libraryName = url.deletingPathExtension().lastPathComponent
        progress = "Preparing your library…"
        let progressModel = self
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return Result {
                    try LibraryProbe.inspect(selection: url) { message in
                        Task { @MainActor in progressModel.progress = message }
                    }
                }
            }.value
            switch result {
            case .success(let value):
                overview = value.overview
                report = value.text
                if value.overview == nil { notice = "This version does not yet understand this library format. You can open Diagnostics for the scan report." }
            case .failure(let error):
                notice = "The library could not be read: \(error.localizedDescription)"
                report = "Scan failed.\n\n\(error.localizedDescription)"
            }
            saveAggregateReport()
            busy = false
        }
    }

    private func saveAggregateReport() {
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("PhotosStatistics")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let header = "Generated: \(ISO8601DateFormatter().string(from: Date()))\nResult: \(overview == nil ? "incomplete" : "success")\n\n"
            try (header + report).write(to: folder.appendingPathComponent("last-probe-report.txt"), atomically: true, encoding: .utf8)
            let summary = folder.appendingPathComponent("last-overview-summary.json")
            if let overview { try overview.summaryJSON().write(to: summary, options: .atomic) }
            else if FileManager.default.fileExists(atPath: summary.path) { try FileManager.default.removeItem(at: summary) }
        } catch { notice = "The scan result is available in this window, but its local diagnostic report could not be saved." }
    }
}

struct LibraryWindow: View {
    @ObservedObject var model: LibraryModel
    var body: some View {
        NavigationSplitView {
            List(selection: $model.section) {
                Section("Library") {
                    ForEach([LibrarySection.overview, .photos, .review]) { section in
                        Label(section.title, systemImage: section.icon).tag(section)
                    }
                }
                Section("Tools") { Label("Diagnostics", systemImage: "wrench.and.screwdriver").tag(LibrarySection.diagnostics) }
            }
            .navigationTitle("Photos Statistics")
            .navigationSplitViewColumnWidth(min: 200, ideal: 225)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Read-only library access", systemImage: "lock.shield")
                    Text("Your photos stay on your Mac and in iCloud.").foregroundStyle(.secondary)
                }.font(.caption).padding().frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            VStack(spacing: 0) {
                if let notice = model.notice {
                    Label(notice, systemImage: "info.circle").font(.callout).padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.orange.opacity(0.1))
                }
                if model.busy {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Reading your library").font(.title2.bold())
                        Text(model.progress).foregroundStyle(.secondary)
                        Text("Metadata and file attributes only. No image downloads.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.section == .diagnostics {
                    ScrollView {
                        Text(model.report).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    }
                } else if let overview = model.overview {
                    switch model.section ?? .overview {
                    case .overview: OverviewScreen(model: model, overview: overview)
                    case .photos: PhotoBrowser(overview: overview, status: $model.photoFilter, reason: nil, previews: model.previews)
                    case .review: ReviewScreen(model: model, overview: overview)
                    case .diagnostics: EmptyView()
                    }
                } else {
                    ContentUnavailableView {
                        Label("Get to know your photo library", systemImage: "photo.stack")
                    } description: {
                        Text("Load your library for an overview and a closer look at original availability. This first version makes no changes to Photos.")
                    } actions: {
                        Button("Choose Photos Library…", action: model.chooseLibrary).buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(model.section?.title ?? "Overview").navigationSubtitle(model.libraryName)
            .toolbar {
                ToolbarItemGroup {
                    if model.section == .diagnostics {
                        Button("Copy report", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.report, forType: .string)
                        }
                    }
                    Button("Refresh", systemImage: "arrow.clockwise", action: model.refresh).disabled(model.busy || model.overview == nil)
                    Button("Choose library", systemImage: "folder", action: model.chooseLibrary).disabled(model.busy)
                }
            }
        }.frame(minWidth: 1050, minHeight: 650)
    }
}
