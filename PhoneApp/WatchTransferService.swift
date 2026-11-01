import Foundation
import Observation
import TrailKit
import WatchConnectivity

/// Sends routes to the Watch app and keeps track of which ones it has. The system queues each
/// transfer and finishes it in the background, even if this app quits or the Watch is away for a while.
@Observable
final class WatchTransferService: NSObject {
    /// A paired Apple Watch with TrailWatch installed.
    private(set) var isWatchReady = false
    private(set) var routesOnWatch: Set<UUID> = []
    private(set) var sending: Set<UUID> = []
    var failure: String?

    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private let outbox = URL.cachesDirectory.appending(path: "Outbox")

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func send(_ route: GPXRoute) {
        guard let session, isWatchReady else { return }
        do {
            try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
            let file = outbox.appending(path: "\(route.id.uuidString).json")
            try JSONEncoder().encode(route).write(to: file, options: .atomic)
            session.transferFile(file, metadata: [WatchTransfer.routeIDKey: route.id.uuidString])
            sending.insert(route.id)
        } catch {
            failure = "Couldn't prepare “\(route.name)” for the Watch."
        }
    }

    private func refresh() {
        guard let session else { return }
        isWatchReady = session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
        routesOnWatch = Self.routeIDs(in: session.receivedApplicationContext)
        sending = Set(session.outstandingFileTransfers.compactMap { Self.routeID(in: $0.file.metadata) })
    }

    nonisolated private static func routeIDs(in context: [String: Any]) -> Set<UUID> {
        Set((context[WatchTransfer.routeIDsKey] as? [String] ?? []).compactMap(UUID.init))
    }

    nonisolated private static func routeID(in metadata: [String: Any]?) -> UUID? {
        (metadata?[WatchTransfer.routeIDKey] as? String).flatMap(UUID.init)
    }
}

extension WatchTransferService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?
    ) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// After switching to another Apple Watch.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let ids = Self.routeIDs(in: context)
        Task { @MainActor in self.routesOnWatch = ids }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: (any Error)?) {
        let id = Self.routeID(in: fileTransfer.file.metadata)
        let failed = error != nil
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        Task { @MainActor in
            if let id { self.sending.remove(id) }
            if failed { self.failure = "Couldn't send the route to your Apple Watch. Try again." }
        }
    }
}
