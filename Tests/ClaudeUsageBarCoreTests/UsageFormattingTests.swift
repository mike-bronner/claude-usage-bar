import XCTest
@testable import ClaudeUsageBarCore

final class UsageFormattingTests: XCTestCase {
    // MARK: Reset countdown

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCountdownUnits() {
        XCTAssertEqual(ResetFormatter.countdown(to: now.addingTimeInterval(42 * 60), now: now), "42m")
        XCTAssertEqual(ResetFormatter.countdown(to: now.addingTimeInterval(2 * 3600 + 15 * 60), now: now), "2h 15m")
        XCTAssertEqual(ResetFormatter.countdown(to: now.addingTimeInterval(3 * 86400 + 4 * 3600 + 59 * 60), now: now), "3d 4h")
    }

    func testCountdownFloorsToOneMinuteAndClampsPast() {
        XCTAssertEqual(ResetFormatter.countdown(to: now.addingTimeInterval(20), now: now), "1m")
        XCTAssertEqual(ResetFormatter.countdown(to: now, now: now), "now")
        XCTAssertEqual(ResetFormatter.countdown(to: now.addingTimeInterval(-500), now: now), "now")
    }

    // MARK: Plan label

    func testPlanLabelCapitalizesAndAppendsMultiplier() {
        XCTAssertEqual(PlanLabel.text(subscriptionType: "max", rateLimitTier: "default_claude_max_20x"), "Max (20x)")
        XCTAssertEqual(PlanLabel.text(subscriptionType: "max", rateLimitTier: "default_claude_max_5x"), "Max (5x)")
    }

    func testPlanLabelWithoutMultiplier() {
        XCTAssertEqual(PlanLabel.text(subscriptionType: "team", rateLimitTier: "default_claude"), "Team")
        XCTAssertEqual(PlanLabel.text(subscriptionType: "team", rateLimitTier: nil), "Team")
        XCTAssertEqual(PlanLabel.text(subscriptionType: "pro", rateLimitTier: "default_claude_max"), "Pro")
    }

    func testPlanLabelNilWithoutSubscription() {
        XCTAssertNil(PlanLabel.text(subscriptionType: nil, rateLimitTier: "default_claude_max_20x"))
        XCTAssertNil(PlanLabel.text(subscriptionType: "", rateLimitTier: nil))
    }
}
