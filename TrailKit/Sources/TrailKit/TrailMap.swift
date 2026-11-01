import CoreGraphics
import Foundation

/// OpenStreetMap data around a route, downloaded on the iPhone and drawn on the Watch.
/// © OpenStreetMap contributors (ODbL).
public struct TrailMap: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        // Lines
        case path, track, road, majorRoad, stream
        /// A line of equal height, from Terrain Tiles; its height is in `elevation`.
        case contour
        // Areas
        case water, wood
        // Places
        case peak, spring, drinkingWater, viewpoint, shelter
    }

    public struct Feature: Codable, Sendable, Equatable {
        public var kind: Kind
        public var name: String?
        /// Metres above sea level, for peaks and contours.
        public var elevation: Double?
        /// One point for a place, several for a line or area.
        public var points: [Point]
    }

    /// A latitude and longitude, stored as a two-number array to keep the file small.
    public struct Point: Codable, Sendable, Equatable {
        public var latitude: Double
        public var longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }

        public init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            latitude = try container.decode(Double.self)
            longitude = try container.decode(Double.self)
        }

        public func encode(to encoder: any Encoder) throws {
            // Six decimals is about 10 cm, plenty for a map and half the digits of a computed contour point.
            var container = encoder.unkeyedContainer()
            try container.encode((latitude * 1e6).rounded() / 1e6)
            try container.encode((longitude * 1e6).rounded() / 1e6)
        }
    }

    /// Shaded relief drawn under the lines.
    public struct Shading: Codable, Sendable, Equatable {
        /// A PNG: black where slopes face away from the light, white where they face it, clear on the flat.
        public var image: Data
        /// The area the image covers, edge to edge.
        public var bounds: BoundingBox
    }

    public var bounds: BoundingBox
    public var features: [Feature]
    /// Metres between contour lines, when the map has them.
    public var contourInterval: Double?
    public var shading: Shading?
    public var downloaded: Date
    /// Metres around the route the map covers; nil for maps from before it was a choice (600 m).
    public var margin: Double?
}

/// A latitude/longitude rectangle.
public struct BoundingBox: Codable, Sendable, Equatable {
    public var south: Double
    public var west: Double
    public var north: Double
    public var east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    /// The smallest box around the points, grown by `margin` metres on every side.
    public init?(around points: [RoutePoint], margin: Double) {
        guard let first = points.first else { return nil }
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        let metresPerDegree = RouteCalculator.earthRadius * .pi / 180
        let latitudeMargin = margin / metresPerDegree
        let longitudeMargin = margin / (metresPerDegree * cos(RouteCalculator.radians(first.latitude)))
        self.init(
            south: latitudes.min()! - latitudeMargin, west: longitudes.min()! - longitudeMargin,
            north: latitudes.max()! + latitudeMargin, east: longitudes.max()! + longitudeMargin)
    }

    public var center: RoutePoint {
        RoutePoint(latitude: (south + north) / 2, longitude: (west + east) / 2)
    }
}

/// Flat metres around an origin, screen-style: +x east, +y south. Under 1% error over a few km.
public struct MapProjection: Sendable {
    public let origin: RoutePoint
    private let metresPerDegree = RouteCalculator.earthRadius * .pi / 180
    private let metresPerLongitude: Double

    public init(origin: RoutePoint) {
        self.origin = origin
        metresPerLongitude = metresPerDegree * cos(RouteCalculator.radians(origin.latitude))
    }

    public func point(latitude: Double, longitude: Double) -> CGPoint {
        CGPoint(
            x: (longitude - origin.longitude) * metresPerLongitude,
            y: (origin.latitude - latitude) * metresPerDegree)
    }

    public func point(_ routePoint: RoutePoint) -> CGPoint {
        point(latitude: routePoint.latitude, longitude: routePoint.longitude)
    }
}

/// Where to write a contour's height along it, in flat map metres (+y south).
public struct ContourLabel: Sendable, Equatable {
    public var point: CGPoint
    /// Radians to turn the text to follow the line, never more than a quarter turn so it reads upright.
    public var angle: Double
    /// Counting along the line, so a zoomed-out map can show every second or third.
    public var index: Int

    /// Labels every `spacing` metres, starting half a spacing in. Contours run with higher ground on
    /// their left, so the text's top faces uphill unless that would leave it upside down.
    public static func along(_ line: [CGPoint], every spacing: Double) -> [ContourLabel] {
        var labels: [ContourLabel] = []
        var next = spacing / 2
        var travelled = 0.0
        for (a, b) in zip(line, line.dropFirst()) {
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0 else { continue }
            while next <= travelled + length {
                let t = (next - travelled) / length
                var angle = atan2(b.y - a.y, b.x - a.x)
                if angle > .pi / 2 { angle -= .pi } else if angle < -.pi / 2 { angle += .pi }
                labels.append(ContourLabel(
                    point: CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), angle: angle, index: labels.count))
                next += spacing
            }
            travelled += length
        }
        return labels
    }
}
