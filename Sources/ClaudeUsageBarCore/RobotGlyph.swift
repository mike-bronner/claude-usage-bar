import AppKit

/// The robot: rounded head with punched-out eyes and mouth, ears, antenna. One drawing serves the
/// 18 pt menu bar item and the 1024 px app icon; coordinates are in an 18×18 design box.
public enum RobotGlyph {
    public static let designSize: CGFloat = 18

    /// Draws into `rect`, scaled uniformly from the design box. Features are holes so the glyph
    /// reads on any background.
    public static func draw(in rect: NSRect, tint: NSColor, dimmed: Bool = false) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        let scale = min(rect.width, rect.height) / designSize
        context.translateBy(x: rect.midX - designSize * scale / 2, y: rect.midY - designSize * scale / 2)
        context.scaleBy(x: scale, y: scale)

        tint.withAlphaComponent(dimmed ? 0.45 : 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 3, y: 2.5, width: 12, height: 10.5), xRadius: 3, yRadius: 3).fill()
        NSBezierPath(roundedRect: NSRect(x: 1, y: 6, width: 1.5, height: 4), xRadius: 0.75, yRadius: 0.75).fill()
        NSBezierPath(roundedRect: NSRect(x: 15.5, y: 6, width: 1.5, height: 4), xRadius: 0.75, yRadius: 0.75).fill()
        NSBezierPath(rect: NSRect(x: 8.4, y: 13, width: 1.2, height: 2)).fill()
        NSBezierPath(ovalIn: NSRect(x: 7.75, y: 14.75, width: 2.5, height: 2.5)).fill()

        context.setBlendMode(.destinationOut)
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 5.5, y: 7.5, width: 2.5, height: 2.5)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10, y: 7.5, width: 2.5, height: 2.5)).fill()
        NSBezierPath(roundedRect: NSRect(x: 6, y: 4.5, width: 6, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
        context.restoreGState()
    }

    /// The app icon at exactly `pixels` square: macOS's rounded-square tile with the robot on it.
    /// Rendered into a bitmap of that size, not through `lockFocus`, which would scale to the
    /// display's backing factor.
    public static func appIcon(pixels: Int) -> NSBitmapImageRep {
        let bitmap = bitmapCanvas(pixels: pixels)
        drawInto(bitmap) {
            let side = CGFloat(pixels)
            // Apple's icon grid: the tile fills ~80% of the canvas, corner radius ~22% of the tile.
            let tile = NSRect(x: side * 0.1, y: side * 0.1, width: side * 0.8, height: side * 0.8)
            NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.20, alpha: 1).setFill()
            NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.22, yRadius: tile.width * 0.22).fill()
            draw(in: tile.insetBy(dx: tile.width * 0.16, dy: tile.width * 0.16), tint: .systemGreen)
        }
        return bitmap
    }

    /// A transparent RGBA canvas whose point size equals its pixel size.
    public static func bitmapCanvas(pixels: Int) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        bitmap.size = NSSize(width: pixels, height: pixels)
        return bitmap
    }

    public static func drawInto(_ bitmap: NSBitmapImageRep, _ body: () -> Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        body()
        NSGraphicsContext.restoreGraphicsState()
    }
}
