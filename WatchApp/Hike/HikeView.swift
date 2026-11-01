import SwiftUI

/// A hike in progress, then its summary.
struct HikeView: View {
    @Bindable var session: HikeSession
    let onClose: () -> Void
    @State private var showsStats = false

    var body: some View {
        if session.isFinished {
            SummaryView(session: session, onDone: onClose)
        } else {
            NavigationStack {
                HikeMapView(session: session) { showsStats = true }
                    .navigationDestination(isPresented: $showsStats) {
                        // Map and stats are two views of one hike, so they fade rather than slide.
                        StatsView(session: session)
                            .navigationTransition(.crossFade)
                    }
            }
            .sheet(isPresented: $session.showsOffRouteAlert) {
                OffRouteView(session: session)
            }
            .confirmationDialog("End this hike?", isPresented: $session.showsEndDialog) {
                Button("Save Hike") {
                    Task { await session.end(saving: true) }
                }
                Button("Discard Hike", role: .destructive) {
                    Task { await session.end(saving: false) }
                    onClose()
                }
            }
        }
    }
}

/// Pauses or resumes the hike.
struct PauseButton: View {
    let session: HikeSession

    var body: some View {
        Button(session.isPaused ? "Resume" : "Pause", systemImage: session.isPaused ? "play.fill" : "pause.fill") {
            if session.isPaused {
                session.resume()
            } else {
                session.pause()
            }
        }
        .tint(.yellow)
    }
}
