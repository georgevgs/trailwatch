import SwiftUI
import TrailKit
import UniformTypeIdentifiers

@main
struct TrailWatchPhoneApp: App {
    @State private var library: RouteLibrary
    @State private var watch: WatchTransferService
    @State private var maps: OfflineMapService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let library = RouteLibrary()
        let watch = WatchTransferService()
        _library = State(initialValue: library)
        _watch = State(initialValue: watch)
        _maps = State(initialValue: OfflineMapService(library: library, watch: watch))
    }

    var body: some Scene {
        WindowGroup {
            RouteListView()
                .environment(library)
                .environment(watch)
                .environment(maps)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { Task { await maps.catchUp() } }
        }
    }
}

extension UTType {
    /// Declared in PhoneApp-Info.plist.
    static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
}
