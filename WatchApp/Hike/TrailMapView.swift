import SwiftUI
import TrailKit

/// The route over OpenStreetMap paths, tracks, roads, water and woods, drawn from the data that came
/// with it, so it works with no signal. The Digital Crown zooms and dragging pans.
struct TrailMapView: View {
    let session: HikeSession
    let layers: TrailMapLayers
    /// Keeps you in the middle; dragging turns it off.
    @Binding var follows: Bool

    /// 0 shows 4 km across the screen; each step halves that.
    @State private var zoom = 2.0
    @State private var center = CGPoint.zero
    @State private var dragStart: CGPoint?
    @State private var width = 200.0
    @FocusState private var isFocused: Bool
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let split = session.tracker.split(at: session.tracker.distanceAlong)
        let walked = split.walked.map(layers.point)
        let ahead = split.ahead.map(layers.point)
        let start = session.route.points.first.map(layers.point)
        let waypoints = session.route.waypoints.map { (point: layers.point($0.point), name: $0.name) }
        let you = youPoint
        let accuracy = session.location?.horizontalAccuracy ?? 0
        let focus = focusPoint
        // Wrist down (Always On) or in Low Power Mode, draw only what you navigate by: less work per
        // frame and no large lit areas, as Apple's Always On guidance asks. The map redraws with every
        // GPS fix, so reading Low Power Mode here keeps up with it.
        let isSimple = isLuminanceReduced || ProcessInfo.processInfo.isLowPowerModeEnabled
        let showsLabels = zoom >= 2 && !isSimple

        Canvas { context, size in
            let scale = size.width / metresAcross
            let transform = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -focus.x, y: -focus.y)

            func stroke(_ path: Path, _ color: Color, _ width: CGFloat, dash: [CGFloat] = []) {
                context.stroke(
                    path.applying(transform), with: .color(color),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
            }
            func line(_ points: [CGPoint]) -> Path { Path { $0.addLines(points) } }
            func dot(_ point: CGPoint, _ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            }

            if !isSimple {
                context.fill(layers.woods.applying(transform), with: .color(.mapWood))
                context.fill(layers.water.applying(transform), with: .color(.mapWater))
                if let shading = layers.shading {
                    context.draw(shading.image, in: shading.rect.applying(transform))
                }
                stroke(layers.contours, .mapContour, 0.6)
                stroke(layers.indexContours, .mapContour, 1.1)
                stroke(layers.streams, .mapStream, 1.5)
                stroke(layers.majorRoads, .mapMajorRoad, 3)
                stroke(layers.roads, .mapRoad, 2)
            }
            stroke(layers.tracks, .mapTrack, 1.5, dash: [4, 3])
            stroke(layers.paths, .mapPath, 1.2, dash: [3, 2])

            stroke(line(walked + ahead.dropFirst()), .black.opacity(0.55), 7)
            stroke(line(ahead), .accentColor.opacity(0.42), 4)
            stroke(line(walked), .accentColor, 4)

            for place in isSimple ? [] : layers.places {
                let p = place.point.applying(transform)
                switch place.kind {
                case .peak:
                    let peak = Path { path in
                        path.move(to: CGPoint(x: p.x, y: p.y - 4))
                        path.addLine(to: CGPoint(x: p.x + 4, y: p.y + 3))
                        path.addLine(to: CGPoint(x: p.x - 4, y: p.y + 3))
                        path.closeSubpath()
                    }
                    context.fill(peak, with: .color(.white.opacity(0.85)))
                    if showsLabels, let label = place.label {
                        context.draw(
                            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.75)),
                            at: CGPoint(x: p.x, y: p.y + 5), anchor: .top)
                    }
                case .spring, .drinkingWater:
                    context.fill(dot(p, 3), with: .color(.mapStream))
                case .viewpoint:
                    context.stroke(dot(p, 3), with: .color(.white.opacity(0.85)), lineWidth: 1.5)
                default:
                    context.fill(Path(CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(.mapTrack))
                }
            }

