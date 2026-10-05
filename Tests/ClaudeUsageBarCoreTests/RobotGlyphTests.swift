import AppKit
import XCTest
@testable import ClaudeUsageBarCore

final class RobotGlyphTests: XCTestCase {
    func testAppIconIsSquareAtRequestedPixels() throws {
        // A Retina display would double these if the drawing went through lockFocus.
        for pixels in [16, 512, 1024] {
            let bitmap = RobotGlyph.appIcon(pixels: pixels)
            XCTAssertEqual(bitmap.pixelsWide, pixels)
            XCTAssertEqual(bitmap.pixelsHigh, pixels)
            XCTAssertNotNil(bitmap.representation(using: .png, properties: [:]))
        }
    }

    func testAppIconPaintsTileAndLeavesCornersClear() throws {
        let bitmap = RobotGlyph.appIcon(pixels: 256)
        // Outside the tile (the outer 10%) stays transparent; the tile's own corner is painted.
        XCTAssertEqual(bitmap.colorAt(x: 2, y: 2)?.alphaComponent, 0)
        XCTAssertEqual(bitmap.colorAt(x: 128, y: 30)?.alphaComponent, 1)
    }

    /// The app icon draws the default `.face`. Samples the robot inside the rendered icon, so a
    /// change to the shared drawing that alters the app icon goes red here.
    func testAppIconShowsThePlainFace() throws {
        let pixels = 1024
        let bitmap = RobotGlyph.appIcon(pixels: pixels)
        // The glyph box inside the tile, as `appIcon` lays it out: tile 80%, inset 16% of the tile.
        let tile = CGFloat(pixels) * 0.8
        let box = CGFloat(pixels) * 0.1 + tile * 0.16
        let scale = (tile - 2 * tile * 0.16) / RobotGlyph.designSize
        func color(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
            try XCTUnwrap(bitmap.colorAt(x: Int(box + x * scale), y: pixels - Int(box + y * scale)))
        }
        // Holes go through the tile: both eyes and the mouth, at their centers and near every edge
        // (the outer eye edges are what the "$" face would fill).
        let holes = [(6.75, 8.75), (11.25, 8.75), (5.75, 8.75), (7.75, 8.75), (10.25, 8.75), (12.25, 8.75),
                     (6.75, 7.75), (6.75, 9.75), (11.25, 7.75), (11.25, 9.75),
                     (9, 5.25), (6.25, 5.25), (11.75, 5.25), (9, 4.6), (9, 5.9)]
        for (x, y) in holes {
            XCTAssertEqual(try color(x, y).alphaComponent, 0, "hole at (\(x), \(y))")
        }
        // The head, ears, and antenna are green, and the gap beside a slash would be head.
        let green = try XCTUnwrap(NSColor.systemGreen.usingColorSpace(.deviceRGB))
        for (x, y) in [(9, 12), (9.8, 9.55), (1.75, 8), (9, 16)] {
            let pixel = try XCTUnwrap(color(x, y).usingColorSpace(.deviceRGB))
            XCTAssertEqual(pixel.alphaComponent, 1, "glyph at (\(x), \(y))")
            XCTAssertEqual(pixel.greenComponent, green.greenComponent, accuracy: 0.02, "green at (\(x), \(y))")
            XCTAssertEqual(pixel.redComponent, green.redComponent, accuracy: 0.02, "green at (\(x), \(y))")
        }
        // The tile shows between the ear and the head, so the robot sits where it always did.
        XCTAssertEqual(try color(2.75, 8).alphaComponent, 1)
        XCTAssertLessThan(try XCTUnwrap(color(2.75, 8).usingColorSpace(.deviceRGB)).greenComponent, 0.3)
    }

    func testGlyphPunchesOutEyesOnAnyBackground() {
        // Draw the glyph alone at 180 px and check an eye pixel is transparent while the head is not.
        let side = 180
        let bitmap = RobotGlyph.bitmapCanvas(pixels: side)
        RobotGlyph.drawInto(bitmap) {
            RobotGlyph.draw(in: NSRect(x: 0, y: 0, width: side, height: side), tint: .systemGreen)
        }
        // Bitmap rows count from the top; the design box is 18 units, scale 10.
        let eye = (x: 68, y: side - 88)     // design (6.75, 8.75)
        let head = (x: 90, y: side - 120)   // design (9, 12)
        XCTAssertEqual(bitmap.colorAt(x: eye.x, y: eye.y)?.alphaComponent, 0)
        XCTAssertEqual(bitmap.colorAt(x: head.x, y: head.y)?.alphaComponent, 1)
    }

    /// Alpha of the glyph drawn alone at scale 10, sampled at design coordinates (y up).
    private func alpha(_ style: RobotGlyph.Style, _ x: CGFloat, _ y: CGFloat) -> CGFloat? {
        let side = 180
        let bitmap = RobotGlyph.bitmapCanvas(pixels: side)
        RobotGlyph.drawInto(bitmap) {
            RobotGlyph.draw(in: NSRect(x: 0, y: 0, width: side, height: side), tint: .systemRed, style: style)
        }
        return bitmap.colorAt(x: Int(x * 10), y: side - Int(y * 10))?.alphaComponent
    }

    func testDollarFaceFillsEyesAndMouthAndPunchesADollar() {
        // The "$" overlaps the eye centers, so the eyes are sampled at their outer edges.
        XCTAssertEqual(alpha(.face, 5.75, 8.75), 0)
        XCTAssertEqual(alpha(.face, 12.25, 8.75), 0)
        XCTAssertEqual(alpha(.face, 6.25, 5.25), 0)
        XCTAssertEqual(alpha(.dollar, 5.75, 8.75), 1, "the left eye's outer edge is filled")
        XCTAssertEqual(alpha(.dollar, 12.25, 8.75), 1, "the right eye's outer edge is filled")
        XCTAssertEqual(alpha(.dollar, 6.25, 5.25), 1, "the mouth's left end is filled")
        XCTAssertEqual(alpha(.dollar, 9, 11.5), 0, "the dollar's bar is punched out")
        XCTAssertEqual(alpha(.dollar, 1.75, 8), 1, "the ears stay")
        XCTAssertEqual(alpha(.dollar, 9, 16), 1, "the antenna stays")
    }

    func testSlashCrossesTheGlyphWithAClearGap() {
        // The slash runs (2, 16) to (16, 1.5); (9, 8.75) sits on it, (9.8, 9.55) in the gap beside it.
        XCTAssertEqual(alpha(.slashed, 9, 8.75), 1, "the slash is painted")
        XCTAssertEqual(alpha(.slashed, 9.8, 9.55), 0, "the gap is cut through the head")
        XCTAssertEqual(alpha(.face, 9.8, 9.55), 1, "the same point is head without the slash")
        XCTAssertEqual(alpha(.slashed, 6.75, 8.75), 0, "the face keeps its eyes under the slash")
        XCTAssertEqual(alpha(.slashed, 12, 12), 1, "the head away from the slash stays")
    }
}
