import Foundation
import Testing
@testable import TrailKit

struct HikeGlanceTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    func glance(progress: Double, paused: Bool = false, at seconds: TimeInterval) -> HikeGlance {
        HikeGlance(routeName: "Loop", progress: progress, distanceRemaining: 1000, countingFrom: start,
                   pausedAt: paused ? start + seconds : nil, arrival: nil, updated: start + seconds)
    }

    @Test func redrawsOnlyForRealChanges() {
        let first = glance(progress: 0.10, at: 0)
        #expect(HikeGlance.isWorthShowing(first, after: nil))
        #expect(HikeGlance.isWorthShowing(nil, after: first))
        #expect(!HikeGlance.isWorthShowing(nil, after: nil))

        #expect(!HikeGlance.isWorthShowing(glance(progress: 0.105, at: 30), after: first))
        #expect(HikeGlance.isWorthShowing(glance(progress: 0.11, at: 30), after: first))
        #expect(HikeGlance.isWorthShowing(glance(progress: 0.10, paused: true, at: 30), after: first))
        #expect(HikeGlance.isWorthShowing(glance(progress: 0.10, at: 120), after: first))
    }
}
