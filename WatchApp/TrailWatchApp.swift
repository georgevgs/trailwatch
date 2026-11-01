import AppIntents
import SwiftUI
import TrailKit
import WatchKit
import WidgetKit

@main
struct TrailWatchApp: App {
    @WKApplicationDelegateAdaptor private var app: AppDelegate

    var body: some Scene {
        WindowGroup {
            Group {
                if let hike = app.hikes.current {
                    // A hike takes over the app until it's ended, so it can't be left with the workout running.
                    HikeView(session: hike, onClose: app.hikes.close)
                } else {
                    NavigationStack {
                        RouteListView()
                    }
                }
            }
            .environment(app.library)
            .environment(app.hikes)
        }
    }
}

/// Holds what lives as long as the app, so WatchKit can hand back a hike after a crash.
final class AppDelegate: NSObject, WKApplicationDelegate {
    let library: RouteLibrary
    let hikes: HikeManager
    private let phone: PhoneConnection

    override init() {
        let library = RouteLibrary(mapsDirectory: URL.applicationSupportDirectory.appending(path: "Maps"))
        self.library = library
        let hikes = HikeManager(library: library)
        self.hikes = hikes
        // Started at launch so routes the iPhone queued arrive as soon as the app runs.
        phone = PhoneConnection(library: library)
        super.init()
        // Lets Siri's Pause Hike and Resume Hike reach the hike in progress.
        AppDependencyManager.shared.add(dependency: hikes)
        // A hike left behind by a crash; a recovered one publishes itself again.
        if HikeGlance.shared != nil {
            HikeGlance.shared = nil
            WidgetCenter.shared.reloadTimelines(ofKind: HikeGlance.widgetKind)
        }
    }

    /// watchOS relaunched the app after it quit during a workout.
    func handleActiveWorkoutRecovery() {
        Task { await hikes.recover() }
    }
}
