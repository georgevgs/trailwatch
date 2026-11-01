import Foundation

/// What a hike needs to carry on if the app quits mid-hike. Saved as the hike goes and cleared when
/// it ends; the workout itself comes back from HealthKit.
nonisolated struct HikeProgress: Codable, Equatable {
    let routeID: UUID
    /// Walking the route from its finish to its start.
    let reversed: Bool
    let offRouteDistance: Double
    var distanceWalked = 0.0
    var ascent = 0.0
    /// The Watch's charge when the hike started, from 0 to 1.
    var batteryAtStart: Float?

    private static let key = "hikeInProgress"

    static var saved: HikeProgress? {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(HikeProgress.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: key) }
    }
}
