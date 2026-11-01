import MapKit
import SwiftUI
import TrailKit

/// The hike's map: the offline trail map when the route came with map data, otherwise Apple Maps.
struct HikeMapView: View {
    let session: HikeSession
    let showStats: () -> Void

    @AppStorage("usesAppleMaps") private var usesAppleMaps = false
    /// Apple Maps follows you once there's a fix and shows the whole route until then.
    @State private var camera = MapCameraPosition.userLocation(fallback: .automatic)
    @State private var follows = true
    @Namespace private var mapScope
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        Group {
            if let layers = trailMap {
                TrailMapView(session: session, layers: layers, follows: $follows)
            } else {
                appleMap
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                if let waypoint = session.reachedWaypoint {
                    pill(waypoint.name, systemImage: "mappin.circle.fill", color: .primary)
                }
                if session.finishesAfterDark {
                    pill("Finish after sunset", systemImage: "sunset.fill", color: .orange)
                }
                if session.isPaused {
                    pill("Paused", systemImage: "pause.fill", color: .yellow)
                }
                if let trailMap {
                    Text(trailMap.hasContours ? "© OpenStreetMap · Mapzen" : "© OpenStreetMap")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                if let message = gpsMessage {
                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                        .padding(.horizontal, 24)
                }
            }
        }
        .overlay(alignment: .bottom) {
            GlassEffectContainer {
                HStack(alignment: .bottom) {
                    Button(action: showStats) {
                        progress
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows hike stats")

                    Spacer()

                    // Hidden with the wrist down, where they can't be used anyway.
                    if !isLuminanceReduced {
                        VStack(spacing: 6) {
                            controls
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .toolbar {
            // Where watchOS puts Close, so reaching for "back" ends the hike properly instead of leaving it.
            ToolbarItem(placement: .topBarLeading) {
                Button("End Hike", systemImage: "xmark") {
                    session.showsEndDialog = true
                }
                .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                PauseButton(session: session)
                    .labelStyle(.iconOnly)
            }
        }
        .mapScope(mapScope)
    }

    private func pill(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.bold())
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
    }

    private var trailMap: TrailMapLayers? {
        usesAppleMaps ? nil : session.mapLayers
    }

    private var appleMap: some View {
        let route = session.tracker.split(at: session.tracker.distanceAlong)
        let line = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)

        return Map(position: $camera, interactionModes: [.pan, .zoom], scope: mapScope) {
            MapPolyline(coordinates: session.route.coordinates)
                .stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            MapPolyline(coordinates: route.ahead.map(\.coordinate))
                .stroke(Color.accentColor.opacity(0.42), style: line)
            MapPolyline(coordinates: route.walked.map(\.coordinate))
                .stroke(Color.accentColor, style: line)

            if let start = session.route.points.first {
                Annotation("Start", coordinate: start.coordinate) {
                    Circle()
                        .fill(.white)
                        .stroke(.terrain, lineWidth: 2)
                        .frame(width: 11, height: 11)
                }
                .annotationTitles(.hidden)
            }

            ForEach(session.route.waypoints, id: \.self) { waypoint in
                Marker(waypoint.name, systemImage: "mappin", coordinate: waypoint.point.coordinate)
            }

            UserAnnotation()
        }
        .mapStyle(.trail())
        .onChange(of: session.showsWayBack) { _, shows in
            if shows { frameWayBack() }
        }
    }

    @ViewBuilder private var controls: some View {
        if session.mapLayers != nil {
            Button {
                usesAppleMaps.toggle()
            } label: {
                Image(systemName: usesAppleMaps ? "map" : "globe.europe.africa")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(usesAppleMaps ? "Show trail map" : "Show Apple Maps")
        }
        if trailMap != nil {
            Button {
                follows = true
            } label: {
                Image(systemName: follows ? "location.fill" : "location")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Follow my location")
        } else {
            MapCompass(scope: mapScope)
            MapUserLocationButton(scope: mapScope)
        }
    }

    /// Progress along the route, or how far away the trail is before you've reached it.
    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !session.monitor.hasReachedRoute, let away = session.tracker.position?.distanceFromRoute,
               away > session.monitor.threshold {
                Text("Trail \(Format.metres(away)) m away")
                    .font(.footnote.bold())
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Format.kilometres(session.tracker.distanceAlong))
                        .font(.headline)
                    Text("/ \(Format.kilometres(session.route.distance)) km")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: session.progress)
            }
        }
        .monospacedDigit()
        .frame(width: 104, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }

    private var gpsMessage: String? {
        switch session.gps.status {
        case .searching: "Finding GPS…"
        case .weakSignal: "Weak GPS signal"
        case .denied: "Location is off. Allow it in Settings › Privacy & Security."
        case .tracking: nil
        }
    }

    /// Shows you and the nearest point of the route together.
    private func frameWayBack() {
        session.showsWayBack = false
        guard let you = session.location?.coordinate,
              let trail = session.tracker.position?.nearestPoint.coordinate
        else { return }
        let a = MKMapPoint(you)
        let b = MKMapPoint(trail)
        let margin = 40 * MKMapPointsPerMeterAtLatitude(you.latitude)
        let both = MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        camera = .rect(both.insetBy(dx: -margin, dy: -margin))
    }
}
