import CoreGraphics
import Foundation

/// OpenStreetMap data around a route: paths, roads, water, woods and hiking landmarks. Downloaded on
/// the iPhone with the route and drawn on the Watch, so the map works with no signal.
/// Map data © OpenStreetMap contributors (ODbL).
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
            var container = encoder.unkeyedContainer()
            try container.encode(latitude)
            try container.encode(longitude)
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

/// Flat metres around an origin, laid out like a screen: east is +x, south is +y. Accurate to well
/// under 1% across the few kilometres around a route.
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
