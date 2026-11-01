import SwiftUI
import TrailKit

/// The route's shape, north up, on the terrain colour. Drawn locally, so it needs no map tiles.
struct RouteThumbnail: View {
    let route: GPXRoute

    var body: some View {
        Canvas { context, size in
            let points = Self.fit(route.points, in: CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8))
            let line = Path { $0.addLines(points) }
            context.stroke(line, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            context.stroke(line, with: .color(.accentColor), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            if let start = points.first {
                context.fill(Path(ellipseIn: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6)), with: .color(.white))
            }
        }
        .background(.terrain, in: .rect(cornerRadius: 12))
        .accessibilityHidden(true)
    }

    /// Projects points flat (longitude × cos(latitude)) and fits them in `rect` without stretching.
    private static func fit(_ points: [RoutePoint], in rect: CGRect) -> [CGPoint] {
        guard let first = points.first else { return [] }
        let xScale = cos(first.latitude * .pi / 180)
        let flat = points.map { CGPoint(x: $0.longitude * xScale, y: -$0.latitude) }
        let xs = flat.map(\.x), ys = flat.map(\.y)
        let minX = xs.min()!, minY = ys.min()!
        let width = max(xs.max()! - minX, 1e-9), height = max(ys.max()! - minY, 1e-9)
        let scale = min(rect.width / width, rect.height / height)
        let left = rect.minX + (rect.width - width * scale) / 2
        let top = rect.minY + (rect.height - height * scale) / 2
        return flat.map { CGPoint(x: left + ($0.x - minX) * scale, y: top + ($0.y - minY) * scale) }
    }
}
