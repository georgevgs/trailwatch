import CoreGraphics
import Foundation
import ImageIO

/// One web-map tile (the slippy-map scheme).
public struct TileID: Hashable, Sendable {
    public let zoom: Int
    public let x: Int
    public let y: Int
}

/// Elevation from Terrain Tiles (Mapzen, on AWS Open Data). Heights are encoded in the PNG
/// colours ("Terrarium").
public enum Terrain {
    /// Shown wherever the contours are, as the data's terms ask.
    public static let attribution = "Elevation: Terrain Tiles by Mapzen (SRTM, EU-DEM © Copernicus, USGS and others)"

    public static func url(for tile: TileID) -> URL {
        URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/\(tile.zoom)/\(tile.x)/\(tile.y).png")!
    }

    /// Tiles covering `box` at zoom 13 (~15 m a pixel), or coarser for big areas.
    public static func tiles(covering box: BoundingBox) -> [TileID] {
        for zoom in [13, 12, 11] {
            let tiles = tiles(covering: box, zoom: zoom)
            if tiles.count <= 25 { return tiles }
        }
        return tiles(covering: box, zoom: 10)
    }

    static func tiles(covering box: BoundingBox, zoom: Int) -> [TileID] {
        let projection = WebMercator(zoom: zoom)
        let left = Int(projection.x(longitude: box.west) / 256), right = Int(projection.x(longitude: box.east) / 256)
        let top = Int(projection.y(latitude: box.north) / 256), bottom = Int(projection.y(latitude: box.south) / 256)
        return (top...bottom).flatMap { y in (left...right).map { x in TileID(zoom: zoom, x: x, y: y) } }
    }

    /// Terrarium encoding: metres = red × 256 + green + blue / 256 − 32768.
    static func elevation(red: UInt8, green: UInt8, blue: UInt8) -> Double {
        Double(red) * 256 + Double(green) + Double(blue) / 256 - 32768
    }

    /// Contour lines and hill shading for a map.
    public struct Relief: Sendable {
        /// Metres between contour lines.
        public var contourInterval: Double
        public var contours: [TrailMap.Feature]
        public var shading: TrailMap.Shading?
    }

    /// Contours and shading inside `box` from the downloaded tiles.
    public static func relief(from tiles: [TileID: Data], in box: BoundingBox) throws -> Relief {
        guard let zoom = tiles.keys.first?.zoom else { return Relief(contourInterval: 0, contours: []) }
        let grid = try ElevationGrid(tiles: tiles, box: box, projection: WebMercator(zoom: zoom))
        let (interval, contours) = contours(in: grid)
        return Relief(contourInterval: interval, contours: contours, shading: Hillshade.shading(of: grid))
    }

    /// Contour lines with heights, each running with higher ground on its left so labels can face uphill.
    /// The interval grows with the relief, from 10 m to 100 m.
    static func contours(in grid: ElevationGrid) -> (interval: Double, features: [TrailMap.Feature]) {
        guard let low = grid.values.min(), let high = grid.values.max() else { return (0, []) }

        let relief = Double(high - low)
        let interval: Double = relief <= 250 ? 10 : relief <= 800 ? 20 : relief <= 2000 ? 50 : 100
        var features: [TrailMap.Feature] = []
        var level = (Double(low) / interval).rounded(.up) * interval
        while level <= Double(high) {
            for line in Isolines.lines(in: grid, at: level) {
                let simplified = Isolines.simplify(line, tolerance: 0.5)
                guard simplified.count >= 3 else { continue }
                let oriented = Isolines.uphillOnLeft(simplified, in: grid, at: level)
                features.append(TrailMap.Feature(
                    kind: .contour, elevation: level, points: oriented.map(grid.coordinate)))
            }
            level += interval
        }
        return (interval, features)
    }
}

/// Shaded relief, lit from the north-west at 45° (GDAL's default).
enum Hillshade {
    static let azimuth = 315.0
    static let altitude = 45.0
    /// Steepens the slopes a little so moderate hills still read on a small screen.
    static let exaggeration = 1.5
    /// The longest side of the image; a big area is averaged down to this.
    static let maxSize = 768

