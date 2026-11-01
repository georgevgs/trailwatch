import Foundation
import Observation

/// The routes saved on this device, kept in one JSON file. Newest first.
@MainActor @Observable
public final class RouteLibrary {
    public private(set) var routes: [GPXRoute] = []
    /// Called after every save or delete.
    @ObservationIgnored public var onChange: (() -> Void)?
    private let fileURL: URL

    public init(fileURL: URL = URL.applicationSupportDirectory.appending(path: "routes.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL) {
            routes = (try? JSONDecoder().decode([GPXRoute].self, from: data)) ?? []
        }
    }

    public func route(id: UUID) -> GPXRoute? {
        routes.first { $0.id == id }
    }

    /// Adds the route, or replaces the one with the same ID.
    public func save(_ route: GPXRoute) throws {
        if let index = routes.firstIndex(where: { $0.id == route.id }) {
            routes[index] = route
        } else {
            routes.insert(route, at: 0)
        }
        try write()
    }

    public func delete(id: UUID) throws {
        routes.removeAll { $0.id == id }
        try write()
    }

    /// Moves routes, in their current order, to just before `target`, or to the end when it's nil.
    public func move(_ ids: [UUID], before target: UUID?) throws {
        let moving = routes.filter { ids.contains($0.id) }
        routes.removeAll { ids.contains($0.id) }
        let index = target.flatMap { target in routes.firstIndex { $0.id == target } } ?? routes.endIndex
        routes.insert(contentsOf: moving, at: index)
        try write()
    }

    private func write() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(routes).write(to: fileURL, options: .atomic)
        onChange?()
    }
}

/// Keys shared by the iPhone and Watch apps for WatchConnectivity.
public enum WatchTransfer {
    /// File metadata: the ID of the route in a transferred file.
    public static let routeIDKey = "routeID"
    /// Application context from the Watch: the IDs of the routes it has.
    public static let routeIDsKey = "routeIDs"
}
