import Foundation

public enum RouteCalculator {
    /// Mean Earth radius (IUGG), in metres.
    static let earthRadius = 6_371_008.8

    /// Haversine distance in metres. Within 0.5% of the ellipsoid, well below GPS error.
    public static func distance(from a: RoutePoint, to b: RoutePoint) -> Double {
        let lat1 = radians(a.latitude)
        let lat2 = radians(b.latitude)
        let dLat = lat2 - lat1
        let dLon = radians(b.longitude - a.longitude)
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, h.squareRoot()))
    }

    /// Compass bearing from `a` towards `b`, in degrees clockwise from north (0..<360).
    public static func bearing(from a: RoutePoint, to b: RoutePoint) -> Double {
        let lat1 = radians(a.latitude)
        let lat2 = radians(b.latitude)
        let dLon = radians(b.longitude - a.longitude)
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Metres along the polyline, point to point.
    public static func length(of points: [RoutePoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { total, leg in
            total + distance(from: leg.0, to: leg.1)
        }
    }

    /// Total climb in metres, ignoring changes smaller than `threshold` (see ``ClimbCounter``).
    public static func elevationGain(of points: [RoutePoint], threshold: Double = 5) -> Double {
        var counter = ClimbCounter(threshold: threshold)
        for elevation in points.compactMap(\.elevation) {
            counter.add(elevation)
        }
        return counter.gain
    }

    /// Whether the route finishes within `tolerance` metres of where it starts.
    public static func isLoop(_ points: [RoutePoint], tolerance: Double = 50) -> Bool {
        guard points.count > 2, let start = points.first, let finish = points.last else { return false }
        return distance(from: start, to: finish) <= tolerance
    }

    static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}

/// Counts climb, ignoring changes under `threshold` metres so elevation jitter doesn't add up.
public struct ClimbCounter: Sendable {
    public let threshold: Double
    public private(set) var gain = 0.0
    private var level: Double?

    public init(threshold: Double = 5) {
        self.threshold = threshold
    }

    public mutating func add(_ elevation: Double) {
        guard let level else {
            self.level = elevation
            return
        }
        let change = elevation - level
        if change >= threshold {
            gain += change
            self.level = elevation
        } else if change <= -threshold {
            self.level = elevation
        }
    }
}