    /// The shading as a see-through PNG with the area it covers.
    static func shading(of grid: ElevationGrid) -> TrailMap.Shading? {
        let factor = Int((Double(max(grid.width, grid.height)) / Double(maxSize)).rounded(.up))
        let small = factor > 1 ? grid.averaged(by: factor) : grid
        let centreLatitude = grid.projection.latitude(y: Double(grid.originY) + Double(grid.height) / 2)
        let metresPerPixel = 40_075_016.686 * cos(centreLatitude * .pi / 180) / grid.projection.size * Double(factor)

        let flat = sin(altitude * .pi / 180)
        var rgba = [UInt8](repeating: 0, count: small.width * small.height * 4)
        for (index, light) in illumination(of: small, metresPerPixel: metresPerPixel, exaggeration: exaggeration).enumerated() {
            // Premultiplied: shadows are black, highlights white; flat ground stays clear.
            if light < flat {
                rgba[index * 4 + 3] = UInt8((flat - light) / flat * 0.55 * 255)
            } else {
                let alpha = UInt8((light - flat) / (1 - flat) * 0.3 * 255)
                rgba[index * 4] = alpha; rgba[index * 4 + 1] = alpha; rgba[index * 4 + 2] = alpha
                rgba[index * 4 + 3] = alpha
            }
        }
        guard let image = png(width: small.width, height: small.height, rgba: rgba) else { return nil }
        let p = grid.projection
        return TrailMap.Shading(image: image, bounds: BoundingBox(
            south: p.latitude(y: Double(grid.originY + grid.height)), west: p.longitude(x: Double(grid.originX)),
            north: p.latitude(y: Double(grid.originY)), east: p.longitude(x: Double(grid.originX + grid.width))))
    }

    /// Light per pixel from 0 to 1; flat ground is sin(altitude). Slopes use Horn's method.
    static func illumination(of grid: ElevationGrid, metresPerPixel: Double, exaggeration: Double = 1) -> [Double] {
        let sunEast = sin(azimuth * .pi / 180) * cos(altitude * .pi / 180)
        let sunNorth = cos(azimuth * .pi / 180) * cos(altitude * .pi / 180)
        let sunUp = sin(altitude * .pi / 180)
        func z(_ x: Int, _ y: Int) -> Double {
            grid.value(x: min(max(x, 0), grid.width - 1), y: min(max(y, 0), grid.height - 1))
        }
        var light = [Double](repeating: 0, count: grid.width * grid.height)
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                // Rows run north to south, so north is y − 1.
                let east = ((z(x + 1, y - 1) + 2 * z(x + 1, y) + z(x + 1, y + 1))
                    - (z(x - 1, y - 1) + 2 * z(x - 1, y) + z(x - 1, y + 1))) * exaggeration / (8 * metresPerPixel)
                let north = ((z(x - 1, y - 1) + 2 * z(x, y - 1) + z(x + 1, y - 1))
                    - (z(x - 1, y + 1) + 2 * z(x, y + 1) + z(x + 1, y + 1))) * exaggeration / (8 * metresPerPixel)
                // The surface normal is (−east, −north, 1); light is its cosine with the sun's direction.
                let lit = (-east * sunEast - north * sunNorth + sunUp) / (1 + east * east + north * north).squareRoot()
                light[y * grid.width + x] = max(0, lit)
            }
        }
        return light
    }

    static func png(width: Int, height: Int, rgba: [UInt8]) -> Data? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// Web Mercator pixel coordinates at a zoom: x east, y south, 256 pixels per tile.
struct WebMercator {
    let size: Double

    init(zoom: Int) {
        size = 256 * pow(2, Double(zoom))
    }

    func x(longitude: Double) -> Double { (longitude + 180) / 360 * size }

    func y(latitude: Double) -> Double {
        (1 - asinh(tan(latitude * .pi / 180)) / .pi) / 2 * size
    }

    func longitude(x: Double) -> Double { x / size * 360 - 180 }

    func latitude(y: Double) -> Double {
        atan(sinh(.pi * (1 - 2 * y / size))) * 180 / .pi
    }
}

/// Heights on a regular grid of map pixels, cut to a bounding box.
struct ElevationGrid {
    enum Failure: Error {
        case missingTile, unreadableTile
    }

    let width: Int
    let height: Int
    /// Row by row, from the north-west corner.
    var values: [Float]
    /// The global pixel of `values[0]`.
    let originX: Int
    let originY: Int
    let projection: WebMercator

    init(width: Int, height: Int, values: [Float], originX: Int = 0, originY: Int = 0, projection: WebMercator = WebMercator(zoom: 0)) {
        self.width = width
        self.height = height
        self.values = values
        self.originX = originX
        self.originY = originY
        self.projection = projection
    }

