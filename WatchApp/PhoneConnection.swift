import Foundation
import TrailKit
import WatchConnectivity

/// Receives routes from the iPhone and reports which ones this Watch has, and your pace.
final class PhoneConnection: NSObject {
    private let library: RouteLibrary
    private let session = WCSession.default

    init(library: RouteLibrary) {
        self.library = library
        super.init()
        library.onChange = { [weak self] in self?.publish() }
        NotificationCenter.default.addObserver(forName: PaceHistory.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
        session.delegate = self
        session.activate()
    }

    /// Hands the iPhone the current state; if it's away, the system delivers the latest one later.
    private func publish() {
        guard session.activationState == .activated else { return }
        try? session.updateApplicationContext([
            WatchTransfer.routeIDsKey: library.routes.map(\.id.uuidString),
            WatchTransfer.paceFactorsKey: PaceHistory.saved.factors,
        ])
    }
}

extension PhoneConnection: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?
    ) {
        Task { @MainActor in self.publish() }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The system deletes the file when this returns, so read it now.
        guard let data = try? Data(contentsOf: file.fileURL),
              let route = try? RouteFile.decode(GPXRoute.self, from: data)
        else { return }
        Task { @MainActor in try? self.library.save(route) }
    }
}
