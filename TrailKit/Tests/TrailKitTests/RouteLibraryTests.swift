import Foundation
import Testing
@testable import TrailKit

@MainActor
struct RouteLibraryTests {
    private let file = URL.temporaryDirectory.appending(path: "RouteLibraryTests-\(UUID().uuidString)/routes.json")

    @Test func keepsRoutesAcrossLaunches() throws {
        let route = GPXRoute(name: "Hymettus", points: [RoutePoint(latitude: 1, longitude: 1), RoutePoint(latitude: 2, longitude: 2)])
        try RouteLibrary(fileURL: file).save(route)

        let reopened = RouteLibrary(fileURL: file)

        #expect(reopened.routes.map(\.id) == [route.id])
        #expect(reopened.route(id: route.id)?.distance == route.distance)
    }

    @Test func savingTheSameRouteAgainReplacesIt() throws {
        let library = RouteLibrary(fileURL: file)
        var route = GPXRoute(name: "Old", points: [RoutePoint(latitude: 1, longitude: 1), RoutePoint(latitude: 2, longitude: 2)])
        try library.save(route)

        route.name = "New"
        try library.save(route)

        #expect(library.routes.map(\.name) == ["New"])
    }

    @Test func putsNewRoutesFirstAndDeletes() throws {
        let library = RouteLibrary(fileURL: file)
        let first = GPXRoute(name: "First", points: [])
        let second = GPXRoute(name: "Second", points: [])
        try library.save(first)
        try library.save(second)
        #expect(library.routes.map(\.name) == ["Second", "First"])

        try library.delete(id: second.id)

        #expect(RouteLibrary(fileURL: file).routes.map(\.name) == ["First"])
    }

    @Test func reordersAndRemembersTheOrder() throws {
        let library = RouteLibrary(fileURL: file)
        let routes = ["C", "B", "A"].map { GPXRoute(name: $0, points: []) }
        for route in routes { try library.save(route) }
        #expect(library.routes.map(\.name) == ["A", "B", "C"])

        try library.move([routes[0].id], before: routes[2].id)
        #expect(library.routes.map(\.name) == ["C", "A", "B"])

        try library.move([routes[0].id, routes[2].id], before: nil)
        #expect(RouteLibrary(fileURL: file).routes.map(\.name) == ["B", "C", "A"])
    }

    @Test func keepsMapsInTheirOwnFilesWhenAsked() throws {
        let maps = file.deletingLastPathComponent().appending(path: "Maps")
        let map = TrailMap(
            bounds: BoundingBox(south: 1, west: 1, north: 2, east: 2),
            features: [TrailMap.Feature(kind: .spring, points: [TrailMap.Point(latitude: 1.5, longitude: 1.5)])],
            downloaded: Date(timeIntervalSince1970: 0))
        var route = GPXRoute(name: "Mapped", points: [RoutePoint(latitude: 1, longitude: 1), RoutePoint(latitude: 2, longitude: 2)])
        route.map = map
        let library = RouteLibrary(fileURL: file, mapsDirectory: maps)
        try library.save(route)

        // Out of memory and routes.json, but still there when a hike asks.
        #expect(library.route(id: route.id)?.map == nil)
        let reopened = RouteLibrary(fileURL: file, mapsDirectory: maps)
        #expect(reopened.hasMap(route.id))
        #expect(reopened.map(for: route.id) == map)

        // Sent again without a map, it keeps the one stored.
        route.map = nil
        try reopened.save(route)
        #expect(reopened.map(for: route.id) == map)

        try reopened.delete(id: route.id)
        #expect(!reopened.hasMap(route.id))
        #expect(try FileManager.default.contentsOfDirectory(atPath: maps.path).isEmpty)
    }

    @Test func movesMapsOutOfOldRouteFiles() throws {
        var route = GPXRoute(name: "Old", points: [RoutePoint(latitude: 1, longitude: 1), RoutePoint(latitude: 2, longitude: 2)])
        route.map = TrailMap(bounds: BoundingBox(south: 1, west: 1, north: 2, east: 2), features: [], downloaded: .now)
        try RouteLibrary(fileURL: file).save(route)

        let library = RouteLibrary(fileURL: file, mapsDirectory: file.deletingLastPathComponent().appending(path: "Maps"))

        #expect(library.route(id: route.id)?.map == nil)
        #expect(library.map(for: route.id) != nil)
    }

    @Test func routeFilesAreCompressedAndOldOnesStillOpen() throws {
        let route = GPXRoute(name: "Long", points: (0..<500).map { RoutePoint(latitude: Double($0) * 0.001, longitude: 23.8) })
        let plain = try JSONEncoder().encode(route)
        let compressed = try RouteFile.encode(route)

        #expect(compressed.count < plain.count / 2)
        #expect(try RouteFile.decode(GPXRoute.self, from: compressed).id == route.id)
        #expect(try RouteFile.decode(GPXRoute.self, from: plain).id == route.id)
    }
}
