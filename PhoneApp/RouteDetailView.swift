import MapKit
import SwiftUI
import TrailKit

struct RouteDetailView: View {
    let route: GPXRoute
    @Environment(WatchTransferService.self) private var watch
    @Environment(OfflineMapService.self) private var maps
    @AppStorage(OfflineMapService.marginKey) private var margin = OfflineMapService.defaultMargin

    var body: some View {
        List {
            Section {
                Map(initialPosition: .automatic) {
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(.black.opacity(0.5), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: route.coordinates)
                        .stroke(.trail, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    if let start = route.points.first {
                        Marker("Start", systemImage: "flag.fill", coordinate: start.coordinate)
                    }
                    ForEach(route.waypoints, id: \.self) { waypoint in
                        Marker(waypoint.name, systemImage: "mappin", coordinate: waypoint.point.coordinate)
                            .tint(.secondary)
                    }
                }
                .mapStyle(.trail(elevation: .realistic))
                .frame(height: 320)
                .listRowInsets(EdgeInsets())
            }

            Section {
                LabeledContent("Distance", value: "\(Format.kilometres(route.distance)) km")
                LabeledContent("Ascent", value: "\(Format.metres(route.elevationGain)) m")
                LabeledContent("Type", value: route.isLoop ? "Loop" : "One way")
                LabeledContent("Estimated time", value: Format.hoursMinutes(
                    FinishEstimate(profile: ElevationProfile(route: route)).timeToFinish(along: 0, elapsed: 0)))
                LabeledContent("Points", value: route.points.count.formatted())
                if !route.waypoints.isEmpty {
                    LabeledContent("Waypoints", value: route.waypoints.count.formatted())
                }
            }

            Section {
                Picker("Area", selection: $margin) {
                    ForEach(OfflineMapService.margins, id: \.self) { margin in
                        Text("\(Self.distance(margin)) around the route")
                    }
                }
                .disabled(maps.downloading.contains(route.id))
                if maps.downloading.contains(route.id) {
                    HStack {
                        ProgressView()
                        Text("Downloading map data…")
                            .foregroundStyle(.secondary)
                    }
                } else if let map = route.map {
                    LabeledContent("Paths and tracks", value: map.features.count { $0.kind == .path || $0.kind == .track }.formatted())
                    LabeledContent("Contour lines", value: map.contourInterval.map { "Every \(Format.metres($0)) m" } ?? "None")
                    LabeledContent("Hill shading", value: map.shading == nil ? "None" : "Included")
                    LabeledContent("Downloaded", value: map.downloaded.formatted(date: .abbreviated, time: .omitted))
                    if (map.margin ?? 600) != margin {
                        Text("This map covers \(Self.distance(map.margin ?? 600)) around the route. Update it to get the new area.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Update Map") { Task { await maps.download(route) } }
                } else {
                    Button(maps.failed.contains(route.id) ? "Try Again" : "Download Offline Map") {
                        Task { await maps.download(route) }
                    }
                }
            } header: {
                Text("Offline Map")
            } footer: {
                Text(mapFooter)
            }

            Section {
                Button {
                    watch.send(route)
                } label: {
                    Label(sendTitle, systemImage: "applewatch")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.onAccent)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!watch.isWatchReady || isSending)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text(sendFooter)
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isSending: Bool { watch.sending.contains(route.id) }

    private var mapFooter: String {
        if maps.failed.contains(route.id) {
            "Couldn't download the map data. Check your connection; the OpenStreetMap server is sometimes busy."
        } else {
            "Paths, tracks, roads, water, landmarks, contour lines and hill shading, drawn on your Watch when there's no signal. A bigger area takes longer to download. If you leave the app, the download carries on. Map data © OpenStreetMap contributors. \(Terrain.attribution)."
        }
    }

    private static func distance(_ metres: Double) -> String {
        metres < 1000 ? "\(Format.metres(metres)) m" : "\((metres / 1000).formatted()) km"
    }

    private var sendTitle: String {
        if isSending { "Sending…" }
        else if watch.routesOnWatch.contains(route.id) { "Send Again" }
        else { "Send to Apple Watch" }
    }

    private var sendFooter: String {
        if !watch.isWatchReady {
            "Pair an Apple Watch and install TrailWatch on it to send routes."
        } else if watch.routesOnWatch.contains(route.id) {
            "On your Apple Watch, ready to hike without your iPhone."
        } else {
            "If your Watch is out of range, the route arrives the next time it's nearby."
        }
    }
}