    init(tiles: [TileID: Data], box: BoundingBox, projection: WebMercator) throws {
        let left = Int(projection.x(longitude: box.west)), right = Int(projection.x(longitude: box.east))
        let top = Int(projection.y(latitude: box.north)), bottom = Int(projection.y(latitude: box.south))
        self.init(width: right - left + 1, height: bottom - top + 1,
                  values: Array(repeating: 0, count: (right - left + 1) * (bottom - top + 1)),
                  originX: left, originY: top, projection: projection)

        let zoom = tiles.keys.first?.zoom ?? 0
        for tileY in (top / 256)...(bottom / 256) {
            for tileX in (left / 256)...(right / 256) {
                guard let data = tiles[TileID(zoom: zoom, x: tileX, y: tileY)] else { throw Failure.missingTile }
                let tile = try Self.decode(data)
                for y in max(top, tileY * 256)...min(bottom, tileY * 256 + 255) {
                    for x in max(left, tileX * 256)...min(right, tileX * 256 + 255) {
                        values[(y - top) * width + (x - left)] = tile[(y - tileY * 256) * 256 + (x - tileX * 256)]
                    }
                }
            }
        }
    }

    func value(x: Int, y: Int) -> Double { Double(values[y * width + x]) }

    /// The height between pixels, bilinear, clamped to the grid.
    func interpolated(at point: CGPoint) -> Double {
        let x = min(max(point.x, 0), Double(width - 1)), y = min(max(point.y, 0), Double(height - 1))
        let x0 = Int(x), y0 = Int(y), x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let tx = x - Double(x0), ty = y - Double(y0)
        let top = value(x: x0, y: y0) * (1 - tx) + value(x: x1, y: y0) * tx
        let bottom = value(x: x0, y: y1) * (1 - tx) + value(x: x1, y: y1) * tx
        return top * (1 - ty) + bottom * ty
    }

    /// The grid with each `factor` × `factor` block of pixels averaged into one.
    func averaged(by factor: Int) -> ElevationGrid {
        let smallWidth = (width + factor - 1) / factor, smallHeight = (height + factor - 1) / factor
        var sums = [Float](repeating: 0, count: smallWidth * smallHeight)
        var counts = [Float](repeating: 0, count: smallWidth * smallHeight)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y / factor) * smallWidth + x / factor
                sums[index] += values[y * width + x]
                counts[index] += 1
            }
        }
        return ElevationGrid(
            width: smallWidth, height: smallHeight, values: zip(sums, counts).map { $0 / $1 },
            originX: originX, originY: originY, projection: projection)
    }

    /// The latitude and longitude of a point in grid coordinates (pixel centres at whole numbers).
    func coordinate(_ point: CGPoint) -> TrailMap.Point {
        TrailMap.Point(
            latitude: projection.latitude(y: Double(originY) + point.y + 0.5),
            longitude: projection.longitude(x: Double(originX) + point.x + 0.5))
    }

    /// Heights from a 256 × 256 Terrarium PNG. Reads raw bytes so colour management can't shift them.
    static func decode(_ data: Data) throws -> [Float] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == 256, image.height == 256, image.bitsPerComponent == 8,
              let bytes = image.dataProvider?.data as Data?
        else { throw Failure.unreadableTile }
        let stride = image.bitsPerPixel / 8
        let alphaFirst = [.first, .premultipliedFirst, .noneSkipFirst].contains(image.alphaInfo)
        let offset = alphaFirst ? 1 : 0
        return bytes.withUnsafeBytes { raw in
            (0..<256 * 256).map { index in
                let pixel = (index / 256) * image.bytesPerRow + (index % 256) * stride + offset
                return Float(Terrain.elevation(red: raw[pixel], green: raw[pixel + 1], blue: raw[pixel + 2]))
            }
        }
    }
}

/// Marching squares: the lines where a grid crosses a height, joined into polylines.
enum Isolines {
    /// A cell edge: the horizontal one from (x, y) to (x + 1, y), or the vertical one to (x, y + 1).
    private struct Edge: Hashable {
        let x: Int
        let y: Int
        let isVertical: Bool
    }

