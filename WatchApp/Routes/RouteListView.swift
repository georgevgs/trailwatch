import SwiftUI
import TrailKit

struct RouteListView: View {
    @Environment(RouteLibrary.self) private var library
    @AppStorage(HikeSession.offRouteDistanceKey) private var offRouteDistance = 40.0

    var body: some View {
        List {
            if let expiry = ProvisioningProfile.appExpirationDate, expiry.timeIntervalSinceNow < 3 * 86_400 {
                Label("Stops opening \(expiry, format: .relative(presentation: .named)). Reinstall before your next hike.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            ForEach(library.routes) { route in
                NavigationLink {
                    RouteDetailView(route: route)
                } label: {
                    row(route)
                }
            }
            .onDelete { offsets in
                for id in offsets.map({ library.routes[$0].id }) {
                    try? library.delete(id: id)
                }
            }
            .reorderable()

            Label("Add a GPX from TrailWatch on iPhone", systemImage: "iphone")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))

            Picker("Off-route alert", selection: $offRouteDistance) {
                ForEach([30.0, 40, 50, 75], id: \.self) { metres in
                    Text("\(Format.metres(metres)) m").tag(metres)
                }
            }
        }
        .reorderContainer(for: GPXRoute.self) { try? library.apply($0) }
        .navigationTitle("Routes")
    }

    private func row(_ route: GPXRoute) -> some View {
        HStack(spacing: 10) {
            RouteThumbnail(route: route)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.headline)
                    .lineLimit(3)
                Text("\(Format.kilometres(route.distance)) km · ↑ \(Format.metres(route.elevationGain)) m")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if library.hasMap(route.id) {
                    Label("Offline map", systemImage: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.done)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
