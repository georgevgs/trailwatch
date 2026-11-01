import Foundation

public enum GPXParser {
    public enum Failure: Error, Equatable {
        /// Not well-formed XML.
        case malformed
        /// A point has a missing or out-of-range `lat`/`lon`.
        case invalidCoordinate
        /// Fewer than two track or route points.
        case noPoints
    }

    /// Reads a GPX 1.0 or 1.1 file. Uses its track points (every `<trkseg>` of every `<trk>`, in order),
    /// or its route points when it has no track, and its waypoints.
    ///
    /// The name comes from the file (`<metadata><name>`, or `<gpx><name>` in GPX 1.0), then the first
    /// track or route, then `fallbackName`.
    public static func parse(_ data: Data, fallbackName: String = "Route") throws(Failure) -> GPXRoute {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = reader
        let finished = parser.parse()

        if reader.foundInvalidCoordinate { throw .invalidCoordinate }
        guard finished else { throw .malformed }

        let points = reader.trackPoints.isEmpty ? reader.routePoints : reader.trackPoints
        guard points.count >= 2 else { throw .noPoints }

        let name = reader.fileName ?? reader.trackName ?? fallbackName
        return GPXRoute(name: name, points: points, waypoints: reader.waypoints)
    }
}

private final class Reader: NSObject, XMLParserDelegate {
    var trackPoints: [RoutePoint] = []
    var routePoints: [RoutePoint] = []
    var waypoints: [Waypoint] = []
    var fileName: String?
    var trackName: String?
    var foundInvalidCoordinate = false

    private var openElements: [String] = []
    private var text = ""
    private var point: RoutePoint?
    private var pointName: String?

    func parser(
        _ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String] = [:]
    ) {
        openElements.append(element)
        text = ""
        guard ["trkpt", "rtept", "wpt"].contains(element) else { return }

        guard let latitude = attributes["lat"].flatMap(Double.init),
              let longitude = attributes["lon"].flatMap(Double.init),
              (-90...90).contains(latitude), (-180...180).contains(longitude)
        else {
            foundInvalidCoordinate = true
            parser.abortParsing()
            return
        }
        point = RoutePoint(latitude: latitude, longitude: longitude)
        pointName = nil
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?
    ) {
        openElements.removeLast()
        let parent = openElements.last
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""

        switch (element, parent) {
        case ("ele", "trkpt"), ("ele", "rtept"), ("ele", "wpt"):
            point?.elevation = Double(value)
        case ("time", "trkpt"), ("time", "rtept"):
            point?.time = Self.date(from: value)
        case ("trkpt", _):
            if let point { trackPoints.append(point) }
            point = nil
        case ("rtept", _):
            if let point { routePoints.append(point) }
            point = nil
        case ("name", "wpt"):
            if !value.isEmpty { pointName = value }
        case ("wpt", _):
            if let point { waypoints.append(Waypoint(point: point, name: pointName ?? "Waypoint")) }
            point = nil
        case ("name", "metadata"), ("name", "gpx"):
            if fileName == nil, !value.isEmpty { fileName = value }
        case ("name", "trk"), ("name", "rte"):
            if trackName == nil, !value.isEmpty { trackName = value }
        default:
            break
        }
    }

    /// GPX times are ISO 8601 in UTC, with or without fractional seconds.
    private static func date(from value: String) -> Date? {
        (try? Date.ISO8601FormatStyle().parse(value))
            ?? (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
    }
}
