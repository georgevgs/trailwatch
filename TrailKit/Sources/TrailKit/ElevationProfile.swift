import Foundation

/// The route's height along its length: what's left to climb and how long the rest should take.
public struct ElevationProfile: Sendable {
    public struct Sample: Equatable, Sendable {
        /// Metres along the route.
        public var distance: Double
        /// Metres above sea level.
        public var elevation: Double
    }

    /// Every route point that has an elevation.
    public let samples: [Sample]
    /// Metres along the route.
    public let length: Double

    public init(route: GPXRoute) {
        var samples: [Sample] = []
        var distance = 0.0
        for (index, point) in route.points.enumerated() {
            if index > 0 { distance += RouteCalculator.distance(from: route.points[index - 1], to: point) }
            if let elevation = point.elevation { samples.append(Sample(distance: distance, elevation: elevation)) }
        }
        self.samples = samples
        length = distance
    }

    /// False when the file has too few elevations to draw or climb.
    public var hasElevation: Bool { samples.count >= 2 }

    /// The height at `distance` along the route, between the nearest samples.
    public func elevation(at distance: Double) -> Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if distance <= first.distance { return first.elevation }
        if distance >= last.distance { return last.elevation }
        // Binary search: this runs for every 50 m of the rest of the route on each GPS fix.
        var low = 0, high = samples.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if samples[middle].distance < distance { low = middle } else { high = middle }
        }
        let a = samples[low], b = samples[high]
        let span = b.distance - a.distance
        return span > 0 ? a.elevation + (b.elevation - a.elevation) * (distance - a.distance) / span : b.elevation
    }

    /// Metres still to climb after `distance`, ignoring changes under 5 m like the route's ascent.
    public func climb(after distance: Double) -> Double {
        count(after: distance) { $0 }
    }

    /// Metres still to descend after `distance`.
    public func descent(after distance: Double) -> Double {
        count(after: distance) { -$0 }
    }

    /// At most `count` samples spread along the route, for a chart.
    public func chartSamples(count: Int = 100) -> [Sample] {
        guard samples.count > count, let last = samples.last else { return samples }
        let step = Double(samples.count - 1) / Double(count - 1)
        return (0..<count - 1).map { samples[Int(Double($0) * step)] } + [last]
    }

    /// Seconds from `start` to `end` metres at Tobler's pace. Slopes are taken over 50 m
    /// so elevation noise doesn't slow the estimate.
    public func walkingTime(from start: Double, to end: Double) -> TimeInterval {
        var time = 0.0
        var distance = max(0, start)
        while distance < end {
            let next = min(distance + 50, end)
            let run = next - distance
            let rise = (elevation(at: next) ?? 0) - (elevation(at: distance) ?? 0)
            time += run / 1000 / Self.toblerSpeed(slope: rise / run) * 3600
            distance = next
        }
        return time
    }

    /// Walking speed in km/h on a slope given as rise over run (Tobler, 1993).
    static func toblerSpeed(slope: Double) -> Double {
        6 * exp(-3.5 * abs(slope + 0.05))
    }

    private func count(after distance: Double, _ direction: (Double) -> Double) -> Double {
        guard let start = elevation(at: distance) else { return 0 }
        var counter = ClimbCounter(threshold: 5)
        counter.add(direction(start))
        for sample in samples where sample.distance > distance {
            counter.add(direction(sample.elevation))
        }
        return counter.gain
    }
}

/// Time to finish: Tobler's estimate scaled by your pace. It starts from your past hikes and
/// moves towards today's pace as you walk; after 1 km on the route, each counts the same.
public struct FinishEstimate: Sendable {
    public let profile: ElevationProfile
    /// Your usual pace against Tobler's, from past hikes; 1 without any.
    public let usualFactor: Double
    private var joined: (along: Double, elapsed: TimeInterval)?

    /// Kilometres on the route after which today's pace counts as much as your usual one.
    static let blendDistance = 1.0
    static let factorRange = 0.6...2.5

    public init(profile: ElevationProfile, usualFactor: Double = 1) {
        self.profile = profile
        self.usualFactor = min(max(usualFactor, Self.factorRange.lowerBound), Self.factorRange.upperBound)
    }

    /// Notes where and when you first reached the route, so the walk to the trailhead isn't counted.
    public mutating func reachedRoute(along: Double, elapsed: TimeInterval) {
        if joined == nil { joined = (along, elapsed) }
    }

    /// Today's pace against Tobler's (above 1 is slower), once there's enough to judge: 200 m and 2 min on the route.
    public func todaysFactor(along: Double, elapsed: TimeInterval) -> Double? {
        guard let joined, along - joined.along >= 200, elapsed - joined.elapsed >= 120 else { return nil }
        let expected = profile.walkingTime(from: joined.along, to: along)
        guard expected > 0 else { return nil }
        return min(max((elapsed - joined.elapsed) / expected, Self.factorRange.lowerBound), Self.factorRange.upperBound)
    }

    /// How much slower (above 1) or faster than Tobler's pace to expect for the rest.
    public func paceFactor(along: Double, elapsed: TimeInterval) -> Double {
        guard let joined, let today = todaysFactor(along: along, elapsed: elapsed) else { return usualFactor }
        let walked = (along - joined.along) / 1000
        return (usualFactor * Self.blendDistance + today * walked) / (Self.blendDistance + walked)
    }

    public func timeToFinish(along: Double, elapsed: TimeInterval) -> TimeInterval {
        profile.walkingTime(from: along, to: profile.length) * paceFactor(along: along, elapsed: elapsed)
    }
}

/// Your pace on past hikes against Tobler's, newest last.
public struct PaceHistory: Codable, Sendable, Equatable {
    public private(set) var factors: [Double] = []

    public init(factors: [Double] = []) {
        self.factors = factors
    }

    /// The median of the last five hikes, so one odd day doesn't skew it; 1 without any.
    public var usualFactor: Double {
        let recent = factors.suffix(5).sorted()
        guard !recent.isEmpty else { return 1 }
        let middle = recent.count / 2
        return recent.count.isMultiple(of: 2) ? (recent[middle - 1] + recent[middle]) / 2 : recent[middle]
    }

    /// Adds a finished hike when it covered at least 2 km of the route in 20 min.
    public mutating func add(_ estimate: FinishEstimate, along: Double, elapsed: TimeInterval) {
        guard along >= 2000, elapsed >= 1200, let factor = estimate.todaysFactor(along: along, elapsed: elapsed) else { return }
        factors = Array((factors + [factor]).suffix(10))
    }
}
