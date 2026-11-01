import Foundation
import Testing
@testable import TrailKit

struct NavigationTests {
    /// About 1.1 km due north from the equator, with a spring halfway and a hut off to the side.
    let route = GPXRoute(
        name: "North",
        points: [
            RoutePoint(latitude: 0, longitude: 0, elevation: 100),
            RoutePoint(latitude: 0.005, longitude: 0, elevation: 200),
            RoutePoint(latitude: 0.01, longitude: 0, elevation: 150),
        ],
        waypoints: [
            Waypoint(point: RoutePoint(latitude: 0.0050, longitude: 0.0002), name: "Spring"),
            Waypoint(point: RoutePoint(latitude: 0.0090, longitude: 0.0001), name: "Hut"),
            Waypoint(point: RoutePoint(latitude: 0.0050, longitude: 0.02), name: "Far away"),
        ])

    @Test func readsWaypoints() throws {
        let data = Data("""
            <?xml version="1.0"?>
            <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
              <wpt lat="9" lon="9"><ele>812</ele><name>Spring</name></wpt>
              <wpt lat="8" lon="8"/>
              <trk><trkseg><trkpt lat="1" lon="1"/><trkpt lat="2" lon="2"/></trkseg></trk>
            </gpx>
            """.utf8)
        let route = try GPXParser.parse(data)

        #expect(route.waypoints == [
            Waypoint(point: RoutePoint(latitude: 9, longitude: 9, elevation: 812), name: "Spring"),
            Waypoint(point: RoutePoint(latitude: 8, longitude: 8), name: "Waypoint"),
        ])
        #expect(route.points.count == 2)
    }

    @Test func readsRoutesSavedBeforeWaypoints() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(route)) as! [String: Any]
        json["waypoints"] = nil
        let decoded = try JSONDecoder().decode(GPXRoute.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.waypoints.isEmpty)
        #expect(decoded.points == route.points)
    }

    @Test func reversesTheRouteAndItsClimb() {
        let reversed = route.reversed()
        #expect(reversed.id == route.id)
        #expect(reversed.points.first == route.points.last)
        #expect(reversed.distance == route.distance)
        #expect(route.elevationGain == 100)
        #expect(reversed.elevationGain == 50)
        #expect(reversed.waypoints == route.waypoints)
    }

    @Test func placesNearbyWaypointsAlongTheRoute() {
        let stops = RouteTracker(route: route).stops(within: 150)
        #expect(stops.map(\.waypoint.name) == ["Spring", "Hut"])
        #expect(abs(stops[0].distanceAlong - 556) < 2)

        let backwards = RouteTracker(route: route.reversed()).stops(within: 150)
        #expect(backwards.map(\.waypoint.name) == ["Hut", "Spring"])
    }

    @Test func alertsOnceForEachWaypointReached() {
        var alerts = WaypointAlerts(radius: 40)
        let nearSpring = RoutePoint(latitude: 0.0050, longitude: 0)

        #expect(alerts.update(at: route.points[0], accuracy: 5, waypoints: route.waypoints) == nil)
        #expect(alerts.update(at: nearSpring, accuracy: 60, waypoints: route.waypoints) == nil)
        #expect(alerts.update(at: nearSpring, accuracy: 5, waypoints: route.waypoints)?.name == "Spring")
        #expect(alerts.update(at: nearSpring, accuracy: 5, waypoints: route.waypoints) == nil)
    }

    @Test func readsTheProfileExpiryDate() {
        let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict>
              <key>ExpirationDate</key><date>2026-11-08T14:16:20Z</date>
            </dict></plist>
            """
        let profile = Data([0x30, 0x82, 0x01]) + Data(plist.utf8) + Data([0xA0, 0x00])
        #expect(ProvisioningProfile.expirationDate(in: profile) == Date(timeIntervalSince1970: 1_794_147_380))
        #expect(ProvisioningProfile.expirationDate(in: Data("not a profile".utf8)) == nil)
    }
}
