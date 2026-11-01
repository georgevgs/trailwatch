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

    @Test func finishEstimateBlendsUsualAndTodaysPace() {
        let points = (0...40).map { RoutePoint(latitude: Double($0) * 0.001, longitude: 0, elevation: 100) }
        let profile = ElevationProfile(route: GPXRoute(name: "Flat", points: points))
        let flatSecondsPerMetre = 3.6 / ElevationProfile.toblerSpeed(slope: 0)

        var estimate = FinishEstimate(profile: profile)
        #expect(abs(estimate.timeToFinish(along: 0, elapsed: 0) - profile.length * flatSecondsPerMetre) < 0.01)

        // Slow walkers start slow.
        var usual = FinishEstimate(profile: profile, usualFactor: 1.5)
        #expect(usual.paceFactor(along: 0, elapsed: 0) == 1.5)

        estimate.reachedRoute(along: 0, elapsed: 120)
        usual.reachedRoute(along: 0, elapsed: 120)
        // Too little walked yet to judge.
        #expect(estimate.paceFactor(along: 100, elapsed: 200) == 1)
        // 1 km at half Tobler's speed: halfway between usual 1 and today's 2.
        #expect(abs(estimate.paceFactor(along: 1000, elapsed: 120 + 1000 * flatSecondsPerMetre * 2) - 1.5) < 0.01)
        // 3 km at Tobler's speed after a usual 1.5: today counts three times as much.
        #expect(abs(usual.paceFactor(along: 3000, elapsed: 120 + 3000 * flatSecondsPerMetre) - 1.125) < 0.01)
    }

    @Test func paceHistoryUsesTheMedianOfRecentHikes() {
        #expect(PaceHistory().usualFactor == 1)
        #expect(PaceHistory(factors: [0.8, 1.6, 1.2]).usualFactor == 1.2)
        #expect(PaceHistory(factors: [2.5, 2.5, 1, 1.1, 1.2, 1.3]).usualFactor == 1.2)

        let points = (0...40).map { RoutePoint(latitude: Double($0) * 0.001, longitude: 0, elevation: 100) }
        var estimate = FinishEstimate(profile: ElevationProfile(route: GPXRoute(name: "Flat", points: points)))
        estimate.reachedRoute(along: 0, elapsed: 0)
        let flatSecondsPerMetre = 3.6 / ElevationProfile.toblerSpeed(slope: 0)
        var history = PaceHistory()
        // Too short to learn from.
        history.add(estimate, along: 1500, elapsed: 1500 * flatSecondsPerMetre)
        #expect(history.factors.isEmpty)
        history.add(estimate, along: 3000, elapsed: 3000 * flatSecondsPerMetre * 1.25)
        #expect(history.factors.count == 1)
        #expect(abs(history.usualFactor - 1.25) < 0.01)
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
