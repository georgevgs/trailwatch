import Foundation
import Testing
@testable import TrailKit

struct StopwatchTests {
    let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func countsTheClockWhileRunning() {
        let stopwatch = Stopwatch(countingFrom: start)
        #expect(stopwatch.elapsed(at: start + 90) == 90)
    }

    @Test func leavesPausesOut() {
        var stopwatch = Stopwatch(countingFrom: start)
        stopwatch.pause(at: start + 60)
        #expect(stopwatch.isPaused)
        #expect(stopwatch.elapsed(at: start + 500) == 60)

        stopwatch.resume(at: start + 300)
        #expect(!stopwatch.isPaused)
        #expect(stopwatch.countingFrom == start + 240)
        #expect(stopwatch.elapsed(at: start + 330) == 90)
    }

    @Test func ignoresRepeatedPauseAndResume() {
        var stopwatch = Stopwatch(countingFrom: start)
        stopwatch.resume(at: start + 10)
        stopwatch.pause(at: start + 60)
        stopwatch.pause(at: start + 120)
        stopwatch.resume(at: start + 180)
        stopwatch.resume(at: start + 240)
        #expect(stopwatch.elapsed(at: start + 240) == 120)
    }
}