    static func lines(in grid: ElevationGrid, at level: Double) -> [[CGPoint]] {
        var segments: [(Edge, Edge)] = []
        for y in 0..<grid.height - 1 {
            for x in 0..<grid.width - 1 {
                let topLeft = grid.value(x: x, y: y), topRight = grid.value(x: x + 1, y: y)
                let bottomRight = grid.value(x: x + 1, y: y + 1), bottomLeft = grid.value(x: x, y: y + 1)
                let index = (topLeft >= level ? 8 : 0) | (topRight >= level ? 4 : 0)
                    | (bottomRight >= level ? 2 : 0) | (bottomLeft >= level ? 1 : 0)
                let top = Edge(x: x, y: y, isVertical: false), bottom = Edge(x: x, y: y + 1, isVertical: false)
                let left = Edge(x: x, y: y, isVertical: true), right = Edge(x: x + 1, y: y, isVertical: true)
                // Saddles are settled by the cell's average height.
                let centreIsHigh = (topLeft + topRight + bottomRight + bottomLeft) / 4 >= level
                switch index {
                case 1, 14: segments.append((left, bottom))
                case 2, 13: segments.append((bottom, right))
                case 3, 12: segments.append((left, right))
                case 4, 11: segments.append((top, right))
                case 6, 9: segments.append((top, bottom))
                case 7, 8: segments.append((left, top))
                case 5:
                    if centreIsHigh { segments += [(left, top), (bottom, right)] }
                    else { segments += [(top, right), (left, bottom)] }
                case 10:
                    if centreIsHigh { segments += [(top, right), (left, bottom)] }
                    else { segments += [(left, top), (bottom, right)] }
                default:
                    break
                }
            }
        }
        return join(segments).map { $0.map { point(on: $0, in: grid, at: level) } }
    }

    /// Links segments that share an edge into the longest runs; rings come back closed.
    private static func join(_ segments: [(Edge, Edge)]) -> [[Edge]] {
        var touching: [Edge: [Int]] = [:]
        for (index, segment) in segments.enumerated() {
            touching[segment.0, default: []].append(index)
            touching[segment.1, default: []].append(index)
        }
        var used = Array(repeating: false, count: segments.count)

        func extend(from edge: Edge) -> [Edge] {
            var run: [Edge] = []
            var current = edge
            while let next = touching[current]?.first(where: { !used[$0] }) {
                used[next] = true
                current = segments[next].0 == current ? segments[next].1 : segments[next].0
                run.append(current)
            }
            return run
        }

        var lines: [[Edge]] = []
        for index in segments.indices where !used[index] {
            used[index] = true
            let forward = extend(from: segments[index].1)
            let backward = extend(from: segments[index].0)
            lines.append(backward.reversed() + [segments[index].0, segments[index].1] + forward)
        }
        return lines
    }

    /// Where `level` crosses an edge, measured from the same end so neighbouring cells agree.
    private static func point(on edge: Edge, in grid: ElevationGrid, at level: Double) -> CGPoint {
        let a = grid.value(x: edge.x, y: edge.y)
        let b = edge.isVertical ? grid.value(x: edge.x, y: edge.y + 1) : grid.value(x: edge.x + 1, y: edge.y)
        let t = b == a ? 0.5 : (level - a) / (b - a)
        return edge.isVertical
            ? CGPoint(x: Double(edge.x), y: Double(edge.y) + t)
            : CGPoint(x: Double(edge.x) + t, y: Double(edge.y))
    }

    /// The line, reversed if needed so that, walking along it, the ground to the left is higher.
    /// Checks one pixel to the side of its longest segment.
    static func uphillOnLeft(_ line: [CGPoint], in grid: ElevationGrid, at level: Double) -> [CGPoint] {
        guard let index = line.indices.dropLast().max(by: {
            hypot(line[$0 + 1].x - line[$0].x, line[$0 + 1].y - line[$0].y)
                < hypot(line[$1 + 1].x - line[$1].x, line[$1 + 1].y - line[$1].y)
        }) else { return line }
        let a = line[index], b = line[index + 1]
        let length = hypot(b.x - a.x, b.y - a.y)
        guard length > 0 else { return line }
        // Rows run north to south, so the left of (dx, dy) is (dy, −dx).
        let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let left = CGPoint(x: middle.x + (b.y - a.y) / length, y: middle.y - (b.x - a.x) / length)
        return grid.interpolated(at: left) >= level ? line : line.reversed()
    }

    /// Douglas–Peucker: drops points within `tolerance` of the line through their neighbours.
    static func simplify(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = Array(repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last > first + 1 else { continue }
            let (a, b) = (points[first], points[last])
            var farthest = first, distance = 0.0
            for index in first + 1..<last {
                let d = distanceToSegment(points[index], a, b)
                if d > distance { (farthest, distance) = (index, d) }
            }
            if distance > tolerance {
                keep[farthest] = true
                stack += [(first, farthest), (farthest, last)]
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    private static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
