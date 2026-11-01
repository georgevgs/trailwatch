import Foundation

/// Display text for distances, times and directions, in the device's number format.
public enum Format {
    /// "3.62" (or "3,62"): metres as kilometres to two decimals.
    public static func kilometres(_ metres: Double) -> String {
        (metres / 1000).formatted(.number.precision(.fractionLength(2)))
    }

    /// "224": whole metres.
    public static func metres(_ metres: Double) -> String {
        metres.formatted(.number.precision(.fractionLength(0)))
    }

    /// "1:21:40"
    public static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .hourMinuteSecond))
    }

    /// "22'22"": minutes and seconds per kilometre, or nil before the first 50 m.
    public static func pace(seconds: TimeInterval, metres: Double) -> String? {
        guard metres >= 50, seconds > 0 else { return nil }
        let perKilometre = Int((seconds / (metres / 1000)).rounded())
        return "\(perKilometre / 60)'\(String(format: "%02d", perKilometre % 60))\""
    }

    /// "northeast": the nearest of the eight compass points to a bearing in degrees.
    public static func compassDirection(_ bearing: Double) -> String {
        let names = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]
        let index = Int(((bearing.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45).rounded(.down)) % 8
        return names[index]
    }
}

extension Format {
    /// "1 hr, 20 min": a time to come, to the minute.
    public static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let minutes = (max(0, seconds) / 60).rounded()
        return Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
