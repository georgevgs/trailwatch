import CoreLocation
import Observation
import TrailKit
import WatchKit
import WidgetKit

/// One hike along a route: GPS, progress, off-route alerts, pausing and the workout recording.
@Observable
final class HikeSession {
    static let offRouteDistanceKey = "offRouteDistance"

    /// The route in the direction you're walking it.
    let route: GPXRoute
    /// The route's waypoints near it, in the order you'll reach them.
    let stops: [RouteStop]
    /// The offline map, when the route came with map data.
    let mapLayers: TrailMapLayers?
    let startDate: Date
    private(set) var endDate: Date?
    /// Time hiking, less pauses.
    private(set) var stopwatch: Stopwatch
    private(set) var tracker: RouteTracker
    private(set) var monitor: OffRouteMonitor
    private(set) var location: CLLocation?
    /// The climb ahead and the time it should take.
    private(set) var finish: FinishEstimate
    /// Today's sunset at the start of the route.
    let sunset: Date?
    private var warnedAboutDark = false
    private var record: HikeProgress
    private var climb = ClimbCounter(threshold: 3)
    private var waypointAlerts = WaypointAlerts()
    /// The waypoint you've just reached, while you're still near it.
    private(set) var reachedWaypoint: Waypoint?
    /// Shows the off-route screen; set when you leave the route, cleared when you're back.
    var showsOffRouteAlert = false
    /// Asks the map to frame you and the way back to the route.
    var showsWayBack = false
    /// Asks whether to save or discard the hike.
    var showsEndDialog = false

    let gps = LocationService()
    let workout: WorkoutRecorder
    private var lastCounted: CLLocation?
    /// What the complication was last given.
    private var shownGlance: HikeGlance?
    private var starting: Task<Void, Never>?
    private var tracking: Task<Void, Never>?

    /// A new hike, or one carrying on with a recovered workout and its saved progress.
    init(route: GPXRoute, progress: HikeProgress, workout: WorkoutRecorder = WorkoutRecorder()) {
        let route = progress.reversed ? route.reversed() : route
        self.route = route
        record = progress
        self.workout = workout
        mapLayers = route.map.map(TrailMapLayers.init)
        let tracker = RouteTracker(route: route)
        self.tracker = tracker
        stops = tracker.stops()
        finish = FinishEstimate(profile: ElevationProfile(route: route))
        sunset = route.points.first.flatMap { Sun.sunset(on: .now, latitude: $0.latitude, longitude: $0.longitude) }
        monitor = OffRouteMonitor(threshold: progress.offRouteDistance)
        let now = Date.now
        startDate = workout.startDate ?? now
        stopwatch = Stopwatch(countingFrom: now - workout.elapsedTime(at: now), pausedAt: workout.isPaused ? now : nil)
    }

    var isFinished: Bool { endDate != nil }

    var isPaused: Bool { stopwatch.isPaused }

    /// The Watch's charge now (or when the hike ended) and when it started, from 0 to 1.
    var battery: (now: Float, atStart: Float)? {
        let now = batteryAtEnd ?? WKInterfaceDevice.current().batteryLevel
        guard now >= 0, let atStart = record.batteryAtStart else { return nil }
        return (now, atStart)
    }
    private var batteryAtEnd: Float?

    /// Metres walked, from GPS.
    var distanceWalked: Double { record.distanceWalked }

    /// Metres climbed, from the watch's GPS and barometric altitude.
    var ascent: Double { record.ascent }

    var progress: Double { route.distance > 0 ? tracker.distanceAlong / route.distance : 0 }

    /// The next waypoint along the route.
    var nextStop: RouteStop? {
        stops.first { $0.distanceAlong > tracker.distanceAlong + waypointAlerts.radius }
    }

    /// Seconds to the finish at your pace so far.
    var timeToFinish: TimeInterval { finish.timeToFinish(along: tracker.distanceAlong, elapsed: elapsed) }

    /// At this pace you'd still be out when the sun sets.
    var finishesAfterDark: Bool {
        guard let sunset, sunset > .now, !isFinished else { return false }
        return Date.now + timeToFinish > sunset
    }

    /// Time hiking, less pauses.
    var elapsed: TimeInterval { stopwatch.elapsed(at: endDate ?? .now) }

