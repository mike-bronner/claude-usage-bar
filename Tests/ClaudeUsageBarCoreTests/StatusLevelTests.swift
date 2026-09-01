import XCTest
@testable import ClaudeUsageBarCore

final class StatusLevelTests: XCTestCase {
    func testThresholdsAtTheBoundaries() {
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 0, severity: "normal", idle: false), .low)
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 49.9, severity: "normal", idle: false), .low)
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 50, severity: "normal", idle: false), .medium)
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 74.9, severity: "normal", idle: false), .medium)
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 75, severity: "normal", idle: false), .high)
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 89.9, severity: "normal", idle: false), .high)
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 90, severity: "normal", idle: false), .critical)
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 100, severity: "normal", idle: false), .critical)
    }

    func testMissingSeverityUsesThresholds() {
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 10, severity: nil, idle: false), .low)
    }

    func testWarningSeverityRaisesToAtLeastHigh() {
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 10, severity: "warning", idle: false), .high)
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 95, severity: "warning", idle: false), .critical, "warning never lowers the level")
    }

    func testUnfamiliarSeverityIsCritical() {
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 10, severity: "exceeded", idle: false), .critical)
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 10, severity: "critical", idle: false), .critical)
    }

    func testIdleWinsOverEverything() {
        XCTAssertEqual(StatusLevel.classify(sessionPercent: 95, severity: "critical", idle: true), .idle)
    }

    func testNoNumbersIsUnknown() {
        XCTAssertEqual(StatusLevel.classify(sessionPercent: nil, severity: "normal", idle: false), .unknown)
    }
}
