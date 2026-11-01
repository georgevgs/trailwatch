import Foundation

/// Fetches OpenStreetMap data from the Overpass API, one query per route.
public enum Overpass {
    public static let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    /// Paths, roads, water, woods and hiking landmarks inside `box`, with their shapes. Lines are
    /// cut at the box's edge to keep the download small; areas stay whole so they can be filled.
    /// Only tags and coordinates come back, not node lists.
    public static func query(for box: BoundingBox) -> String {
        let area = "\(box.south),\(box.west),\(box.north),\(box.east)"
        return """
            [out:json][timeout:90][bbox:\(area)];
            (
              way["highway"~"^(\(alternatives(Self.highways.keys)))$"];
              way["waterway"~"^(\(alternatives(Self.waterways)))$"];
            )->.lines;
            (
              way["natural"~"^(water|wood)$"];
              way["landuse"="forest"];
            )->.areas;
            (
              node["natural"~"^(peak|spring)$"];
              node["amenity"~"^(drinking_water|shelter)$"];
              node["tourism"="viewpoint"];
            )->.places;
            .lines out tags geom(\(area)) qt;
            .areas out tags geom qt;
            .places out qt;
            """
    }

    private static func alternatives(_ values: some Collection<String>) -> String {
        values.sorted().joined(separator: "|")
    }

    private static let highways: [String: TrailMap.Kind] = [
        "path": .path, "footway": .path, "steps": .path, "bridleway": .path, "cycleway": .path, "pedestrian": .path,
        "track": .track,
        "motorway": .majorRoad, "trunk": .majorRoad, "primary": .majorRoad, "secondary": .majorRoad, "tertiary": .majorRoad,
        "motorway_link": .majorRoad, "trunk_link": .majorRoad, "primary_link": .majorRoad,
        "secondary_link": .majorRoad, "tertiary_link": .majorRoad,
        "unclassified": .road, "residential": .road, "living_street": .road, "service": .road, "road": .road,
    ]

    private static let waterways: Set = ["river", "stream", "brook", "canal", "ditch", "drain"]

    /// Reads an Overpass JSON response made with `out geom`. Anything TrailWatch doesn't draw is skipped,
    /// and points within 2 m of a straight line are dropped: about half of them, unseen on a Watch.
    public static func trailMap(from data: Data, bounds: BoundingBox, downloaded: Date = .now) throws -> TrailMap {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let projection = MapProjection(origin: bounds.center)
        let features = response.elements.flatMap(features).map { feature in
            var feature = feature
            let flat = feature.points.map { projection.point(latitude: $0.latitude, longitude: $0.longitude) }
            feature.points = Isolines.simplifiedIndices(flat, tolerance: 2).map { feature.points[$0] }
            return feature
        }
        return TrailMap(bounds: bounds, features: features, downloaded: downloaded)
    }

    private static func features(_ element: Element) -> [TrailMap.Feature] {
        let tags = element.tags ?? [:]
        switch element.type {
        case "node":
            guard let latitude = element.lat, let longitude = element.lon, let kind = placeKind(tags) else { return [] }
            return [TrailMap.Feature(
                kind: kind, name: tags["name"], elevation: tags["ele"].flatMap(Double.init),
                points: [TrailMap.Point(latitude: latitude, longitude: longitude)])]
        case "way":
            guard let kind = wayKind(tags) else { return [] }
            if kind == .water || kind == .wood {
                let points = (element.geometry ?? []).compactMap { $0 }.map { TrailMap.Point(latitude: $0.lat, longitude: $0.lon) }
                // A lone area way has to close on itself; open ones are pieces of larger shapes.
                guard points.count >= 3, points.first == points.last else { return [] }
                return [TrailMap.Feature(kind: kind, name: tags["name"], points: points)]
            }
            // A line cut by the box's edge comes back with nulls where it's outside; each piece inside is drawn.
            return (element.geometry ?? [])
                .split { $0 == nil }
                .map { $0.compactMap { $0.map { TrailMap.Point(latitude: $0.lat, longitude: $0.lon) } } }
                .filter { $0.count >= 2 }
                .map { TrailMap.Feature(kind: kind, name: tags["name"], points: $0) }
        default:
            return []
        }
    }

    private static func wayKind(_ tags: [String: String]) -> TrailMap.Kind? {
        if let highway = tags["highway"] { return highways[highway] }
        if let waterway = tags["waterway"], waterways.contains(waterway) { return .stream }
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