    /// Starts the workout and GPS. They run until `end(saving:)`, whatever is on screen.
    func start() {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        if record.batteryAtStart == nil, device.batteryLevel >= 0 {
            record.batteryAtStart = device.batteryLevel
        }
        HikeProgress.saved = record
        workout.onChange = { [weak self] change, date in
            switch change {
            case .paused: self?.pause(at: date)
            case .resumed: self?.resume(at: date)
            case .ended: Task { await self?.end(saving: true) }
            }
        }
        if workout.state != .recording {
            starting = Task { await workout.start(at: startDate) }
        }
        tracking = Task { await gps.track { handle($0) } }
        updateComplication()
    }

    func pause(at date: Date = .now) {
        guard !isFinished, !isPaused else { return }
        stopwatch.pause(at: date)
        workout.pause()
        updateComplication()
    }

    func resume(at date: Date = .now) {
        guard !isFinished, isPaused else { return }
        stopwatch.resume(at: date)
        // Ground covered while paused doesn't count.
        lastCounted = nil
        climb = ClimbCounter(threshold: 3)
        workout.resume()
        updateComplication()
    }

    /// Ends the hike. Saving records it in Apple Health; discarding keeps nothing.
    func end(saving: Bool) async {
        guard endDate == nil else { return }
        let end = Date.now
        endDate = end
        batteryAtEnd = WKInterfaceDevice.current().batteryLevel
        showsOffRouteAlert = false
        tracking?.cancel()
        HikeProgress.saved = nil
        updateComplication()
        // Ending straight after Start waits for the workout to begin, so it can't be left running.
        await starting?.value
        await workout.finish(at: end, ascent: ascent, saving: saving)
    }

    private func handle(_ fix: CLLocation) {
        guard endDate == nil else { return }
        location = fix
        let point = RoutePoint(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
        let position = tracker.update(with: point, accuracy: fix.horizontalAccuracy)
        updateComplication()

        // Paused, the map still shows where you are, but nothing is counted or recorded.
        guard !isPaused else { return }
        workout.add(fix)
        let before = record
        countDistance(to: fix)
        countClimb(fix)
        if record != before { HikeProgress.saved = record }
        checkWaypoints(at: point, accuracy: fix.horizontalAccuracy)

        guard let position else { return }
        if monitor.hasReachedRoute { finish.reachedRoute(along: position.distanceAlong, elapsed: elapsed) }
        if finishesAfterDark, !warnedAboutDark {
            warnedAboutDark = true
            WKInterfaceDevice.current().play(.notification)
        }
        switch monitor.update(distanceFromRoute: position.distanceFromRoute, accuracy: fix.horizontalAccuracy, at: fix.timestamp) {
        case .left:
            showsOffRouteAlert = true
            WKInterfaceDevice.current().play(.notification)
        case .rejoined:
            showsOffRouteAlert = false
            WKInterfaceDevice.current().play(.success)
        case nil:
            break
        }
    }

    /// Shares the hike with the watch-face complication and redraws it when something visible changed.
    /// Reloads while a workout runs don't count against WidgetKit's budget (Apple DTS), but each one
    /// still costs battery.
    private func updateComplication() {
        let glance = isFinished ? nil : HikeGlance(
            routeName: route.name, progress: progress, distanceRemaining: tracker.distanceRemaining,
            countingFrom: stopwatch.countingFrom, pausedAt: stopwatch.pausedAt,
            arrival: isPaused ? nil : .now + timeToFinish, updated: .now)
        guard HikeGlance.isWorthShowing(glance, after: shownGlance) else { return }
        shownGlance = glance
        HikeGlance.shared = glance
        WidgetCenter.shared.reloadTimelines(ofKind: HikeGlance.widgetKind)
    }

    private func checkWaypoints(at point: RoutePoint, accuracy: Double) {
        if let reached = reachedWaypoint,
           RouteCalculator.distance(from: point, to: reached.point) > waypointAlerts.radius * 1.5 {
            reachedWaypoint = nil
        }
        if let waypoint = waypointAlerts.update(at: point, accuracy: accuracy, waypoints: route.waypoints) {
            reachedWaypoint = waypoint
            WKInterfaceDevice.current().play(.navigationGenericManeuver)
        }
    }

    private func countDistance(to fix: CLLocation) {
        guard fix.horizontalAccuracy <= 30 else { return }
        guard let last = lastCounted else {
            lastCounted = fix
            return
        }
        // Steps under 5 m are mostly GPS wander while standing still.
        let step = fix.distance(from: last)
        guard step >= 5 else { return }
        record.distanceWalked += step
        lastCounted = fix
    }

    private func countClimb(_ fix: CLLocation) {
        guard (0...15).contains(fix.verticalAccuracy) else { return }
        let before = climb.gain
        climb.add(fix.altitude)
        record.ascent += climb.gain - before
    }
}
