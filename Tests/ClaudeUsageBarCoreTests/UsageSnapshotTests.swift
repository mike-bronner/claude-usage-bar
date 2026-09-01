import XCTest
@testable import ClaudeUsageBarCore

final class UsageSnapshotTests: XCTestCase {
    /// A live response as observed on 2026-09-01, trimmed of nothing so the noise is exercised.
    static let live = #"""
    {
      "amber_ladder" : null,
      "extra_usage" : { "credits_ever_enabled" : true, "is_enabled" : false, "utilization" : null },
      "five_hour" : { "resets_at" : "2026-09-01T22:50:00.347301+00:00", "utilization" : 23 },
      "limits" : [
        { "group" : "session", "is_active" : true, "kind" : "session", "percent" : 23,
          "resets_at" : "2026-09-01T22:50:00.347301+00:00", "scope" : null, "severity" : "normal" },
        { "group" : "weekly", "is_active" : false, "kind" : "weekly_all", "percent" : 5,
          "resets_at" : "2026-09-02T09:00:00.347321+00:00", "scope" : null, "severity" : "normal" },
        { "group" : "weekly", "is_active" : false, "kind" : "weekly_scoped", "percent" : 2,
          "resets_at" : null, "scope" : { "model" : { "display_name" : "Fable", "id" : null }, "surface" : null },
          "severity" : "warning" }
      ],
      "nimbus_quill" : { "resets_at" : null, "utilization" : 0 },
      "seven_day" : { "resets_at" : "2026-09-02T09:00:00.347321+00:00", "utilization" : 5 },
      "spend" : {
        "auto_reload" : null, "balance" : null, "can_purchase_credits" : false, "can_toggle" : false,
        "cap" : null, "disabled_reason" : "out_of_credits",
        "disclaimer" : "Usage credits cover you when you hit your plan limits.",
        "enabled" : false, "limit" : null, "percent" : 0, "severity" : "normal",
        "used" : { "amount_minor" : 0, "currency" : "USD", "exponent" : 2 }
      },
      "tangelo" : null
    }
    """#

    private let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testDecodesLimitsInOrderWithKindsAndScopes() throws {
        let snapshot = try UsageSnapshot.decode(Data(Self.live.utf8), fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.limits.map(\.kind), [.session, .weeklyAll, .weeklyScoped])
        XCTAssertEqual(snapshot.limits.map(\.percent), [23, 5, 2])
        XCTAssertEqual(snapshot.limits.map(\.isActive), [true, false, false])
        XCTAssertEqual(snapshot.limits.map(\.modelName), [nil, nil, "Fable"])
        XCTAssertEqual(snapshot.limits.map(\.severity), ["normal", "normal", "warning"])
        XCTAssertEqual(snapshot.limits.map(\.isElevated), [false, false, true])
    }

    func testDecodesFractionalTimestampsAndNullResets() throws {
        let snapshot = try UsageSnapshot.decode(Data(Self.live.utf8), fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.session?.resetsAt, Date(timeIntervalSince1970: 1_788_303_000.347))
        XCTAssertNil(snapshot.weeklyScoped.first?.resetsAt)
    }

    func testAccessorsPickByKind() throws {
        let snapshot = try UsageSnapshot.decode(Data(Self.live.utf8), fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.session?.percent, 23)
        XCTAssertEqual(snapshot.weeklyAll?.percent, 5)
        XCTAssertEqual(snapshot.weeklyScoped.map(\.modelName), ["Fable"])
    }

    func testDecodesDisabledCredits() throws {
        let credits = try XCTUnwrap(UsageSnapshot.decode(Data(Self.live.utf8), fetchedAt: fetchedAt).credits)
        XCTAssertFalse(credits.enabled)
        XCTAssertEqual(credits.disabledReason, "out_of_credits")
        XCTAssertEqual(credits.used, Money(amountMinor: 0, currency: "USD", exponent: 2))
        XCTAssertNil(credits.limit)
        XCTAssertNil(credits.balance)
        XCTAssertNil(credits.autoReload)
        XCTAssertFalse(credits.canPurchaseCredits)
    }

    func testDecodesEnabledCreditsWithMoneyAndAutoReload() throws {
        let json = #"""
        {"limits":[],"spend":{"enabled":true,"percent":42,"can_purchase_credits":true,"auto_reload":true,
         "used":{"amount_minor":1250,"currency":"USD","exponent":2},
         "limit":{"amount_minor":5000,"currency":"USD","exponent":2},
         "balance":{"amount_minor":3750,"currency":"USD","exponent":2}}}
        """#
        let credits = try XCTUnwrap(UsageSnapshot.decode(Data(json.utf8), fetchedAt: fetchedAt).credits)
        XCTAssertTrue(credits.enabled)
        XCTAssertEqual(credits.percent, 42)
        XCTAssertEqual(credits.used?.amount, 12.5)
        XCTAssertEqual(credits.limit?.amount, 50)
        XCTAssertEqual(credits.balance?.amount, 37.5)
        XCTAssertEqual(credits.autoReload, true)
        XCTAssertTrue(credits.canPurchaseCredits)
    }

    func testAutoReloadObjectShapeReadsItsEnabledFlag() throws {
        let json = #"{"limits":[],"spend":{"enabled":true,"auto_reload":{"enabled":false,"amount":10}}}"#
        let credits = try XCTUnwrap(UsageSnapshot.decode(Data(json.utf8), fetchedAt: fetchedAt).credits)
        XCTAssertEqual(credits.autoReload, false)
    }

    func testAutoReloadUnknownShapeReadsAsUnknownNotFailure() throws {
        let json = #"{"limits":[],"spend":{"enabled":true,"auto_reload":"weird"}}"#
        let credits = try XCTUnwrap(UsageSnapshot.decode(Data(json.utf8), fetchedAt: fetchedAt).credits)
        XCTAssertNil(credits.autoReload)
    }

    func testUnknownKindIsPreservedNotDropped() throws {
        let json = #"{"limits":[{"kind":"monthly_thing","percent":7}]}"#
        let snapshot = try UsageSnapshot.decode(Data(json.utf8), fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.limits.first?.kind, .other("monthly_thing"))
        XCTAssertEqual(snapshot.limits.first?.severity, "normal")
        XCTAssertEqual(snapshot.limits.first?.isActive, false)
        XCTAssertNil(snapshot.session)
    }

    func testMissingSpendYieldsNilCredits() throws {
        XCTAssertNil(try UsageSnapshot.decode(Data(#"{"limits":[]}"#.utf8), fetchedAt: fetchedAt).credits)
    }

    // MARK: Fail-closed

    func testRejectsMissingLimits() {
        assertMalformed(#"{"five_hour":{"utilization":3}}"#)
    }

    func testRejectsLimitWithoutPercent() {
        assertMalformed(#"{"limits":[{"kind":"session"}]}"#)
    }

    func testRejectsGarbageTimestamp() {
        assertMalformed(#"{"limits":[{"kind":"session","percent":1,"resets_at":"tomorrow"}]}"#)
    }

    func testRejectsNonJSON() {
        assertMalformed("<html>")
    }

    private func assertMalformed(_ json: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try UsageSnapshot.decode(Data(json.utf8), fetchedAt: fetchedAt), file: file, line: line) { error in
            guard case UsageError.malformedResponse = error else { return XCTFail("got \(error)", file: file, line: line) }
        }
    }

    // MARK: Money

    func testMoneyFormatsByExponent() {
        XCTAssertEqual(Money(amountMinor: 1250, currency: "USD", exponent: 2).amount, 12.5)
        XCTAssertEqual(Money(amountMinor: 1250, currency: "JPY", exponent: 0).amount, 1250)
        XCTAssertEqual(Money(amountMinor: 1250, currency: "USD", exponent: 2).formatted, 12.5.formatted(.currency(code: "USD")))
    }
}
