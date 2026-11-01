import Foundation

/// The hike in progress as the watch-face complication shows it. The Watch app writes it to the app
/// group it shares with its widget extension; nil when no hike is running.
public struct HikeGlance: Codable, Equatable, Sendable {
    public var routeName: String
    /// From 0 to 1 along the route.
    public var progress: Double
    /// Metres along the route still to walk.
    public var distanceRemaining: Double
    /// Where the hike's running timer counts from (see ``Stopwatch``).
    public var countingFrom: Date
    /// When the current pause began; nil while hiking.
    public var pausedAt: Date?
    /// The estimated finish, while hiking.
    public var arrival: Date?
    public var updated: Date

    public init(routeName: String, progress: Double, distanceRemaining: Double, countingFrom: Date,
                pausedAt: Date?, arrival: Date?, updated: Date) {
        self.routeName = routeName
        self.progress = progress
        self.distanceRemaining = distanceRemaining
        self.countingFrom = countingFrom
        self.pausedAt = pausedAt
        self.arrival = arrival
        self.updated = updated
    }

    public static let appGroup = "group.eu.vagdas.trailwatch"
    public static let widgetKind = "TrailWatchLauncher"
    private static let key = "hikeGlance"

    /// The glance in the shared app group.
    public static var shared: HikeGlance? {
        get {
            UserDefaults(suiteName: appGroup)?.data(forKey: key)
                .flatMap { try? JSONDecoder().decode(HikeGlance.self, from: $0) }
        }
        set {
            UserDefaults(suiteName: appGroup)?.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
        }
    }

    public var isPaused: Bool { pausedAt != nil }

    /// Whether going from `old` to `new` is worth redrawing the complication: a hike starting or
    /// ending, a pause or resume, each whole percent of the route, or every two minutes for the arrival time.
    public static func isWorthShowing(_ new: HikeGlance?, after old: HikeGlance?) -> Bool {
        guard let new, let old else { return (new == nil) != (old == nil) }
        return new.isPaused != old.isPaused
            || (new.progress * 100).rounded(.down) != (old.progress * 100).rounded(.down)
            || new.updated.timeIntervalSince(old.updated) >= 120
    }
}
