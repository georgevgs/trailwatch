import Foundation
import Testing
@testable import TrailKit

struct OffRouteMonitorTests {
    private let start = Date(timeIntervalSince1970: 0)

    @Test func waitsUntilYouHaveReachedTheRoute() {
        var monitor = OffRouteMonitor(threshold: 40)

        // Walking up from the car park, 300 m away.
        #expect(feed(&monitor, distances: Array(repeating: 300, count: 30)) == [])
        #expect(!monitor.hasReachedRoute)
    }

    @Test func alertsOnceAfterStayingOutsideForTheConfirmationTime() {
        var monitor = OffRouteMonitor(threshold: 40, confirmation: 10)

        let changes = feed(&monitor, distances: [5, 10] + Array(repeating: 60, count: 20))

        #expect(changes == [.left])
        #expect(monitor.isOffRoute)
    }

    @Test func ignoresABriefWander() {
        var monitor = OffRouteMonitor(threshold: 40, confirmation: 10)

        // Nine seconds out at 60 m, then back.
        #expect(feed(&monitor, distances: [5] + Array(repeating: 60, count: 9) + [10, 60, 10]) == [])
    }

    @Test func rejoinsOnlyWhenClearlyBackOnTheRoute() {
        var monitor = OffRouteMonitor(threshold: 40, confirmation: 10)

        // 30 m is inside the threshold but not inside 60% of it (24 m).
        let changes = feed(&monitor, distances: [5] + Array(repeating: 60, count: 11) + [30, 30, 20])

        #expect(changes == [.left, .rejoined])
        #expect(!monitor.isOffRoute)
    }

    @Test func skipsFixesTooVagueToJudge() {
        var monitor = OffRouteMonitor(threshold: 40, confirmation: 10)
        _ = monitor.update(distanceFromRoute: 5, accuracy: 5, at: start)

        for second in 1...20 {
            #expect(monitor.update(distanceFromRoute: 80, accuracy: 65, at: start + Double(second)) == nil)
        }
    }

    /// One fix a second, each 5 m accurate.
    private func feed(_ monitor: inout OffRouteMonitor, distances: [Double]) -> [OffRouteMonitor.Change] {
        distances.enumerated().compactMap { second, distance in
            monitor.update(distanceFromRoute: distance, accuracy: 5, at: start + Double(second))
        }
    }
}
