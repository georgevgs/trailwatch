import Foundation

/// Time spent hiking: the clock since the start, less any pauses.
public struct Stopwatch: Sendable, Equatable {
    /// Where a running timer counts from: the start, moved later by the pauses so far.
    public private(set) var countingFrom: Date
    /// When the current pause began; nil while running.
    public private(set) var pausedAt: Date?

    public init(countingFrom: Date, pausedAt: Date? = nil) {
        self.countingFrom = countingFrom
        self.pausedAt = pausedAt
    }

    public var isPaused: Bool { pausedAt != nil }

    public mutating func pause(at date: Date) {
        guard pausedAt == nil else { return }
        pausedAt = date
    }

    public mutating func resume(at date: Date) {
        guard let pausedAt else { return }
        countingFrom += max(0, date.timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }

    /// Seconds of hiking up to `date`.
    public func elapsed(at date: Date) -> TimeInterval {
        max(0, (pausedAt ?? date).timeIntervalSince(countingFrom))
    }
}
