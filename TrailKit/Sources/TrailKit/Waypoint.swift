import Foundation

/// A named place from a GPX `<wpt>`: a spring, hut, junction or summit marked along the way.
public struct Waypoint: Codable, Hashable, Sendable {
    public var point: RoutePoint
    public var name: String

    public init(point: RoutePoint, name: String) {
        self.point = point
        self.name = name
    }
}

/// Taps once as you reach each waypoint, without repeating while you linger nearby.
public struct WaypointAlerts: Sendable {
    /// Metres from a waypoint that count as reaching it.
    public let radius: Double
    private var reached: Set<Waypoint> = []

    public init(radius: Double = 40) {
        self.radius = radius
    }

    /// The waypoint you've just come within `radius` of, if any. Fixes too vague to tell are skipped.
    public mutating func update(at position: RoutePoint, accuracy: Double, waypoints: [Waypoint]) -> Waypoint? {
        guard accuracy <= radius else { return nil }
        let distances = waypoints
            .filter { !reached.contains($0) }
            .map { ($0, RouteCalculator.distance(from: position, to: $0.point)) }
        guard let (waypoint, distance) = distances.min(by: { $0.1 < $1.1 }), distance <= radius else { return nil }
        reached.insert(waypoint)
        return waypoint
    }
}
