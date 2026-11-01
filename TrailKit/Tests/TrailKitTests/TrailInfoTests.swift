import Foundation
import Testing
@testable import TrailKit

struct TrailInfoTests {
    /// 1.1 km north: up 100 m to the middle, then down 50 m.
    let route = GPXRoute(name: "Hill", points: [
        RoutePoint(latitude: 0, longitude: 0, elevation: 100),
        RoutePoint(latitude: 0.005, longitude: 0, elevation: 200),
        RoutePoint(latitude: 0.01, longitude: 0, elevation: 150),
    ])

    @Test func climbAndDescentLeft() {
        let profile = ElevationProfile(route: route)
        #expect(profile.hasElevation)
        #expect(profile.climb(after: 0) == route.elevationGain)
        #expect(profile.descent(after: 0) == 50)
        let middle = profile.samples[1].distance
        #expect(profile.elevation(at: middle / 2) == 150)
        #expect(abs(profile.climb(after: middle / 2) - 50) < 0.001)
        #expect(profile.climb(after: middle) == 0)
        #expect(profile.descent(after: profile.length) == 0)
    }

    @Test func routesWithoutElevationHaveNoProfile() {
        let flat = GPXRoute(name: "Flat", points: [
            RoutePoint(latitude: 0, longitude: 0), RoutePoint(latitude: 0.01, longitude: 0),
        ])
        let profile = ElevationProfile(route: flat)
        #expect(!profile.hasElevation)
        #expect(profile.climb(after: 0) == 0)
        // Tobler on the flat is 5.04 km/h.
        #expect(abs(profile.walkingTime(from: 0, to: profile.length) - profile.length / ElevationProfile.toblerSpeed(slope: 0) * 3.6) < 0.01)
    }

    @Test func toblerIsFastestOnAGentleDescent() {
        #expect(ElevationProfile.toblerSpeed(slope: -0.05) == 6)
        #expect(abs(ElevationProfile.toblerSpeed(slope: 0) - 5.04) < 0.01)
        #expect(ElevationProfile.toblerSpeed(slope: 0.2) < ElevationProfile.toblerSpeed(slope: -0.2))
    }

    @Test func chartSamplesKeepTheEnds() {
        let points = (0...500).map { RoutePoint(latitude: Double($0) * 0.0001, longitude: 0, elevation: Double($0)) }
        let profile = ElevationProfile(route: GPXRoute(name: "Long", points: points))
        let chart = profile.chartSamples(count: 100)
        #expect(chart.count == 100)
        #expect(chart.first == profile.samples.first)
        #expect(chart.last == profile.samples.last)
    }

    @Test func finishEstimateLearnsYourPace() {
        let points = (0...40).map { RoutePoint(latitude: Double($0) * 0.001, longitude: 0, elevation: 100) }
        var estimate = FinishEstimate(profile: ElevationProfile(route: GPXRoute(name: "Flat", points: points)))
        let tobler = estimate.timeToFinish(along: 0, elapsed: 0)
        #expect(abs(tobler - estimate.profile.length / ElevationProfile.toblerSpeed(slope: 0) * 3.6) < 0.01)

        estimate.reachedRoute(along: 0, elapsed: 120)
        // Too little walked yet to judge.
        #expect(estimate.paceFactor(along: 500, elapsed: 600) == 1)
        // 2 km in 48 min is half Tobler's speed.
        let along = 2000.0
        let factor = estimate.paceFactor(along: along, elapsed: 120 + along / ElevationProfile.toblerSpeed(slope: 0) * 3.6 * 2)
        #expect(abs(factor - 2) < 0.01)
    }

    @Test func sunsetMatchesPublishedTimes() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date { utc.date(from: DateComponents(year: y, month: m, day: d))! }
        func time(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
            utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
        }

        // London 21 June 2024: 21:21 BST. New York 21 December 2024: 16:32 EST.
        let london = try #require(Sun.sunset(on: day(2024, 6, 21), latitude: 51.5074, longitude: -0.1278, calendar: utc))
        #expect(abs(london.timeIntervalSince(time(2024, 6, 21, 20, 21))) < 120)
        let newYork = try #require(Sun.sunset(on: day(2024, 12, 21), latitude: 40.7128, longitude: -74.006, calendar: utc))
        #expect(abs(newYork.timeIntervalSince(time(2024, 12, 21, 21, 32))) < 120)
        // Polar night in Tromsø.
        #expect(Sun.sunset(on: day(2026, 12, 21), latitude: 69.65, longitude: 18.96, calendar: utc) == nil)
    }
}
