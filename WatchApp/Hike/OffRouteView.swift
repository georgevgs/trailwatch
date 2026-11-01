import SwiftUI
import TrailKit

/// How far off the route you are and which way the trail is. Closes by itself once you're back on it.
struct OffRouteView: View {
    let session: HikeSession
    @Environment(\.dismiss) private var dismiss

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
        }
    }

    private var distance: Double { session.tracker.position?.distanceFromRoute ?? 0 }

    /// Compass bearing from you to the nearest point of the route.
    private var bearing: Double {
        guard let you = session.location?.coordinate, let trail = session.tracker.position?.nearestPoint else { return 0 }
        return RouteCalculator.bearing(from: RoutePoint(latitude: you.latitude, longitude: you.longitude), to: trail)
    }

    /// North-up dial with an arrow towards the trail.
    private var compass: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.offRoute.opacity(0.35), lineWidth: 2)
            Text("N")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 3)
            Image(systemName: "location.north.fill")
                .font(.system(size: 24))
                .foregroundStyle(.offRoute)
                .rotationEffect(.degrees(bearing))
        }
        .frame(width: 58, height: 58)
        .accessibilityHidden(true)
    }
}
