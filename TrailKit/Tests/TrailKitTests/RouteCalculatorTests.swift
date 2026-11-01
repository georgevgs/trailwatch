import Foundation
import Testing
@testable import TrailKit

struct RouteCalculatorTests {
    @Test func oneDegreeOfLatitudeIsAbout111Kilometres() {
        let distance = RouteCalculator.distance(
            from: RoutePoint(latitude: 0, longitude: 23), to: RoutePoint(latitude: 1, longitude: 23))

        #expect(abs(distance - 111_195) < 1)
    }

    @Test func longitudeShrinksTowardsThePoles() {
        // At Athens' latitude a degree of longitude is cos(38°) of one at the equator.
        let atEquator = RouteCalculator.distance(
            from: RoutePoint(latitude: 0, longitude: 23), to: RoutePoint(latitude: 0, longitude: 24))
        let atAthens = RouteCalculator.distance(
            from: RoutePoint(latitude: 38, longitude: 23), to: RoutePoint(latitude: 38, longitude: 24))

        #expect(abs(atAthens / atEquator - cos(38 * Double.pi / 180)) < 0.001)
    }

    @Test func lengthAddsEveryLeg() {
        let points = [0.0, 0.001, 0.003].map { RoutePoint(latitude: $0, longitude: 0) }

        #expect(abs(RouteCalculator.length(of: points) - 333.6) < 0.1)
        #expect(RouteCalculator.length(of: Array(points.prefix(1))) == 0)
    }

    @Test func gainIgnoresJitterBelowTheThreshold() {
        #expect(RouteCalculator.elevationGain(of: points([100, 103, 100, 104, 100])) == 0)
    }

    @Test func gainCountsClimbsBetweenDescents() {
        // +10, then a 5 m dip, then +15 from the bottom of the dip.
        #expect(RouteCalculator.elevationGain(of: points([100, 110, 105, 120])) == 25)
    }

    @Test func gainCountsASteadyClimbOfSmallSteps() {
        let climb = RouteCalculator.elevationGain(of: points(Array(stride(from: 0, through: 100, by: 2))))

        #expect(abs(climb - 100) < 5)
    }

    @Test func gainSkipsPointsWithoutElevation() {
        let route = [RoutePoint(latitude: 0, longitude: 0), RoutePoint(latitude: 0, longitude: 0.001)]

        #expect(RouteCalculator.elevationGain(of: route) == 0)
    }

    @Test func detectsLoops() {
        let loop = [(0.0, 0.0), (0.001, 0.0), (0.001, 0.001), (0.0001, 0.0)]
            .map { RoutePoint(latitude: $0.0, longitude: $0.1) }
        let outAndBack = [(0.0, 0.0), (0.001, 0.0), (0.002, 0.0)]
            .map { RoutePoint(latitude: $0.0, longitude: $0.1) }

        #expect(RouteCalculator.isLoop(loop))
        #expect(!RouteCalculator.isLoop(outAndBack))
    }

    @Test func kaisarianiLoopMeasurements() throws {
        let url = try #require(Bundle.module.url(
            forResource: "kaisariani_megalos_kyklos", withExtension: "gpx", subdirectory: "Fixtures"))
        let route = try GPXParser.parse(Data(contentsOf: url))

        // Topoguide lists 3.65 km; the 94 points measure 3.62 km point to point.
        #expect(abs(route.distance - 3_619.6) < 1)
        #expect(route.isLoop)
        // Elevations are whole metres from an elevation model: 241 m raw, 224 m once 5 m jitter is
        // filtered. The highest point is 161 m above the lowest.
        #expect(RouteCalculator.elevationGain(of: route.points, threshold: 0) == 241)
        #expect(route.elevationGain == 224)
    }

    private func points(_ elevations: [Double]) -> [RoutePoint] {
        elevations.map { RoutePoint(latitude: 0, longitude: 0, elevation: $0) }
    }
}
