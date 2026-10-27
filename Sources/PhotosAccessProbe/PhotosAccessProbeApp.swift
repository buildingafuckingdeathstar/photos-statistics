import SwiftUI
import AppKit

@main
struct PhotosAccessProbeApp: App {
    var body: some Scene {
        WindowGroup("Photos Access Probe") { ProbeView() }
            .defaultSize(width: 850, height: 650)
    }
}

struct ProbeView: View {
    @State private var report = "Choose a Photos library to test read-only database access. This prototype checks access and inventories metadata columns; it does not yet calculate photographic statistics."
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Photos library access").font(.largeTitle.bold())
            Text("Read-only access • Local processing • No original downloads")
                .foregroundStyle(.secondary)
            HStack {
                Button("Choose Photos Library…", action: chooseLibrary).disabled(busy)
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Copy Report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }.disabled(busy)
            }
            ScrollView {
                Text(report).font(.system(.body, design: .monospaced))
                    .foregroundStyle(failed ? Color.red : Color.primary)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            Text("A successful check demonstrates technical access on this Mac. App Store review and metadata interpretation remain separate checks.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(24).frame(minWidth: 650, minHeight: 450)
        .task { restoreLibrary() }
    }

    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Choose your Photos library"
        panel.message = "Select a .photoslibrary package, or a folder containing a Photos database. Access is read-only."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: "libraryBookmark")
        } catch {
            // A bookmark failure does not invalidate access from this file chooser session.
            UserDefaults.standard.removeObject(forKey: "libraryBookmark")
        }
        inspect(url)
    }

    private func restoreLibrary() {
        guard let data = UserDefaults.standard.data(forKey: "libraryBookmark") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale else {
                report = "Please choose your library again to renew its saved read-only access."
                return
            }
            inspect(url)
        } catch {
            report = "Saved library access could not be restored. Please choose your library again."
        }
    }

    private func inspect(_ url: URL) {
        busy = true
        failed = false
        report = "Checking access and creating a temporary database snapshot…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return Result { try LibraryProbe.inspect(selection: url) }
            }.value
            switch result {
            case .success(let value): report = value.text
            case .failure(let error):
                failed = true
                report = "Access check did not complete.\n\n\(error.localizedDescription)\n\nThe result is not evidence of missing photos or missing EXIF."
            }
            // Store only the aggregate diagnostic report in this app's own container.
            // No library snapshot, per-photo identifiers, paths or metadata values are retained.
            do {
                let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
                    .appendingPathComponent("PhotosStatistics")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let header = "Generated: \(ISO8601DateFormatter().string(from: Date()))\nResult: \(failed ? "failed" : "success")\n\n"
                try (header + report).write(to: folder.appendingPathComponent("last-probe-report.txt"),
                                           atomically: true, encoding: .utf8)
                report += "\n\nAggregate report saved in the app's Application Support folder."
            } catch {
                report += "\n\nCould not save the local report: \(error.localizedDescription)"
            }
            busy = false
        }
    }
}
