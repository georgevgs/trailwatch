import CoreLocation

/// One `<trkpt>` or `<rtept>` of a GPX file.
public struct RoutePoint: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// Metres above sea level, when the file has `<ele>`.
    public var elevation: Double?
    public var time: Date?

    public init(latitude: Double, longitude: Double, elevation: Double? = nil, time: Date? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.time = time
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
