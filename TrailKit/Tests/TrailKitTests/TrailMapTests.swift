import Foundation
import Testing
@testable import TrailKit

struct TrailMapTests {
    private let box = BoundingBox(south: 37.95, west: 23.78, north: 37.97, east: 23.81)

    @Test func readsOverpassWaysAndPlaces() throws {
        let map = try Overpass.trailMap(from: Data(sample.utf8), bounds: box)

        #expect(map.features.map(\.kind) == [.path, .path, .road, .stream, .wood, .peak, .spring])
        #expect(map.features[0].name == "Kaisariani trail")
        // Cut where the path leaves the box and comes back.
        #expect(map.features[0].points == [
            TrailMap.Point(latitude: 37.960, longitude: 23.790), TrailMap.Point(latitude: 37.961, longitude: 23.791),
        ])
        #expect(map.features[1].points == [
            TrailMap.Point(latitude: 37.962, longitude: 23.792), TrailMap.Point(latitude: 37.963, longitude: 23.793),
        ])
        #expect(map.features[5].elevation == 1026)
        #expect(map.bounds == box)
    }

    @Test func skipsWhatItDoesntDraw() throws {
        let map = try Overpass.trailMap(from: Data(sample.utf8), bounds: box)

        // The bus stop, the construction road, the open wood way and the one-node path are left out.
        #expect(map.features.count == 7)
    }

    @Test func storesPointsCompactly() throws {
        let feature = TrailMap.Feature(kind: .spring, points: [TrailMap.Point(latitude: 37.96, longitude: 23.8)])

        let json = String(decoding: try JSONEncoder().encode(feature), as: UTF8.self)

        #expect(json.contains(#""points":[[37.96,23.8]]"#))
        #expect(try JSONDecoder().decode(TrailMap.Feature.self, from: Data(json.utf8)) == feature)
    }

    @Test func routesSavedBeforeMapsStillLoad() throws {
        let route = GPXRoute(name: "Old", points: [RoutePoint(latitude: 1, longitude: 1), RoutePoint(latitude: 2, longitude: 2)])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(route)) as! [String: Any]
        json.removeValue(forKey: "map")

        let decoded = try JSONDecoder().decode(GPXRoute.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(decoded.map == nil)
        #expect(decoded.name == "Old")
    }

    @Test func boxGrowsByTheMarginInMetres() throws {
        let points = [RoutePoint(latitude: 38, longitude: 23), RoutePoint(latitude: 38.01, longitude: 23.02)]
        let box = try #require(BoundingBox(around: points, margin: 600))
        let projection = MapProjection(origin: RoutePoint(latitude: 38, longitude: 23))

        let southwest = projection.point(latitude: box.south, longitude: box.west)
        #expect(abs(southwest.x + 600) < 0.5)
        #expect(abs(southwest.y - 600) < 0.5)
        #expect(abs(box.north - 38.01 - 600 / 111_195) < 1e-7)
    }

    @Test func projectionMatchesGreatCircleDistances() {
        let projection = MapProjection(origin: RoutePoint(latitude: 37.96, longitude: 23.79))
        let a = RoutePoint(latitude: 37.9643257, longitude: 23.7906644)
        let b = RoutePoint(latitude: 37.9588737, longitude: 23.8045641)

        let pa = projection.point(a), pb = projection.point(b)
        let flat = hypot(pa.x - pb.x, pa.y - pb.y)

        #expect(abs(flat - RouteCalculator.distance(from: a, to: b)) / flat < 0.001)
        #expect(pb.x > pa.x && pb.y > pa.y)  // b is east and south of a
    }

    @Test func contourLabelsAreSpacedAlongTheLineAndUpright() {
        // 1 km heading west, then 500 m north.
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: -1000, y: 0), CGPoint(x: -1000, y: -500)]
        let labels = ContourLabel.along(line, every: 400)

        #expect(labels.map(\.point) == [CGPoint(x: -200, y: 0), CGPoint(x: -600, y: 0), CGPoint(x: -1000, y: 0), CGPoint(x: -1000, y: -400)])
        #expect(labels.map(\.index) == [0, 1, 2, 3])
        // Westward text would be upside down, so it's turned to read left to right.
        #expect(abs(labels[0].angle) < 1e-9)
        #expect(abs(labels[3].angle + .pi / 2) < 1e-9)
        #expect(ContourLabel.along(line, every: 4000).isEmpty)
    }

    @Test func queryCoversTheBox() {
        let query = Overpass.query(for: box)

        #expect(query.contains("[bbox:37.95,23.78,37.97,23.81]"))
        #expect(query.hasPrefix("[out:json]"))
        #expect(query.contains(".lines out tags geom(37.95,23.78,37.97,23.81) qt;"))
        #expect(query.contains(#"way["highway"~"^(bridleway|cycleway|footway|"#))
        #expect(!query.contains("construction"))
    }

    private let sample = """
        {"elements": [
          {"type": "way", "id": 1, "tags": {"highway": "path", "name": "Kaisariani trail"},
           "geometry": [null, {"lat": 37.960, "lon": 23.790}, {"lat": 37.961, "lon": 23.791}, null, null,
                        {"lat": 37.962, "lon": 23.792}, {"lat": 37.963, "lon": 23.793}, null]},
          {"type": "way", "id": 2, "tags": {"highway": "residential"},
           "geometry": [{"lat": 37.962, "lon": 23.790}, {"lat": 37.963, "lon": 23.792}]},
          {"type": "way", "id": 3, "tags": {"highway": "construction"},
           "geometry": [{"lat": 37.962, "lon": 23.790}, {"lat": 37.963, "lon": 23.792}]},
          {"type": "way", "id": 4, "tags": {"waterway": "stream"},
           "geometry": [{"lat": 37.955, "lon": 23.800}, {"lat": 37.956, "lon": 23.801}]},
          {"type": "way", "id": 5, "tags": {"landuse": "forest"},
           "geometry": [{"lat": 37.95, "lon": 23.80}, {"lat": 37.96, "lon": 23.80}, {"lat": 37.96, "lon": 23.81}, {"lat": 37.95, "lon": 23.80}]},
          {"type": "way", "id": 6, "tags": {"natural": "wood"},
           "geometry": [{"lat": 37.95, "lon": 23.80}, {"lat": 37.96, "lon": 23.80}]},
          {"type": "way", "id": 7, "tags": {"highway": "footway"}, "geometry": [{"lat": 37.95, "lon": 23.80}]},
          {"type": "node", "id": 8, "lat": 37.952, "lon": 23.805, "tags": {"natural": "peak", "name": "Evzonas", "ele": "1026"}},
          {"type": "node", "id": 9, "lat": 37.957, "lon": 23.797, "tags": {"natural": "spring"}},
          {"type": "node", "id": 10, "lat": 37.958, "lon": 23.796, "tags": {"highway": "bus_stop"}}
        ]}
        """
}
