import Foundation
import Testing
@testable import TrailKit

struct FormatTests {
    @Test func paceIsMinutesAndSecondsPerKilometre() {
        #expect(Format.pace(seconds: 1342, metres: 1000) == "22'22\"")
        #expect(Format.pace(seconds: 1200, metres: 2000) == "10'00\"")
        #expect(Format.pace(seconds: 60, metres: 40) == nil)
    }

    @Test func durationShowsHoursMinutesAndSeconds() {
        #expect(Format.duration(4900) == "1:21:40")
        #expect(Format.duration(65) == "0:01:05")
    }

    @Test func compassDirectionRoundsToTheNearestPoint() {
        #expect(Format.compassDirection(0) == "north")
        #expect(Format.compassDirection(44) == "northeast")
        #expect(Format.compassDirection(180) == "south")
        #expect(Format.compassDirection(337.4) == "northwest")
        #expect(Format.compassDirection(337.6) == "north")
    }

    @Test func bearingsPointTheRightWay() {
        let origin = RoutePoint(latitude: 0, longitude: 0)

        #expect(abs(RouteCalculator.bearing(from: origin, to: RoutePoint(latitude: 1, longitude: 0)) - 0) < 1e-9)
        #expect(abs(RouteCalculator.bearing(from: origin, to: RoutePoint(latitude: 0, longitude: 1)) - 90) < 1e-9)
        #expect(abs(RouteCalculator.bearing(from: origin, to: RoutePoint(latitude: -1, longitude: 0)) - 180) < 1e-9)
        #expect(abs(RouteCalculator.bearing(from: origin, to: RoutePoint(latitude: 0, longitude: -1)) - 270) < 1e-9)
    }
}
