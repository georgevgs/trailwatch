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
}
