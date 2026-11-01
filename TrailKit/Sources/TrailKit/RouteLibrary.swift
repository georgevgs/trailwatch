import Foundation
import Observation

/// The routes saved on this device, kept in one JSON file. Newest first.
///
/// With a maps folder (the Watch), each offline map is kept compressed in its own file and read
/// only when a hike needs it, so launching doesn't load every map.
@MainActor @Observable
public final class RouteLibrary {
    public private(set) var routes: [GPXRoute] = []
    /// Called after every save or delete.
    @ObservationIgnored public var onChange: (() -> Void)?
    private let fileURL: URL
    private let mapsDirectory: URL?
    /// Routes whose map is in the maps folder.
    private var storedMaps: Set<UUID> = []

    public init(
        fileURL: URL = URL.applicationSupportDirectory.appending(path: "routes.json"), mapsDirectory: URL? = nil
    ) {
        self.fileURL = fileURL
        self.mapsDirectory = mapsDirectory
        if let data = try? Data(contentsOf: fileURL) {
            routes = (try? JSONDecoder().decode([GPXRoute].self, from: data)) ?? []
        }
        guard let mapsDirectory else { return }
        storedMaps = Set(routes.map(\.id).filter { FileManager.default.fileExists(atPath: mapURL($0, in: mapsDirectory).path) })
        // Maps saved inside routes.json before they had their own files.
        if routes.contains(where: { $0.map != nil }) {
            for index in routes.indices where routes[index].map != nil {
                if (try? storeMap(of: routes[index])) != nil { routes[index].map = nil }
            }
            try? write()
        }
    }

    public func route(id: UUID) -> GPXRoute? {
        routes.first { $0.id == id }
    }

    /// The route has an offline map, kept with it or in the maps folder.
    public func hasMap(_ id: UUID) -> Bool {
        storedMaps.contains(id) || route(id: id)?.map != nil
    }

    /// The route's offline map, read from the maps folder when it's kept there.
    public func map(for id: UUID) -> TrailMap? {
        if let map = route(id: id)?.map { return map }
        guard let mapsDirectory, storedMaps.contains(id),
              let data = try? Data(contentsOf: mapURL(id, in: mapsDirectory))
        else { return nil }
        return try? RouteFile.decode(TrailMap.self, from: data)
    }

    /// Adds the route, or replaces the one with the same ID. A route sent without a map keeps the one stored.
    public func save(_ route: GPXRoute) throws {
        var route = route
        if mapsDirectory != nil, route.map != nil {
            try storeMap(of: route)
            route.map = nil
        }
        if let index = routes.firstIndex(where: { $0.id == route.id }) {
            routes[index] = route
        } else {
            routes.insert(route, at: 0)
        }
        try write()
    }

    public func delete(id: UUID) throws {
        routes.removeAll { $0.id == id }
        if let mapsDirectory, storedMaps.remove(id) != nil {
            try? FileManager.default.removeItem(at: mapURL(id, in: mapsDirectory))
        }
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

    private func storeMap(of route: GPXRoute) throws {
        guard let mapsDirectory, let map = route.map else { return }
        try FileManager.default.createDirectory(at: mapsDirectory, withIntermediateDirectories: true)
        try RouteFile.encode(map).write(to: mapURL(route.id, in: mapsDirectory), options: .atomic)
        storedMaps.insert(route.id)
    }

    private func mapURL(_ id: UUID, in directory: URL) -> URL {
        directory.appending(path: "\(id.uuidString).map")
    }

    private func write() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(routes).write(to: fileURL, options: .atomic)
        onChange?()
    }
}

/// JSON compressed with LZFSE, for routes sent to the Watch and maps stored on it: about a quarter of the size.
public enum RouteFile {
    public static func encode(_ value: some Encodable) throws -> Data {
        try (JSONEncoder().encode(value) as NSData).compressed(using: .lzfse) as Data
    }

    /// Reads compressed or plain JSON, so files from before compression still open.
    public static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        if let plain = try? (data as NSData).decompressed(using: .lzfse) as Data,
           let value = try? JSONDecoder().decode(type, from: plain) {
            return value
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

/// Keys shared by the iPhone and Watch apps for WatchConnectivity.
public enum WatchTransfer {
    /// File metadata: the ID of the route in a transferred file.
    public static let routeIDKey = "routeID"
    /// Application context from the Watch: the IDs of the routes it has.
    public static let routeIDsKey = "routeIDs"
    /// Application context from the Watch: your pace on past hikes, for the iPhone's estimates.
    public static let paceFactorsKey = "paceFactors"
}
