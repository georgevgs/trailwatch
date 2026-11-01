import Foundation

/// Where a GPS fix sits relative to the route.
public struct RoutePosition: Equatable, Sendable {
    /// Metres from the route's start to your place on it.
    public var distanceAlong: Double
    /// Metres from you to the nearest point of the route.
    public var distanceFromRoute: Double
    /// The nearest point of the route: the way back when you're off it.
    public var nearestPoint: RoutePoint
}

/// A waypoint near the route, placed along it.
public struct RouteStop: Equatable, Sendable {
    public var waypoint: Waypoint
    /// Metres from the route's start to the waypoint's place on it.
    public var distanceAlong: Double
}

/// Follows your progress along a route, fix by fix.
public struct RouteTracker: Sendable {
    public let route: GPXRoute
    /// Metres from the start to each point.
    private let cumulative: [Double]
    public private(set) var position: RoutePosition?

    public init(route: GPXRoute) {
        self.route = route
        var total = 0.0
        var cumulative = [0.0]
        for (a, b) in zip(route.points, route.points.dropFirst()) {
            total += RouteCalculator.distance(from: a, to: b)
            cumulative.append(total)
        }
        self.cumulative = cumulative
    }

    public var distanceAlong: Double { position?.distanceAlong ?? 0 }

    public var distanceRemaining: Double { max(0, route.distance - distanceAlong) }

    /// Places a fix on the route. Where it passes a spot twice (loops, out-and-backs), picks the
    /// match that continues from the last one, preferring forward.
    @discardableResult
    public mutating func update(with fix: RoutePoint, accuracy: Double = 0) -> RoutePosition? {
        let matches = route.points.indices.dropLast().map { match(fix, segment: $0) }
        guard let nearest = matches.min(by: { $0.distance < $1.distance }) else { return nil }

        let window = max(15, accuracy)
        let candidates = matches.filter { $0.distance <= nearest.distance + window }
        let chosen = if let last = position?.distanceAlong {
            candidates.min { cost(of: $0.along, after: last) < cost(of: $1.along, after: last) }!
        } else {
            candidates.min { $0.along < $1.along }!
        }

        position = RoutePosition(
            distanceAlong: chosen.along, distanceFromRoute: nearest.distance, nearestPoint: nearest.point)
        return position
    }

    /// Where a point near the route, such as a waypoint, sits along it.
    public func locate(_ point: RoutePoint) -> RoutePosition? {
        let matches = route.points.indices.dropLast().map { match(point, segment: $0) }
        guard let nearest = matches.min(by: { $0.distance < $1.distance }) else { return nil }
        return RoutePosition(distanceAlong: nearest.along, distanceFromRoute: nearest.distance, nearestPoint: nearest.point)
    }

    /// The route's waypoints within `range` metres of it, in the order you reach them.
    public func stops(within range: Double = 150) -> [RouteStop] {
        route.waypoints
            .compactMap { waypoint in
                guard let position = locate(waypoint.point), position.distanceFromRoute <= range else { return nil }
                return RouteStop(waypoint: waypoint, distanceAlong: position.distanceAlong)
            }
            .sorted { $0.distanceAlong < $1.distanceAlong }
    }

    /// Splits the route at `distance` into walked and ahead. Both include the split point.
    public func split(at distance: Double) -> (walked: [RoutePoint], ahead: [RoutePoint]) {
        guard route.points.count > 1, let total = cumulative.last else { return ([], route.points) }
        let distance = min(max(distance, 0), total)
        let start = cumulative.lastIndex { $0 <= distance } ?? 0
        let end = min(start + 1, route.points.count - 1)
        let length = cumulative[end] - cumulative[start]
        let fraction = length > 0 ? (distance - cumulative[start]) / length : 0
        let point = interpolate(route.points[start], route.points[end], fraction)
        return (Array(route.points[...start]) + [point], [point] + Array(route.points[end...]))
    }

    private struct Match {
        var along: Double
        var distance: Double
        var point: RoutePoint
    }

    /// Closest point on a segment to the fix, in flat metres around the fix.
    private func match(_ fix: RoutePoint, segment index: Int) -> Match {
        let a = route.points[index]
        let b = route.points[index + 1]
        let metresPerDegree = RouteCalculator.earthRadius * .pi / 180
        let metresPerLongitude = metresPerDegree * cos(RouteCalculator.radians(fix.latitude))
        func flat(_ point: RoutePoint) -> SIMD2<Double> {
            [(point.longitude - fix.longitude) * metresPerLongitude, (point.latitude - fix.latitude) * metresPerDegree]
        }

        let start = flat(a)
        let direction = flat(b) - start
        let lengthSquared = (direction * direction).sum()
        // The fix is the origin, so the projection of (fix − start) onto the segment is −start·direction.
        let fraction = lengthSquared > 0 ? min(1, max(0, -(start * direction).sum() / lengthSquared)) : 0
        let closest = start + fraction * direction

        return Match(
            along: cumulative[index] + fraction * (cumulative[index + 1] - cumulative[index]),
            distance: (closest * closest).sum().squareRoot(),
            point: interpolate(a, b, fraction))
    }

    /// Metres of progress a match implies; stepping back costs three times as much as stepping forward.
    private func cost(of along: Double, after last: Double) -> Double {
        along >= last ? along - last : (last - along) * 3
    }

    private func interpolate(_ a: RoutePoint, _ b: RoutePoint, _ fraction: Double) -> RoutePoint {
        RoutePoint(
            latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: a.longitude + (b.longitude - a.longitude) * fraction)
    }
}
