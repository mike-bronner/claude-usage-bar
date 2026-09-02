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
}
