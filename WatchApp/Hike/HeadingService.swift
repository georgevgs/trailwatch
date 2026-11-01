import CoreLocation
import Observation

/// Which way the Watch faces, from its compass. Core Location has no async heading API, so this wraps the delegate.
@Observable
final class HeadingService: NSObject, CLLocationManagerDelegate {
    /// Degrees clockwise from true north (magnetic when there's no fix); nil while the compass is unavailable or needs calibrating.
    private(set) var heading: Double?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 5
    }

    func start() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingHeading()
        heading = nil
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value: Double? = newHeading.headingAccuracy < 0 ? nil
            : newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = value }
    }
}
