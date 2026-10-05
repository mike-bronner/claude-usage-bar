import XCTest
@testable import ClaudeUsageBarCore

final class StatusLevelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var later: Date { now.addingTimeInterval(3600) }
    private var earlier: Date { now.addingTimeInterval(-1) }

    private func limit(_ kind: UsageLimit.Kind, _ percent: Double, resets: Date?, severity: String = "normal") -> UsageLimit {
        UsageLimit(kind: kind, percent: percent, resetsAt: resets, modelName: nil, severity: severity, isActive: true)
    }

    private func credits(enabled: Bool, percent: Double) -> UsageCredits {
        UsageCredits(enabled: enabled, percent: percent, used: nil, limit: nil, balance: nil, autoReload: nil,
                     canPurchaseCredits: false, disabledReason: nil, severity: nil)
    }

    private func classify(_ limits: [UsageLimit], credits: UsageCredits? = nil, idle: Bool = false) -> StatusLevel {
        StatusLevel.classify(snapshot: UsageSnapshot(limits: limits, credits: credits, fetchedAt: now), idle: idle, now: now)
    }

    // MARK: One limit

    func testThresholdsAtTheBoundaries() {
        XCTAssertEqual(StatusLevel.classify(percent: 0, severity: "normal"), .low)
        XCTAssertEqual(StatusLevel.classify(percent: 49.9, severity: "normal"), .low)
        XCTAssertEqual(StatusLevel.classify(percent: 50, severity: "normal"), .medium)
        XCTAssertEqual(StatusLevel.classify(percent: 74.9, severity: "normal"), .medium)
        XCTAssertEqual(StatusLevel.classify(percent: 75, severity: "normal"), .high)
        XCTAssertEqual(StatusLevel.classify(percent: 89.9, severity: "normal"), .high)
        XCTAssertEqual(StatusLevel.classify(percent: 90, severity: "normal"), .critical)
        XCTAssertEqual(StatusLevel.classify(percent: 100, severity: "normal"), .critical)
    }

    func testMissingSeverityUsesThresholds() {
        XCTAssertEqual(StatusLevel.classify(percent: 10, severity: nil), .low)
    }

    func testWarningSeverityRaisesToAtLeastHigh() {
        XCTAssertEqual(StatusLevel.classify(percent: 10, severity: "warning"), .high)
        XCTAssertEqual(StatusLevel.classify(percent: 95, severity: "warning"), .critical, "warning never lowers the level")
    }

    func testUnfamiliarSeverityIsCritical() {
        XCTAssertEqual(StatusLevel.classify(percent: 10, severity: "exceeded"), .critical)
        XCTAssertEqual(StatusLevel.classify(percent: 10, severity: "critical"), .critical)
    }

    // MARK: One account

    func testTightestLimitDecidesAcrossSessionAndWeekly() {
        XCTAssertEqual(classify([limit(.session, 10, resets: later), limit(.weeklyAll, 80, resets: later)]), .high)
        XCTAssertEqual(classify([limit(.session, 60, resets: later), limit(.weeklyScoped, 92, resets: nil)]), .critical)
        XCTAssertEqual(classify([limit(.session, 10, resets: later), limit(.weeklyAll, 20, resets: later, severity: "warning")]), .high,
                       "a weekly limit's severity counts, not only the session's")
    }

    func testLimitWhoseResetPassedIsIgnored() {
        XCTAssertEqual(classify([limit(.session, 100, resets: earlier), limit(.weeklyAll, 30, resets: later)]), .low)
        XCTAssertEqual(classify([limit(.session, 95, resets: now)]), .unknown, "a reset at exactly now has passed")
    }

    func testLimitWithoutResetCounts() {
        XCTAssertEqual(classify([limit(.weeklyScoped, 100, resets: nil)]), .out)
    }

    func testIdleAccountCountsWithLastKnownNumbers() {
        XCTAssertEqual(classify([limit(.session, 95, resets: later)], idle: true), .critical)
        XCTAssertEqual(classify([limit(.session, 100, resets: later)], idle: true), .out)
    }

    func testIdleAccountWithEveryResetPassedIsIdle() {
        XCTAssertEqual(classify([limit(.session, 100, resets: earlier)], idle: true), .idle)
        XCTAssertEqual(StatusLevel.classify(snapshot: nil, idle: true, now: now), .idle)
    }

    func testNoNumbersIsUnknown() {
        XCTAssertEqual(StatusLevel.classify(snapshot: nil, idle: false, now: now), .unknown)
        XCTAssertEqual(classify([]), .unknown)
    }

    // MARK: Out and on credits

    func testSpentLimitWithoutCreditsIsOut() {
        XCTAssertEqual(classify([limit(.session, 100, resets: later)]), .out, "no spend object means no credits")
        XCTAssertEqual(classify([limit(.session, 100, resets: later)], credits: credits(enabled: false, percent: 0)), .out)
        XCTAssertEqual(classify([limit(.weeklyAll, 104, resets: later)], credits: credits(enabled: false, percent: 0)), .out)
    }

    func testSpentLimitWithCreditsUsedUpIsOut() {
        XCTAssertEqual(classify([limit(.session, 100, resets: later)], credits: credits(enabled: true, percent: 100)), .out)
    }

    func testSpentLimitWithCreditsLeftIsOnCredits() {
        XCTAssertEqual(classify([limit(.session, 100, resets: later)], credits: credits(enabled: true, percent: 0)), .onCredits(creditPercent: 0))
        XCTAssertEqual(classify([limit(.weeklyAll, 100, resets: later)], credits: credits(enabled: true, percent: 99.9)), .onCredits(creditPercent: 99.9))
    }

    func testLimitJustUnderFullIsNotSpent() {
        XCTAssertEqual(classify([limit(.session, 99.9, resets: later)], credits: credits(enabled: false, percent: 0)), .critical)
    }

    func testCreditsAloneDoNotRaiseTheLevel() {
        XCTAssertEqual(classify([limit(.session, 10, resets: later)], credits: credits(enabled: true, percent: 80)), .low)
    }

    // MARK: Order

    func testSeverityOrderWorstLast() {
        let ordered: [StatusLevel] = [
            .idle, .unknown, .low, .medium, .high, .critical,
            .onCredits(creditPercent: 0), .onCredits(creditPercent: 60), .out,
        ]
        for (index, level) in ordered.enumerated() {
            for other in ordered[..<index] {
                XCTAssertLessThan(other, level)
                XCTAssertFalse(level < other)
            }
        }
        XCTAssertEqual(ordered.shuffled().max(), .out)
    }
}
