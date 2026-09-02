import AppKit
import ClaudeUsageBarCore

// Build tool: writes the app icon as an .iconset directory for `iconutil`. Usage:
//   render-icon <output.iconset>

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: render-icon <output.iconset>\n".utf8))
    exit(2)
}

let iconset = URL(filePath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The sizes iconutil expects; each point size at 1x and 2x.
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let png = RobotGlyph.appIcon(pixels: pixels).representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("could not encode \(pixels)px\n".utf8))
            exit(1)
        }
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try png.write(to: iconset.appending(path: name))
    }
}
