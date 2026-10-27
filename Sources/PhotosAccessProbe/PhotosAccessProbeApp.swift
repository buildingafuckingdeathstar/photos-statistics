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
            busy = false
        }
    }
}
