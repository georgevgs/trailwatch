import Foundation

/// Decides when you've left the route, without crying wolf over GPS wander.
///
/// You're off route once every usable fix for `confirmation` seconds is more than `threshold` metres
/// from it, and back on once within 60% of the threshold. Fixes less accurate than the threshold
/// are too vague to judge and are skipped. It only starts watching after you've first been on the
/// route, so walking from the car park to the trailhead doesn't alert.
public struct OffRouteMonitor: Sendable {
    public enum Change: Sendable {
        case left, rejoined
    }

    public let threshold: Double
    public let confirmation: TimeInterval
    public private(set) var isOffRoute = false
    public private(set) var hasReachedRoute = false
    private var outsideSince: Date?

    public init(threshold: Double, confirmation: TimeInterval = 10) {
        self.threshold = threshold
        self.confirmation = confirmation
    }

    /// Returns a change when you leave or rejoin the route.
    public mutating func update(distanceFromRoute distance: Double, accuracy: Double, at time: Date) -> Change? {
        guard accuracy <= threshold else { return nil }

        if isOffRoute {
            guard distance <= threshold * 0.6 else { return nil }
            isOffRoute = false
            return .rejoined
        }

        guard distance > threshold else {
            hasReachedRoute = true
            outsideSince = nil
            return nil
        }
        guard hasReachedRoute else { return nil }

        let since = outsideSince ?? time
        outsideSince = since
        guard time.timeIntervalSince(since) >= confirmation else { return nil }
        isOffRoute = true
        outsideSince = nil
        return .left
    }
}
