import Foundation

public enum Sun {
    /// Sunset on `day` at a place, from NOAA's solar equations (within a minute or two outside
    /// polar regions). Nil when the sun doesn't set or rise.
    public static func sunset(on day: Date, latitude: Double, longitude: Double, calendar: Calendar = .current) -> Date? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        guard let midnight = utc.date(from: parts) else { return nil }

        // Start at local solar noon, then refine once at the first answer.
        var sunset = midnight.addingTimeInterval((720 - 4 * longitude) * 60)
        for _ in 0..<2 {
            let (equationOfTime, declination) = solarPosition(at: sunset)
            let lat = radians(latitude)
            let cosHourAngle = cos(radians(90.833)) / (cos(lat) * cos(declination)) - tan(lat) * tan(declination)
            guard (-1...1).contains(cosHourAngle) else { return nil }
            let hourAngle = degrees(acos(cosHourAngle))
            sunset = midnight.addingTimeInterval((720 - 4 * longitude - equationOfTime + 4 * hourAngle) * 60)
        }
        return sunset
    }

    /// The equation of time in minutes and the sun's declination in radians.
    private static func solarPosition(at date: Date) -> (Double, Double) {
        let t = (date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545) / 36_525
        let meanLongitude = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let center = sin(radians(meanAnomaly)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(radians(2 * meanAnomaly)) * (0.019993 - 0.000101 * t)
            + sin(radians(3 * meanAnomaly)) * 0.000289
        let omega = radians(125.04 - 1934.136 * t)
        let apparentLongitude = meanLongitude + center - 0.00569 - 0.00478 * sin(omega)
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(omega)
        let declination = asin(sin(radians(obliquity)) * sin(radians(apparentLongitude)))

        let y = pow(tan(radians(obliquity / 2)), 2)
        let l = radians(meanLongitude), m = radians(meanAnomaly)
        let equationOfTime = 4 * degrees(
            y * sin(2 * l) - 2 * eccentricity * sin(m) + 4 * eccentricity * y * sin(m) * cos(2 * l)
                - 0.5 * y * y * sin(4 * l) - 1.25 * eccentricity * eccentricity * sin(2 * m))
        return (equationOfTime, declination)
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
