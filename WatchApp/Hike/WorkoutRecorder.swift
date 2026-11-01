import CoreLocation
import HealthKit
import Observation

/// Records the hike as an outdoor hiking workout with its route. The running workout keeps
/// the app alive with the wrist down.
///
/// HealthKit's order: start the activity, then collection. To end: stop the activity, wait for
/// `.stopped`, end collection, finish the workout, end the session.
@Observable
final class WorkoutRecorder: NSObject {
    enum State {
        /// No Health access, or the hike was discarded; the hike itself still works.
        case notRecording
        case recording, saved, failed
    }

    /// A change that came from the session itself, not from TrailWatch's buttons.
    enum Change {
        /// Pressing the side button and Digital Crown together pauses and resumes a workout.
        case paused, resumed
        /// watchOS ended the workout, for example because another workout app started one.
        case ended
    }

    private(set) var state = State.notRecording
    /// Beats per minute, while recording.
    private(set) var heartRate: Double?
    /// The heart-rate zone you're in, counted from 1, using the zones set in Health (watchOS 27).
    private(set) var heartRateZone: Int?
    @ObservationIgnored var onChange: ((Change, Date) -> Void)?

    /// Apple recommends one health store for the whole app.
    private static let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    /// The workout once it's in Apple Health, for rating its effort.
    private var savedWorkout: HKWorkout?
    private var stopped: CheckedContinuation<Void, Never>?
    private var isEnding = false

    /// Asks for Health access the first time; later calls return straight away.
    static func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // Relating an effort rating needs both reading and sharing its type.
        let share: Set<HKSampleType> = [
            .workoutType(), HKSeriesType.workoutRoute(),
            HKQuantityType(.distanceWalkingRunning), HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.workoutEffortScore),
        ]
        let read: Set<HKObjectType> = [
            HKQuantityType(.heartRate), HKQuantityType(.distanceWalkingRunning), HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.workoutEffortScore),
        ]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    /// When a recovered workout started; nil for a new one.
    var startDate: Date? { builder?.startDate }

    var isPaused: Bool { session?.state == .paused }

    /// Workout time so far, less pauses, as HealthKit counts it.
    func elapsedTime(at date: Date) -> TimeInterval {
        builder?.elapsedTime(at: date) ?? 0
    }

    /// Starts recording, asking for Health access the first time.
    func start(at date: Date) async {
        await Self.requestAuthorization()
        guard Self.store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .hiking
        configuration.locationType = .outdoor
        do {
            let session = try HKWorkoutSession(healthStore: Self.store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: Self.store, workoutConfiguration: configuration)
            attach(session, builder)
            session.startActivity(with: date)
            try await builder.beginCollection(at: date)
            state = .recording
        } catch {
            builder?.discardWorkout()
            session?.end()
            detach()
            state = .failed
        }
    }

    /// Picks up the workout that was running when the app quit unexpectedly. False when there's none.
    func recover() async -> Bool {
        guard let session = try? await Self.store.recoverActiveWorkoutSession() else { return false }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: Self.store, workoutConfiguration: session.workoutConfiguration)
        attach(session, builder)
        state = .recording
        return true
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    func add(_ location: CLLocation) {
        guard state == .recording else { return }
        routeBuilder?.insertRouteData([location]) { _, _ in }
    }

    /// Ends the workout. Saving puts it in Apple Health with its route and climb; otherwise it's thrown away.
    func finish(at date: Date, ascent: Double, saving: Bool) async {
        guard state == .recording, let session, let builder else { return }
        isEnding = true
        defer { detach() }

        guard saving else {
            builder.discardWorkout()
            session.end()
            state = .notRecording
            return
        }
        do {
            // HealthKit has to finish collecting before the builder can end.
            if session.state == .running || session.state == .paused {
                await withCheckedContinuation { continuation in
                    stopped = continuation
                    session.stopActivity(with: date)
                }
            }
            try await builder.endCollection(at: date)
            if ascent > 0 {
                try await builder.addMetadata([
                    HKMetadataKeyElevationAscended: HKQuantity(unit: .meter(), doubleValue: ascent)
                ])
            }
            // Also saves the route, which belongs to this builder.
            savedWorkout = try await builder.finishWorkout()
            session.end()
            state = .saved
        } catch {
            builder.discardWorkout()
            session.end()
            state = .failed
        }
    }

    /// Saves a 1–10 effort rating with the workout. Per Apple DTS, relate the sample; don't save it first.
    func rateEffort(_ score: Int) async -> Bool {
        guard let workout = savedWorkout else { return false }
        let sample = HKQuantitySample(
            type: HKQuantityType(.workoutEffortScore),
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: Double(score)),
            start: workout.startDate, end: workout.endDate)
        do {
            return try await Self.store.relateWorkoutEffortSample(sample, with: workout, activity: nil)
        } catch {
            return false
        }
    }

    private func attach(_ session: HKWorkoutSession, _ builder: HKLiveWorkoutBuilder) {
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        // HealthKit asks for the workout builder's own route builder rather than a separate one.
        routeBuilder = builder.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder
    }

    private func detach() {
        session = nil
        builder = nil
        routeBuilder = nil
    }

    private func sessionChanged(to newState: HKWorkoutSessionState, from oldState: HKWorkoutSessionState, at date: Date) {
        switch newState {
        case .paused:
            onChange?(.paused, date)
        case .running where oldState == .paused:
            onChange?(.resumed, date)
        case .stopped, .ended:
            stopFinished()
            if state == .recording, !isEnding { onChange?(.ended, date) }
        default:
            break
        }
    }

    private func stopFinished() {
        stopped?.resume()
        stopped = nil
    }
}

extension WorkoutRecorder: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState, date: Date
    ) {
        Task { @MainActor in self.sessionChanged(to: toState, from: fromState, at: date) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        Task { @MainActor in self.stopFinished() }
    }
}

extension WorkoutRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let type = HKQuantityType(.heartRate)
        guard collectedTypes.contains(type),
              let bpm = workoutBuilder.statistics(for: type)?.mostRecentQuantity()?
                  .doubleValue(for: .count().unitDivided(by: .minute()))
        else { return }
        Task { @MainActor in self.heartRate = bpm }
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didUpdateWorkoutZone update: HKLiveWorkoutZoneUpdate) {
        guard let group = update.zoneGroup, group.configuration.quantityType == HKQuantityType(.heartRate),
              let current = update.currentZoneDuration?.zone,
              let position = group.configuration.zones.firstIndex(where: { $0.index == current.index })
        else { return }
        Task { @MainActor in self.heartRateZone = position + 1 }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
