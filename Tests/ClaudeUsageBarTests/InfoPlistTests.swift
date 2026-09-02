import XCTest

/// The bundle's Info.plist is hand-written; pin the keys the app cannot work without.
final class InfoPlistTests: XCTestCase {
    private func plist() throws -> [String: Any] {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Support/Info.plist")
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testMenuBarOnlyApp() throws {
        XCTAssertEqual(try plist()["LSUIElement"] as? Bool, true, "without LSUIElement the app gets a Dock icon")
    }

    func testExecutableAndIdentifier() throws {
        let plist = try plist()
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "ClaudeUsageBar")
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.mikebronner.ClaudeUsageBar")
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "14.0")
    }
}
