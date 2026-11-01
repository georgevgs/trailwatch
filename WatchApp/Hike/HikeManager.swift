import Foundation
import Observation
import TrailKit

/// The hike in progress. Owned by the app rather than a screen, so no navigation can leave a
/// workout running without its hike, and a hike carries on if the app is relaunched mid-hike.
@Observable
final class HikeManager {
    private(set) var current: HikeSession?
    private let library: RouteLibrary

    init(library: RouteLibrary) {
        self.library = library
    }

    func start(_ route: GPXRoute, reversed: Bool, offRouteDistance: Double) {
        guard current == nil else { return }
        let progress = HikeProgress(routeID: route.id, reversed: reversed, offRouteDistance: offRouteDistance)
        let hike = HikeSession(route: route, progress: progress)
        hike.start()
        current = hike
    }

    /// Leaves an ended hike.
    func close() {
        current = nil
    }

    /// Carries on the hike whose workout was running when the app quit unexpectedly.
    func recover() async {
        guard current == nil else { return }
        let workout = WorkoutRecorder()
        guard await workout.recover() else { return }
        guard let progress = HikeProgress.saved, let route = library.route(id: progress.routeID) else {
            // Nothing to navigate: save what was recorded rather than leave the workout running.
            await workout.finish(at: .now, ascent: HikeProgress.saved?.ascent ?? 0, saving: true)
            HikeProgress.saved = nil
            return
        }
        let hike = HikeSession(route: route, progress: progress, workout: workout)
        hike.start()
        current = hike
    }
}
