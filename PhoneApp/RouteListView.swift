import SwiftUI
import TrailKit

struct RouteListView: View {
    @Environment(RouteLibrary.self) private var library
    @Environment(WatchTransferService.self) private var watch
    @Environment(OfflineMapService.self) private var maps
    @State private var isImporting = false
    @State private var importProblem: String?

    var body: some View {
        @Bindable var watch = watch

        NavigationStack {
            List {
                if let expiry = ProvisioningProfile.appExpirationDate, expiry.timeIntervalSinceNow < 3 * 86_400 {
                    Label("TrailWatch stops opening \(expiry, format: .relative(presentation: .named)) on this iPhone and your Watch. Install it again from Xcode before your next hike.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                ForEach(library.routes) { route in
                    NavigationLink(value: route.id) {
                        row(route)
                    }
                }
                .onDelete { offsets in
                    for id in offsets.map({ library.routes[$0].id }) {
                        try? library.delete(id: id)
                    }
                }
                .reorderable()
            }
            .reorderContainer(for: GPXRoute.self) { try? library.apply($0) }
            .overlay {
                if library.routes.isEmpty {
                    ContentUnavailableView {
                        Label("No Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    } description: {
                        Text("Import a GPX file from Files, then send it to your Apple Watch.")
                    } actions: {
                        Button("Import GPX") { isImporting = true }
                    }
                }
            }
            .navigationTitle("Routes")
            .navigationDestination(for: UUID.self) { id in
                if let route = library.route(id: id) {
                    RouteDetailView(route: route)
                }
            }
            .toolbar {
                Button("Import GPX", systemImage: "plus") { isImporting = true }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.gpx], allowsMultipleSelection: true) {
                importFiles($0)
            }
            .alert("Couldn't Import", isPresented: isShowing($importProblem), presenting: importProblem) { _ in
            } message: {
                Text($0)
            }
            .alert("Not Sent", isPresented: isShowing($watch.failure), presenting: watch.failure) { _ in
            } message: {
                Text($0)
            }
        }
    }

    private func row(_ route: GPXRoute) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(route.name)
                    .font(.headline)
                Text("\(Format.kilometres(route.distance)) km · ↑ \(Format.metres(route.elevationGain)) m")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if watch.sending.contains(route.id) || maps.downloading.contains(route.id) {
                ProgressView()
            } else if watch.routesOnWatch.contains(route.id) {
                Image(systemName: "applewatch")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("On Apple Watch")
            }
        }
    }

    private func importFiles(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result else { return }
        var unreadable: [String] = []
        for url in urls {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let route = try GPXParser.parse(
                    Data(contentsOf: url), fallbackName: url.deletingPathExtension().lastPathComponent)
                try library.save(route)
                Task { await maps.download(route) }
            } catch {
                unreadable.append(url.lastPathComponent)
            }
        }
        if !unreadable.isEmpty {
            importProblem = "\(unreadable.formatted()) isn't a GPX file with a track or route TrailWatch can read."
        }
    }

    private func isShowing(_ message: Binding<String?>) -> Binding<Bool> {
        Binding { message.wrappedValue != nil } set: { if !$0 { message.wrappedValue = nil } }
    }
}
