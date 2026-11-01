import Foundation
import Testing
@testable import TrailKit

struct RouteTrackerTests {
    /// 0.001° of latitude is 111.2 m.
    private let step = 111.195

    @Test func measuresProgressAndDistanceFromTheRoute() throws {
        var tracker = RouteTracker(route: route([(0, 0), (0.001, 0), (0.002, 0)]))

        let update = tracker.update(with: RoutePoint(latitude: 0.0015, longitude: 0.0001))
        let position = try #require(update)

        #expect(abs(position.distanceAlong - 1.5 * step) < 0.5)
        #expect(abs(position.distanceFromRoute - 11.1) < 0.2)
        #expect(abs(position.nearestPoint.latitude - 0.0015) < 1e-9)
        #expect(abs(tracker.distanceRemaining - 0.5 * step) < 0.5)
    }

    @Test func aLoopStartsAtTheBeginningAndFinishesAtTheEnd() {
        // A square loop, about 445 m round.
        let square = [(0.0, 0.0), (0.001, 0), (0.001, 0.001), (0, 0.001), (0, 0)]
        var tracker = RouteTracker(route: route(square))

        // Standing at the trailhead, which is both start and finish: progress is zero, not the whole loop.
        tracker.update(with: RoutePoint(latitude: 0.00001, longitude: 0))
        #expect(tracker.distanceAlong < 2)

        for (latitude, longitude) in [(0.0005, 0.0), (0.001, 0.0005), (0.0005, 0.001), (0, 0.0005), (0, 0.0001)] {
            tracker.update(with: RoutePoint(latitude: latitude, longitude: longitude))
        }
        #expect(tracker.distanceRemaining < 12)
    }

    @Test func anOutAndBackKeepsCountingOnTheWayBack() {
        var tracker = RouteTracker(route: route([(0, 0), (0.002, 0), (0, 0)]))

        for latitude in [0.0005, 0.001, 0.0015, 0.002, 0.0019, 0.0015] {
            tracker.update(with: RoutePoint(latitude: latitude, longitude: 0))
        }

        // 2 steps out, then 0.5 back: not 1.5 steps out.
        #expect(abs(tracker.distanceAlong - 2.5 * step) < 0.5)
    }

    @Test func followsTheKaisarianiLoopAllTheWayRound() throws {
        let url = try #require(Bundle.module.url(
            forResource: "kaisariani_megalos_kyklos", withExtension: "gpx", subdirectory: "Fixtures"))
        let route = try GPXParser.parse(Data(contentsOf: url))
        var tracker = RouteTracker(route: route)

        var progress: [Double] = []
        for point in route.points {
            tracker.update(with: point)
            progress.append(tracker.distanceAlong)
        }

        #expect(zip(progress, progress.dropFirst()).allSatisfy { $0 <= $1 + 0.01 })
        #expect(abs(progress.last! - route.distance) < 1)
    }

    @Test func walkingBackAlongTheTrailReducesProgress() {
        var tracker = RouteTracker(route: route([(0, 0), (0.001, 0), (0.002, 0)]))

        tracker.update(with: RoutePoint(latitude: 0.0015, longitude: 0))
        tracker.update(with: RoutePoint(latitude: 0.001, longitude: 0))

        #expect(abs(tracker.distanceAlong - step) < 0.5)
    }

    @Test func splitsTheRouteWherePositionIs() {
        let tracker = RouteTracker(route: route([(0, 0), (0.001, 0), (0.002, 0)]))

        let (walked, ahead) = tracker.split(at: 1.5 * step)

        #expect(walked.map(\.latitude).count == 3)
        #expect(abs(walked.last!.latitude - 0.0015) < 1e-7)
        #expect(ahead.first == walked.last)
        #expect(ahead.last?.latitude == 0.002)
    }

    @Test func splitClampsToTheRoute() {
        let tracker = RouteTracker(route: route([(0, 0), (0.001, 0)]))

        #expect(tracker.split(at: -10).walked.count == 2)
        #expect(tracker.split(at: 10_000).ahead.allSatisfy { $0.latitude == 0.001 })
    }

    private func route(_ coordinates: [(Double, Double)]) -> GPXRoute {
        GPXRoute(name: "Test", points: coordinates.map { RoutePoint(latitude: $0.0, longitude: $0.1) })
    }
}
