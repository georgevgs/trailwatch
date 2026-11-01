import SwiftUI
import TrailKit

struct RouteDetailView: View {
    let route: GPXRoute
    @Environment(HikeManager.self) private var hikes
    @AppStorage(HikeSession.offRouteDistanceKey) private var offRouteDistance = 40.0
    @State private var reversed = false

    var body: some View {
        // Walking it the other way changes the start and the climb.
        let shown = reversed ? route.reversed() : route
        let profile = ElevationProfile(route: shown)
        let duration = FinishEstimate(profile: profile).timeToFinish(along: 0, elapsed: 0)
        let sunset = shown.points.first.flatMap { Sun.sunset(on: .now, latitude: $0.latitude, longitude: $0.longitude) }

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RouteThumbnail(route: shown)
                    .frame(height: 76)

                Text(route.name)
                    .font(.headline)

                HStack(alignment: .top) {
                    stat(Format.kilometres(shown.distance), unit: "km", label: "Distance")
                    stat(Format.metres(shown.elevationGain), unit: "m", label: "Ascent")
                    stat(route.isLoop ? "Loop" : "One way", label: "Type")
                }

                if profile.hasElevation {
                    ElevationChart(profile: profile)
                        .frame(height: 40)
                }

                Label("About \(Format.hoursMinutes(duration))", systemImage: "clock")
                    .font(.footnote)
                if let sunset, sunset > .now {
                    let afterDark = Date.now + duration > sunset
                    let time = sunset.formatted(.dateTime.hour().minute())
                    Label(afterDark ? "Sunset \(time): you'd finish after dark" : "Sunset \(time)", systemImage: "sunset.fill")
                        .font(.footnote)
                        .foregroundStyle(afterDark ? Color.orange : Color.secondary)
                }

                if !route.waypoints.isEmpty {
                    Label("\(route.waypoints.count) waypoints", systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Toggle("Reverse direction", isOn: $reversed)

                Button {
                    hikes.start(route, reversed: reversed, offRouteDistance: offRouteDistance)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .handGestureShortcut(.primaryAction)
            }
        }
        // Asked here rather than at Start, so the hike begins without a prompt in the way.
        .task { await WorkoutRecorder.requestAuthorization() }
    }

    private func stat(_ value: String, unit: String? = nil, label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.headline)
                if let unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(label.uppercased())
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
