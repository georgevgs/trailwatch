import ImageIO
import SwiftUI
import TrailKit

/// Map data turned into shapes once, in flat metres, so each frame only moves and scales them.
/// Lines are grouped into 500 m cells and areas keep their bounds, so a frame draws only what's near the screen.
struct TrailMapLayers {
    struct Place {
        let kind: TrailMap.Kind
        let point: CGPoint
        let label: String?
    }

    /// The lines in one cell.
    struct Lines {
        var streams = Path()
        var majorRoads = Path()
        var roads = Path()
        var tracks = Path()
        var paths = Path()
        var contours = Path()
        /// Every fifth contour, drawn bolder so heights can be read off at a glance.
        var indexContours = Path()
    }

    struct Area {
        let path: Path
        let bounds: CGRect
    }

    let projection: MapProjection
    private let cells = MapCells(size: 500)
    private var lines: [MapCells.Key: Lines] = [:]
    private(set) var woods: [Area] = []
    private(set) var water: [Area] = []
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
        func add(_ points: [CGPoint], to line: WritableKeyPath<Lines, Path>) {
            for run in cells.runs(points) {
                lines[run.key, default: Lines()][keyPath: line].addLines(run.points)
            }
        }
        func area(_ points: [CGPoint]) -> Area {
            let path = Path { $0.addLines(points); $0.closeSubpath() }
            return Area(path: path, bounds: path.boundingRect)
        }
        for feature in map.features {
            let points = feature.points.map { projection.point(latitude: $0.latitude, longitude: $0.longitude) }
            switch feature.kind {
            case .wood: woods.append(area(points))
            case .water: water.append(area(points))
            case .stream: add(points, to: \.streams)
            case .majorRoad: add(points, to: \.majorRoads)
            case .road: add(points, to: \.roads)
            case .track: add(points, to: \.tracks)
            case .path: add(points, to: \.paths)
            case .contour:
                let isIndex = map.contourInterval.map { (feature.elevation ?? 0).truncatingRemainder(dividingBy: $0 * 5) == 0 } ?? false
                if isIndex {
                    add(points, to: \.indexContours)
                    if let elevation = feature.elevation {
                        contourLabels += ContourLabel.along(points, every: Self.contourLabelSpacing)
                            .map { ($0, Format.metres(elevation)) }
                    }
                } else {
                    add(points, to: \.contours)
                }
            case .peak:
                let height = feature.elevation.map { " \(Format.metres($0)) m" } ?? ""
                places.append(Place(kind: .peak, point: points[0], label: feature.name.map { $0 + height }))
            case .spring, .drinkingWater, .viewpoint, .shelter:
                places.append(Place(kind: feature.kind, point: points[0], label: nil))
            }
        }
    }

    /// The lines of every cell that could show inside `rect` (flat metres).
    func lines(near rect: CGRect) -> [Lines] {
        cells.keys(around: rect).compactMap { lines[$0] }
    }

    func point(_ routePoint: RoutePoint) -> CGPoint {
        projection.point(routePoint)
    }
}
