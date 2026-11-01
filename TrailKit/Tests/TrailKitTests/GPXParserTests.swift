import Foundation
import Testing
@testable import TrailKit

struct GPXParserTests {
    @Test func readsTheKaisarianiLoop() throws {
        let url = try #require(Bundle.module.url(
            forResource: "kaisariani_megalos_kyklos", withExtension: "gpx", subdirectory: "Fixtures"))
        let route = try GPXParser.parse(Data(contentsOf: url))

        #expect(route.name == "Μεγάλος Κύκλος Μονής Καισαριανής")
        #expect(route.points.count == 94)
        #expect(route.points.first == RoutePoint(latitude: 37.9643257, longitude: 23.7906644, elevation: 278))
        #expect(route.points.allSatisfy { $0.time == nil })
        // Every point sits on Hymettus's western slope, around Kaisariani Monastery.
        #expect(route.points.allSatisfy {
            (37.95...37.97).contains($0.latitude) && (23.78...23.81).contains($0.longitude)
        })
    }

    @Test func joinsTrackSegmentsInOrder() throws {
        let route = try GPXParser.parse(gpx("""
            <trk><name>Two parts</name>
              <trkseg><trkpt lat="1" lon="1"/><trkpt lat="2" lon="2"/></trkseg>
              <trkseg><trkpt lat="3" lon="3"/></trkseg>
            </trk>
            """))

        #expect(route.name == "Two parts")
        #expect(route.points.map(\.latitude) == [1, 2, 3])
    }

    @Test func usesRoutePointsWhenThereIsNoTrack() throws {
        let route = try GPXParser.parse(gpx("""
            <wpt lat="9" lon="9"><name>Spring</name></wpt>
            <rte><name>Planned</name>
              <rtept lat="1" lon="1"><ele>100.5</ele></rtept>
              <rtept lat="2" lon="2"><ele>110</ele></rtept>
            </rte>
            """))

        #expect(route.name == "Planned")
        #expect(route.points.map(\.elevation) == [100.5, 110])
    }

    @Test func prefersTheFileNameOverTheTrackName() throws {
        let route = try GPXParser.parse(gpx("""
            <metadata><name>Hymettus loop</name></metadata>
            <trk><name>Track 1</name><trkseg><trkpt lat="1" lon="1"/><trkpt lat="2" lon="2"/></trkseg></trk>
            """))

        #expect(route.name == "Hymettus loop")
    }

    @Test func fallsBackToTheGivenName() throws {
        let route = try GPXParser.parse(
            gpx(#"<trk><trkseg><trkpt lat="1" lon="1"/><trkpt lat="2" lon="2"/></trkseg></trk>"#),
            fallbackName: "hymettus")

        #expect(route.name == "hymettus")
    }

    @Test func readsTimestampsWithAndWithoutFractionalSeconds() throws {
        let route = try GPXParser.parse(gpx("""
            <trk><trkseg>
              <trkpt lat="1" lon="1"><time>2026-11-01T08:30:00Z</time></trkpt>
              <trkpt lat="2" lon="2"><time>2026-11-01T08:30:05.500Z</time></trkpt>
            </trkseg></trk>
            """))

        let start = try #require(route.points[0].time)
        let next = try #require(route.points[1].time)
        #expect(start == Date(timeIntervalSince1970: 1_793_521_800))
        #expect(next.timeIntervalSince(start) == 5.5)
    }

    @Test func ignoresElevationInsideExtensions() throws {
        let route = try GPXParser.parse(gpx("""
            <trk><trkseg>
              <trkpt lat="1" lon="1"><extensions><ele>999</ele></extensions></trkpt>
              <trkpt lat="2" lon="2"/>
            </trkseg></trk>
            """))

        #expect(route.points[0].elevation == nil)
    }

    @Test func rejectsOutOfRangeCoordinates() {
        #expect(throws: GPXParser.Failure.invalidCoordinate) {
            try GPXParser.parse(gpx(#"<trk><trkseg><trkpt lat="95" lon="1"/><trkpt lat="2" lon="2"/></trkseg></trk>"#))
        }
    }

    @Test func rejectsMissingCoordinates() {
        #expect(throws: GPXParser.Failure.invalidCoordinate) {
            try GPXParser.parse(gpx(#"<trk><trkseg><trkpt lat="1"/><trkpt lat="2" lon="2"/></trkseg></trk>"#))
        }
    }

    @Test func rejectsAFileWithoutEnoughPoints() {
        #expect(throws: GPXParser.Failure.noPoints) {
            try GPXParser.parse(gpx(#"<wpt lat="1" lon="1"/><trk><trkseg><trkpt lat="1" lon="1"/></trkseg></trk>"#))
        }
    }

    @Test func rejectsMalformedXML() {
        #expect(throws: GPXParser.Failure.malformed) {
            try GPXParser.parse(Data("<gpx><trk>".utf8))
        }
    }

    private func gpx(_ body: String) -> Data {
        Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="tests">\(body)</gpx>
            """.utf8)
    }
}
