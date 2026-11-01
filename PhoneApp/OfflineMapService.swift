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
    /// When each running download began, to show how long it's been waiting.
    private(set) var started: [UUID: Date] = [:]

    private let library: RouteLibrary
    private let watch: WatchTransferService
    /// The latest Overpass request; the next waits for it, as the usage policy forbids parallel ones.
    private var lastQuery: Task<Data, any Error>?

    /// Downloads not yet finished, kept across launches so they resume if the app was closed.
    private static let pendingKey = "pendingMapDownloads"
    private var pending: Set<UUID> {
        get { Set((UserDefaults.standard.stringArray(forKey: Self.pendingKey) ?? []).compactMap(UUID.init)) }
        set { UserDefaults.standard.set(newValue.map(\.uuidString), forKey: Self.pendingKey) }
    }

    init(library: RouteLibrary, watch: WatchTransferService) {
        self.library = library
        self.watch = watch
    }

    /// Picks up what's left when the app opens: downloads that failed or were cut short, then
    /// contours on maps made in an older format.
    func catchUp() async {
        for id in pending.subtracting(downloading) {
            if let route = library.route(id: id) {
                await download(route, keepsGoingInBackground: false)
            } else {
                pending.remove(id)
            }
        }
        for route in library.routes where route.map?.isOutdated == true && !downloading.contains(route.id) {
            await updateContours(route)
        }
    }

    /// Downloads the map. From a tap it keeps going if you leave the app; Apple allows that only
    /// for work someone started.
    func download(_ route: GPXRoute, keepsGoingInBackground: Bool = true) async {
        let margin = Self.margin
        guard !downloading.contains(route.id),
              let bounds = BoundingBox(around: route.points, margin: margin)
        else { return }
        downloading.insert(route.id)
        started[route.id] = .now
        pending.insert(route.id)
        failed.remove(route.id)
        defer {
            downloading.remove(route.id)
            started[route.id] = nil
        }

        // Map data, contours, saving and sending.
        let work = keepsGoingInBackground ? ContinuedWork(title: "Offline map", subtitle: route.name, steps: 3) : nil
        var succeeded = false
        defer { work?.finish(success: succeeded) }

        // Elevation tiles come from another server; fetch them in parallel.
        async let relief = Self.relief(around: bounds)
        do {
            let data = try await query(Overpass.query(for: bounds))
            work?.advance()
            var map = try await Self.read(data, bounds: bounds)
            map.margin = margin
            map.version = TrailMap.currentVersion
            if let relief = await relief {
                map.contourInterval = relief.contourInterval
                map.features += relief.contours
                map.shading = relief.shading
            }
            work?.advance()

            // Save onto the current copy in case it changed; skip if deleted.
            pending.remove(route.id)
            guard var latest = library.route(id: route.id) else { return }
            latest.map = map
            try library.save(latest)
            if watch.routesOnWatch.contains(latest.id) {
                watch.send(latest)
            }
            work?.advance()
            succeeded = true
        } catch {
            failed.insert(route.id)
        }
    }

    /// Rebuilds an old map's contours and shading from the elevation tiles alone: a few seconds, no Overpass.
    private func updateContours(_ route: GPXRoute) async {
        guard var map = route.map else { return }
        downloading.insert(route.id)
        defer { downloading.remove(route.id) }
        guard let relief = await Self.relief(around: map.bounds) else { return }
        map.features = map.features.filter { $0.kind != .contour } + relief.contours
        map.contourInterval = relief.contourInterval
        map.shading = relief.shading
        map.version = TrailMap.currentVersion
        guard var latest = library.route(id: route.id), latest.map?.isOutdated == true else { return }
        latest.map = map
        try? library.save(latest)
        if watch.routesOnWatch.contains(latest.id) {
            watch.send(latest)
        }
    }

    /// Queues an Overpass query behind any already running.
    private func query(_ query: String) async throws -> Data {
        let previous = lastQuery
        let task = Task {
            _ = try? await previous?.value
            return try await Self.overpass(query)
        }
        lastQuery = task
        return try await task.value
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