            for waypoint in waypoints {
                let p = waypoint.point.applying(transform)
                context.fill(dot(p, 5), with: .color(.black.opacity(0.6)))
                context.fill(dot(p, 3.5), with: .color(.mapWaypoint))
                if showsLabels {
                    context.draw(
                        Text(waypoint.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.mapWaypoint),
                        at: CGPoint(x: p.x, y: p.y + 6), anchor: .top)
                }
            }

            if let start {
                let p = start.applying(transform)
                context.fill(dot(p, 5), with: .color(.terrain))
                context.fill(dot(p, 3.5), with: .color(.white))
            }

            if let you {
                let p = you.applying(transform)
                context.fill(dot(p, max(0, accuracy * scale)), with: .color(.mapYou.opacity(0.18)))
                context.fill(dot(p, 6.5), with: .color(.white))
                context.fill(dot(p, 4.5), with: .color(.mapYou))
            }
        }
        .background(.terrain)
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width = $0 }
        .gesture(drag)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .digitalCrownRotation(
            $zoom, from: 0, through: 5, by: 0.25, sensitivity: .medium,
            isContinuous: false, isHapticFeedbackEnabled: true)
        .onAppear { isFocused = true }
        .onChange(of: session.showsOffRouteAlert) { isFocused = true }
        .onChange(of: session.showsWayBack) { _, shows in
            if shows { frameWayBack() }
        }
        .accessibilityElement()
        .accessibilityLabel("Trail map")
        .accessibilityValue("\(Format.metres(metresAcross)) metres across")
    }

    private var metresAcross: Double { 4000 / pow(2, zoom) }

    private var youPoint: CGPoint? {
        session.location.map { layers.projection.point(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
    }

    /// The map's middle, in metres; the origin is the middle of the downloaded area.
    private var focusPoint: CGPoint {
        follows ? (youPoint ?? .zero) : center
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let origin = dragStart ?? focusPoint
                dragStart = origin
                follows = false
                let metresPerPoint = metresAcross / width
                center = CGPoint(
                    x: origin.x - value.translation.width * metresPerPoint,
                    y: origin.y - value.translation.height * metresPerPoint)
            }
            .onEnded { _ in dragStart = nil }
    }

    /// Shows you and the nearest point of the route together.
    private func frameWayBack() {
        session.showsWayBack = false
        guard let you = youPoint, let trail = session.tracker.position?.nearestPoint else { return }
        let target = layers.point(trail)
        follows = false
        center = CGPoint(x: (you.x + target.x) / 2, y: (you.y + target.y) / 2)
        let span = max(hypot(you.x - target.x, you.y - target.y) * 2.5, 150)
        zoom = min(max(log2(4000 / span), 0), 5)
    }
}

private extension Color {
    static let mapWood = Color(red: 0x20 / 255, green: 0x33 / 255, blue: 0x27 / 255)
    static let mapWater = Color(red: 0x1D / 255, green: 0x3D / 255, blue: 0x52 / 255)
    static let mapStream = Color(red: 0x4A / 255, green: 0x9A / 255, blue: 0xD4 / 255)
    static let mapMajorRoad = Color(red: 0x8A / 255, green: 0x8F / 255, blue: 0x98 / 255)
    static let mapRoad = Color(red: 0x5E / 255, green: 0x64 / 255, blue: 0x6D / 255)
    static let mapTrack = Color(red: 0xA8 / 255, green: 0x9A / 255, blue: 0x74 / 255)
    static let mapPath = Color(red: 0xE2 / 255, green: 0xDA / 255, blue: 0xC8 / 255).opacity(0.75)
    static let mapContour = Color(red: 0xB0 / 255, green: 0x8A / 255, blue: 0x5E / 255).opacity(0.45)
    static let mapWaypoint = Color(red: 0xFF / 255, green: 0xF1 / 255, blue: 0xD6 / 255)
    static let mapYou = Color(red: 0x6E / 255, green: 0x7F / 255, blue: 0xFF / 255)
}
