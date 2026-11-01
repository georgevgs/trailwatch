import SwiftUI
import TrailKit

/// How far off the route you are and which way the trail is. Closes by itself once you're back on it.
struct OffRouteView: View {
    let session: HikeSession
    @Environment(\.dismiss) private var dismiss
    /// Runs only while this screen is open, to save battery.
    @State private var compassService = HeadingService()

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                compass

                Text("OFF ROUTE")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(.offRoute)
                    .padding(.top, 6)
                Text("\(Format.metres(distance)) m")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("Trail is to the \(Format.compassDirection(bearing))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if facing.source == .travel {
                    Text("Arrow by direction of travel")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    session.showsWayBack = true
                    dismiss()
                } label: {
                    Text("Show on Map")
                        .bold()
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.offRoute)
                .handGestureShortcut(.primaryAction)
                .padding(.top, 8)

                Button("Dismiss") { dismiss() }
                    .buttonStyle(.glass)
            }
            .scenePadding(.horizontal)
        }
        .onAppear { compassService.start() }
        .onDisappear { compassService.stop() }
    }

    private var distance: Double { session.tracker.position?.distanceFromRoute ?? 0 }

    enum FacingSource { case compass, travel, north }

    /// Which way the dial's top points: the compass, else the way you're walking, else north.
    private var facing: (degrees: Double, source: FacingSource) {
        if let heading = compassService.heading { return (heading, .compass) }
        if let fix = session.location, fix.speed > 0.5, (0...45).contains(fix.courseAccuracy), fix.course >= 0 {
            return (fix.course, .travel)
        }
        return (0, .north)
    }

    /// Compass bearing from you to the nearest point of the route.
    private var bearing: Double {
        guard let you = session.location?.coordinate, let trail = session.tracker.position?.nearestPoint else { return 0 }
        return RouteCalculator.bearing(from: RoutePoint(latitude: you.latitude, longitude: you.longitude), to: trail)
    }

    /// A dial with an arrow towards the trail. It turns with the Watch, so the arrow points the
    /// way to walk; without a compass reading it stays north-up.
    private var compass: some View {
        let heading = facing.degrees
        return ZStack {
            Circle()
                .strokeBorder(Color.offRoute.opacity(0.35), lineWidth: 2)
            Text("N")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(heading))
                .offset(y: -22)
                .rotationEffect(.degrees(-heading))
            Image(systemName: "location.north.fill")
                .font(.system(size: 24))
                .foregroundStyle(.offRoute)
                .rotationEffect(.degrees(bearing - heading))
        }
        .frame(width: 58, height: 58)
        .accessibilityHidden(true)
    }
}
