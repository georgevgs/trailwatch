import Foundation
import TrailKit
import WatchConnectivity

/// Receives routes from the iPhone and reports which ones this Watch has.
final class PhoneConnection: NSObject {
    private let library: RouteLibrary
    private let session = WCSession.default

    init(library: RouteLibrary) {
        self.library = library
        super.init()
        library.onChange = { [weak self] in self?.publishRoutes() }
        session.delegate = self
        session.activate()
    }

    /// Hands the iPhone the current list; if it's away, the system delivers the latest one later.
    private func publishRoutes() {
        guard session.activationState == .activated else { return }
        let ids = library.routes.map(\.id.uuidString)
        try? session.updateApplicationContext([WatchTransfer.routeIDsKey: ids])
    }
}

extension PhoneConnection: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?
    ) {
        Task { @MainActor in self.publishRoutes() }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The system deletes the file when this returns, so read it now.
        guard let data = try? Data(contentsOf: file.fileURL),
              let route = try? JSONDecoder().decode(GPXRoute.self, from: data)
        else { return }
        Task { @MainActor in try? self.library.save(route) }
    }
}
