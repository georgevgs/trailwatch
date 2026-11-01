import Foundation

/// Fetches OpenStreetMap data from the Overpass API, one query per route.
public enum Overpass {
    public static let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    /// Paths, roads, water, woods and hiking landmarks inside `box`, with their shapes.
    public static func query(for box: BoundingBox) -> String {
        let area = "(\(box.south),\(box.west),\(box.north),\(box.east))"
        return """
            [out:json][timeout:60];
            (
              way["highway"]\(area);
              way["waterway"]\(area);
              way["natural"="water"]\(area);
              way["natural"="wood"]\(area);
              way["landuse"="forest"]\(area);
              node["natural"~"^(peak|spring)$"]\(area);
              node["amenity"~"^(drinking_water|shelter)$"]\(area);
              node["tourism"="viewpoint"]\(area);
            );
            out geom qt;
            """
    }

    /// Reads an Overpass JSON response made with `out geom`. Anything TrailWatch doesn't draw is skipped.
    public static func trailMap(from data: Data, bounds: BoundingBox, downloaded: Date = .now) throws -> TrailMap {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let features = response.elements.compactMap(feature)
        return TrailMap(bounds: bounds, features: features, downloaded: downloaded)
    }

    private static func feature(_ element: Element) -> TrailMap.Feature? {
        let tags = element.tags ?? [:]
        switch element.type {
        case "node":
            guard let latitude = element.lat, let longitude = element.lon, let kind = placeKind(tags) else { return nil }
            return TrailMap.Feature(
                kind: kind, name: tags["name"], elevation: tags["ele"].flatMap(Double.init),
                points: [TrailMap.Point(latitude: latitude, longitude: longitude)])
        case "way":
            let points = (element.geometry ?? []).compactMap { $0 }.map {
                TrailMap.Point(latitude: $0.lat, longitude: $0.lon)
            }
            guard points.count >= 2, let kind = wayKind(tags) else { return nil }
            // A lone area way has to close on itself; open ones are pieces of larger shapes.
            if kind == .water || kind == .wood, points.first != points.last { return nil }
            return TrailMap.Feature(kind: kind, name: tags["name"], points: points)
        default:
            return nil
        }
    }

    private static func wayKind(_ tags: [String: String]) -> TrailMap.Kind? {
        if let highway = tags["highway"] {
            switch highway {
            case "path", "footway", "steps", "bridleway", "cycleway", "pedestrian": return .path
            case "track": return .track
            case "motorway", "trunk", "primary", "secondary", "tertiary",
                 "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link": return .majorRoad
            case "unclassified", "residential", "living_street", "service", "road": return .road
            default: return nil
            }
        }
        if let waterway = tags["waterway"], ["river", "stream", "brook", "canal", "ditch", "drain"].contains(waterway) {
            return .stream
        }
        if tags["natural"] == "water" { return .water }
        if tags["natural"] == "wood" || tags["landuse"] == "forest" { return .wood }
        return nil
    }

    private static func placeKind(_ tags: [String: String]) -> TrailMap.Kind? {
        switch (tags["natural"], tags["amenity"], tags["tourism"]) {
        case ("peak", _, _): .peak
        case ("spring", _, _): .spring
        case (_, "drinking_water", _): .drinkingWater
        case (_, "shelter", _): .shelter
        case (_, _, "viewpoint"): .viewpoint
        default: nil
        }
    }

    private struct Response: Decodable {
        let elements: [Element]
    }

    private struct Element: Decodable {
        let type: String
        let lat: Double?
        let lon: Double?
        /// Way shapes; a null stands for a node Overpass left out.
        let geometry: [Coordinate?]?
        let tags: [String: String]?
    }

    private struct Coordinate: Decodable {
        let lat: Double
        let lon: Double
    }
}
