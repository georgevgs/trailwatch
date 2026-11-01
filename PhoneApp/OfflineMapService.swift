import Foundation
import Observation
import TrailKit

/// Downloads OSM data and contours around a route for the Watch's offline map.
/// Routes already on the Watch are resent with it.
@Observable
final class OfflineMapService {
    /// Metres around the route the map can cover; more means a bigger download and file on the Watch.
    static let margins = [600.0, 1500, 3000]
    static let marginKey = "mapMargin"
    static let defaultMargin = 1500.0

    /// The area chosen for new downloads.
    static var margin: Double {
        let saved = UserDefaults.standard.double(forKey: marginKey)
        return margins.contains(saved) ? saved : defaultMargin
    }

    private(set) var downloading: Set<UUID> = []
    private(set) var failed: Set<UUID> = []

    private let library: RouteLibrary
    private let watch: WatchTransferService

    init(library: RouteLibrary, watch: WatchTransferService) {
        self.library = library
        self.watch = watch
    }

    /// Downloads the map. Call it from a tap: it keeps going if you leave the app.
    func download(_ route: GPXRoute) async {
        let margin = Self.margin
        guard !downloading.contains(route.id),
              let bounds = BoundingBox(around: route.points, margin: margin)
        else { return }
        downloading.insert(route.id)
        failed.remove(route.id)
        defer { downloading.remove(route.id) }

        // Map data, contours, saving and sending.
        let work = ContinuedWork(title: "Offline map", subtitle: route.name, steps: 3)
        var succeeded = false
        defer { work.finish(success: succeeded) }

        // Elevation tiles come from another server; fetch them in parallel.
        async let relief = Self.relief(around: bounds)
        do {
            let data = try await Self.overpass(Overpass.query(for: bounds))
            work.advance()
            var map = try await Self.read(data, bounds: bounds)
            map.margin = margin
            if let relief = await relief {
                map.contourInterval = relief.contourInterval
                map.features += relief.contours
                map.shading = relief.shading
            }
            work.advance()

            // Save onto the current copy in case it changed; skip if deleted.
            guard var latest = library.route(id: route.id) else { return }
            latest.map = map
            try library.save(latest)
            if watch.routesOnWatch.contains(latest.id) {
                watch.send(latest)
            }
            work.advance()
            succeeded = true
        } catch {
            failed.insert(route.id)
        }
    }

    /// Runs an Overpass query. A busy server gets one more try after 30 s, as its usage policy asks.
    private static func overpass(_ query: String) async throws -> Data {
        var request = URLRequest(url: Overpass.endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("TrailWatch/1.0 (iOS hiking app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")".utf8)

        for attempt in 1...2 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode
            if status == 200 { return data }
            // 429 and 406: too many requests; 504: no free slot in time.
            guard attempt == 1, [429, 406, 504].contains(status) else { break }
            try await Task.sleep(for: .seconds(30))
        }
        throw URLError(.badServerResponse)
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
