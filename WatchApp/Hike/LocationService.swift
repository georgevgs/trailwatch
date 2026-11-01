import CoreLocation
import Observation

/// Runs GPS during a hike, including with the wrist down, and reports whether there's a usable fix.
@Observable
final class LocationService {
    enum Status {
        case searching, tracking, weakSignal, denied
    }

    /// Fixes less precise than this (metres) count as a weak signal and aren't used.
    static let usableAccuracy: CLLocationAccuracy = 50

    private(set) var status = Status.searching

    /// Hands each usable fix to `handle` until the calling task is cancelled.
    func track(_ handle: (CLLocation) -> Void) async {
        // Asks for When In Use permission the first time.
        let session = CLServiceSession(authorization: .whenInUse)
        // Keeps updates coming when the watch shows another app or the clock. Only activates once
        // permission is granted, so it's started on the first fix.
        var background: CLBackgroundActivitySession?
        defer {
            background?.invalidate()
            session.invalidate()
        }

        do {
            for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                if update.authorizationDenied || update.authorizationDeniedGlobally || update.authorizationRestricted {
                    status = .denied
                } else if let location = update.location {
                    if background == nil { background = CLBackgroundActivitySession() }
                    if (0...Self.usableAccuracy).contains(location.horizontalAccuracy) {
                        status = .tracking
                        handle(location)
                    } else {
                        status = .weakSignal
                    }
                } else if update.locationUnavailable {
                    status = .searching
                }
            }
        } catch {
            status = .searching
        }
    }
}
