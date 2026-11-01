import ImageIO
import SwiftUI
import TrailKit

/// Map data turned into shapes once, in flat metres, so each frame only moves and scales them.
struct TrailMapLayers {
    struct Place {
        let kind: TrailMap.Kind
        let point: CGPoint
        let label: String?
    }

    let projection: MapProjection
    private(set) var woods = Path()
    private(set) var water = Path()
    private(set) var streams = Path()
    private(set) var majorRoads = Path()
    private(set) var roads = Path()
    private(set) var tracks = Path()
    private(set) var paths = Path()
    private(set) var contours = Path()
    /// Every fifth contour, drawn bolder so heights can be read off at a glance.
    private(set) var indexContours = Path()
    let hasContours: Bool
    /// Heights written along the index contours.
    private(set) var contourLabels: [(label: ContourLabel, text: String)] = []
    /// Metres between contour labels along a line.
    static let contourLabelSpacing = 250.0
    /// The shaded relief and where it goes, in the same flat metres as the lines.
    private(set) var shading: (image: Image, rect: CGRect)?
    private(set) var places: [Place] = []

    init(map: TrailMap) {
        projection = MapProjection(origin: map.bounds.center)
        hasContours = map.contourInterval != nil
        if let relief = map.shading,
           let source = CGImageSourceCreateWithData(relief.image as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let northWest = projection.point(latitude: relief.bounds.north, longitude: relief.bounds.west)
            let southEast = projection.point(latitude: relief.bounds.south, longitude: relief.bounds.east)
            shading = (Image(decorative: image, scale: 1).interpolation(.medium),
                       CGRect(x: northWest.x, y: northWest.y, width: southEast.x - northWest.x, height: southEast.y - northWest.y))
        }
        for feature in map.features {
            let points = feature.points.map { projection.point(latitude: $0.latitude, longitude: $0.longitude) }
            switch feature.kind {
            case .wood: woods.addLines(points); woods.closeSubpath()
            case .water: water.addLines(points); water.closeSubpath()
            case .stream: streams.addLines(points)
            case .majorRoad: majorRoads.addLines(points)
            case .road: roads.addLines(points)
            case .track: tracks.addLines(points)
            case .path: paths.addLines(points)
            case .contour:
                let isIndex = map.contourInterval.map { (feature.elevation ?? 0).truncatingRemainder(dividingBy: $0 * 5) == 0 } ?? false
                if isIndex {
                    indexContours.addLines(points)
                    if let elevation = feature.elevation {
                        contourLabels += ContourLabel.along(points, every: Self.contourLabelSpacing)
                            .map { ($0, Format.metres(elevation)) }
                    }
                } else {
                    contours.addLines(points)
                }
            case .peak:
                let height = feature.elevation.map { " \(Format.metres($0)) m" } ?? ""
                places.append(Place(kind: .peak, point: points[0], label: feature.name.map { $0 + height }))
            case .spring, .drinkingWater, .viewpoint, .shelter:
                places.append(Place(kind: feature.kind, point: points[0], label: nil))
            }
        }
    }

    func point(_ routePoint: RoutePoint) -> CGPoint {
        projection.point(routePoint)
    }
}
