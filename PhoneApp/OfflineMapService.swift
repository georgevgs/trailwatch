import Foundation
import Observation
import TrailKit

/// Downloads OSM data and contours around a route for the Watch's offline map.
/// Routes already on the Watch are resent with it.
@Observable
final class OfflineMapService {
    /// Metres around the route that the map covers.
    static let margin = 600.0

    private(set) var downloading: Set<UUID> = []
    private(set) var failed: Set<UUID> = []

    private let library: RouteLibrary
    private let watch: WatchTransferService

    init(library: RouteLibrary, watch: WatchTransferService) {
        self.library = library
        self.watch = watch
    }

    func download(_ route: GPXRoute) async {
        guard !downloading.contains(route.id),
              let bounds = BoundingBox(around: route.points, margin: Self.margin)
        else { return }
        downloading.insert(route.id)
        failed.remove(route.id)
        defer { downloading.remove(route.id) }

        // Elevation tiles come from another server; fetch them in parallel.
        async let relief = Self.relief(around: bounds)
        do {
            var request = URLRequest(url: Overpass.endpoint, timeoutInterval: 120)
            request.httpMethod = "POST"
            request.setValue("TrailWatch/1.0 (iOS hiking app)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let query = Overpass.query(for: bounds).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
            request.httpBody = Data("data=\(query)".utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            var map = try await Self.read(data, bounds: bounds)
            if let relief = await relief {
                map.contourInterval = relief.contourInterval
                map.features += relief.contours
                map.shading = relief.shading
            }

            // Save onto the current copy in case it changed; skip if deleted.
            guard var latest = library.route(id: route.id) else { return }
            latest.map = map
            try library.save(latest)
            if watch.routesOnWatch.contains(latest.id) {
                watch.send(latest)
            }
        } catch {
            failed.insert(route.id)
        }
    }

    /// Contours and hill shading, or nil if the download fails. The map works without.
    @concurrent private static func relief(around bounds: BoundingBox) async -> Terrain.Relief? {
        do {
            let tiles = try await withThrowingTaskGroup(of: (TileID, Data).self) { group in
                for tile in Terrain.tiles(covering: bounds) {
                    group.addTask {
                        let (data, response) = try await URLSession.shared.data(from: Terrain.url(for: tile))
                        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                        return (tile, data)
                    }
                }
                return try await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
            }
            return try Terrain.relief(from: tiles, in: bounds)
        } catch {
            return nil
        }
    }

    /// Parsing a few hundred kilobytes of JSON stays off the main actor.
    @concurrent private static func read(_ data: Data, bounds: BoundingBox) async throws -> TrailMap {
        try Overpass.trailMap(from: data, bounds: bounds)
    }
}
