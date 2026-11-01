import CoreLocation

/// A route to follow, read from a GPX file. Distance and climb are worked out once, when it is created.
public struct GPXRoute: Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let points: [RoutePoint]
    /// Metres along the route.
    public let distance: Double
    /// Metres climbed, with GPS/elevation-model noise filtered out.
    public let elevationGain: Double
    /// Named places from the file: springs, huts, junctions.
    public let waypoints: [Waypoint]
    /// Map data around the route for offline use, once the iPhone has downloaded it.
    public var map: TrailMap?

    public init(id: UUID = UUID(), name: String, points: [RoutePoint], waypoints: [Waypoint] = []) {
        self.id = id
        self.name = name
        self.points = points
        self.waypoints = waypoints
        distance = RouteCalculator.length(of: points)
        elevationGain = RouteCalculator.elevationGain(of: points)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        points = try container.decode([RoutePoint].self, forKey: .points)
        distance = try container.decode(Double.self, forKey: .distance)
        elevationGain = try container.decode(Double.self, forKey: .elevationGain)
        // Routes saved before waypoints were read have none.
        waypoints = try container.decodeIfPresent([Waypoint].self, forKey: .waypoints) ?? []
        map = try container.decodeIfPresent(TrailMap.self, forKey: .map)
    }

    /// The same route walked from its finish back to its start. Its climb is worked out again.
    public func reversed() -> GPXRoute {
        var route = GPXRoute(id: id, name: name, points: points.reversed(), waypoints: waypoints)
        route.map = map
        return route
    }

    public var isLoop: Bool { RouteCalculator.isLoop(points) }

    public var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }
}
