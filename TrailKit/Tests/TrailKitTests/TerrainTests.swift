import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import TrailKit

struct TerrainTests {
    @Test func decodesTerrariumHeights() throws {
        #expect(Terrain.elevation(red: 128, green: 0, blue: 0) == 0)
        #expect(Terrain.elevation(red: 129, green: 22, blue: 128) == 278.5)

        // A real PNG round trip: 278.5 m everywhere.
        var pixels = [UInt8](repeating: 0, count: 256 * 256 * 3)
        for index in stride(from: 0, to: pixels.count, by: 3) {
            pixels[index] = 129; pixels[index + 1] = 22; pixels[index + 2] = 128
        }
        let image = try #require(CGImage(
            width: 256, height: 256, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: 256 * 3,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent))
        let png = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        let heights = try ElevationGrid.decode(png as Data)
        #expect(heights.count == 256 * 256)
        #expect(heights.allSatisfy { $0 == 278.5 })
    }

    @Test func findsTheTilesAroundKaisariani() {
        let box = BoundingBox(south: 37.955, west: 23.785, north: 37.970, east: 23.800)
        #expect(Terrain.tiles(covering: box) == [TileID(zoom: 13, x: 4637, y: 3160), TileID(zoom: 13, x: 4637, y: 3161)])

        let projection = WebMercator(zoom: 13)
        #expect(abs(projection.latitude(y: projection.y(latitude: 37.96)) - 37.96) < 1e-9)
        #expect(abs(projection.longitude(x: projection.x(longitude: 23.79)) - 23.79) < 1e-9)
    }

    @Test func tracesRingsRoundAHill() {
        // A cone 100 m high in the middle of a 41 × 41 grid, falling 5 m per cell.
        let size = 41
        let values = (0..<size * size).map { index -> Float in
            let x = Double(index % size - 20), y = Double(index / size - 20)
            return Float(max(0, 100 - 5 * (x * x + y * y).squareRoot()))
        }
        let grid = ElevationGrid(width: size, height: size, values: values)

        let rings = Isolines.lines(in: grid, at: 50)
        #expect(rings.count == 1)
        let ring = rings[0]
        #expect(ring.first == ring.last)
        // 50 m is 10 cells from the top.
        for point in ring {
            #expect(abs(hypot(point.x - 20, point.y - 20) - 10) < 0.3)
        }
        let simplified = Isolines.simplify(ring, tolerance: 0.5)
        #expect(simplified.count < ring.count)
        #expect(simplified.count >= 8)
    }

    @Test func stopsLinesAtTheGridEdge() {
        // A slope rising to the east: every contour runs north–south, edge to edge.
        let values = (0..<20 * 10).map { Float($0 % 20) * 10 }
        let lines = Isolines.lines(in: ElevationGrid(width: 20, height: 10, values: values), at: 55)
        #expect(lines.count == 1)
        #expect(lines[0].count == 10)
        #expect(lines[0].allSatisfy { abs($0.x - 5.5) < 1e-9 })
    }
}

struct HillshadeTests {
    /// A 9 × 9 grid rising `rise` metres per pixel to the east and `riseSouth` to the south.
    func slope(east rise: Float, south riseSouth: Float) -> ElevationGrid {
        ElevationGrid(width: 9, height: 9, values: (0..<81).map { Float($0 % 9) * rise + Float($0 / 9) * riseSouth + 500 })
    }

    @Test func lightsSlopesFacingTheNorthWest() {
        let flat = Hillshade.illumination(of: slope(east: 0, south: 0), metresPerPixel: 10)[40]
        #expect(abs(flat - sin(.pi / 4)) < 1e-9)

        // Rising to the south-east, the slope faces north-west, into the sun.
        let facingSun = Hillshade.illumination(of: slope(east: 5, south: 5), metresPerPixel: 10)[40]
        let facingAway = Hillshade.illumination(of: slope(east: -5, south: -5), metresPerPixel: 10)[40]
        #expect(facingSun > flat)
        #expect(facingAway < flat)
        // A cliff facing away gets no light at all.
        #expect(Hillshade.illumination(of: slope(east: -500, south: -500), metresPerPixel: 10)[40] == 0)
    }

    @Test func makesASeeThroughImageOfTheArea() throws {
        let grid = ElevationGrid(
            width: 20, height: 10, values: (0..<200).map { Float($0 % 20) * 8 },
            originX: 1_187_000, originY: 809_000, projection: WebMercator(zoom: 13))
        let shading = try #require(Hillshade.shading(of: grid))
        let image = try #require(CGImageSourceCreateWithData(shading.image as CFData, nil).flatMap {
            CGImageSourceCreateImageAtIndex($0, 0, nil)
        })
        #expect(image.width == 20)
        #expect(image.height == 10)
        #expect(shading.bounds.north > shading.bounds.south)
        #expect(shading.bounds.east > shading.bounds.west)
    }

    @Test func averagesBigAreasDown() {
        let grid = ElevationGrid(width: 5, height: 3, values: (0..<15).map(Float.init))
        let small = grid.averaged(by: 2)
        #expect(small.width == 3)
        #expect(small.height == 2)
        #expect(small.values[0] == (0 + 1 + 5 + 6) / 4)
        #expect(small.values[5] == 14)
    }
}
