import XCTest
@testable import TVGuardian

final class RuleEngineTests: XCTestCase {
    let tvID = UUID()
    func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
    func schedule(days: [Int] = [6], start: Int = 21 * 60, end: Int = 7 * 60, zone: String = "Asia/Muscat") -> RestrictionSchedule {
        RestrictionSchedule(tvID: tvID, name: "Bedtime", weekdays: days, startMinute: start, endMinute: end, timeZoneID: zone)
    }
    func testOvernightBelongsToStartDay() {
        let rule = schedule()
        XCTAssertTrue(RuleEngine.isActive(rule, at: date("2026-11-20T18:00:00Z"))) // Friday 22:00
        XCTAssertTrue(RuleEngine.isActive(rule, at: date("2026-11-21T02:59:00Z"))) // Saturday 06:59
        XCTAssertFalse(RuleEngine.isActive(rule, at: date("2026-11-21T03:00:00Z"))) // Saturday 07:00
        XCTAssertFalse(RuleEngine.isActive(rule, at: date("2026-11-19T18:00:00Z"))) // Thursday
    }
    func testStartInclusiveEndExclusive() {
        let rule = schedule(start: 9 * 60, end: 15 * 60)
        XCTAssertFalse(RuleEngine.isActive(rule, at: date("2026-11-20T04:59:00Z")))
        XCTAssertTrue(RuleEngine.isActive(rule, at: date("2026-11-20T05:00:00Z")))
        XCTAssertFalse(RuleEngine.isActive(rule, at: date("2026-11-20T11:00:00Z")))
    }
    func testSaturdayToSundayRollover() {
        XCTAssertTrue(RuleEngine.isActive(schedule(days: [7]), at: date("2026-11-22T01:00:00Z")))
    }
    func testEqualTimesMeanWholeSelectedDay() {
        let rule = schedule(start: 0, end: 0)
        XCTAssertTrue(RuleEngine.isActive(rule, at: date("2026-11-20T14:00:00Z")))
        XCTAssertFalse(RuleEngine.isActive(rule, at: date("2026-11-21T00:00:00Z")))
    }
    func testDisabledAndInvalidSchedulesDoNotActivate() {
        var rule = schedule(); rule.enabled = false
        XCTAssertFalse(RuleEngine.isActive(rule, at: date("2026-11-20T18:00:00Z")))
        XCTAssertFalse(RuleEngine.isActive(schedule(zone: "bad/zone"), at: date("2026-11-20T18:00:00Z")))
    }
    func testDSTRepeatedHourUsesHomeWallClock() {
        let rule = schedule(days: [1], start: 60, end: 120, zone: "America/New_York")
        XCTAssertTrue(RuleEngine.isActive(rule, at: date("2026-11-01T05:30:00Z")))
        XCTAssertTrue(RuleEngine.isActive(rule, at: date("2026-11-01T06:30:00Z")))
        XCTAssertFalse(RuleEngine.isActive(rule, at: date("2026-11-01T07:00:00Z")))
    }
    func testBlockAndAgeAreScopedToTVAndApp() {
        var state = GuardianState()
        state.rules = [AppRule(tvID: tvID, appID: "fixture.app", blocked: true)]
        XCTAssertFalse(RuleEngine.evaluate(tvID: tvID, appID: "fixture.app", state: state).allowed)
        XCTAssertTrue(RuleEngine.evaluate(tvID: UUID(), appID: "fixture.app", state: state).allowed)
        XCTAssertTrue(RuleEngine.evaluate(tvID: tvID, appID: "other.app", state: state).allowed)
    }
    func testAgeThresholdFailsClosedWithoutProfile() {
        var state = GuardianState()
        state.rules = [AppRule(tvID: tvID, appID: "fixture.app", minimumAge: 13)]
        XCTAssertFalse(RuleEngine.evaluate(tvID: tvID, appID: "fixture.app", state: state).allowed)
        let profile = ChildProfile(name: "Test child", age: 8)
        state.profiles = [profile]; state.activeProfileID = profile.id
        XCTAssertFalse(RuleEngine.evaluate(tvID: tvID, appID: "fixture.app", state: state).allowed)
        state.profiles[0].age = 13
        XCTAssertTrue(RuleEngine.evaluate(tvID: tvID, appID: "fixture.app", state: state).allowed)
    }
    func testAllAppsScheduleAndAppScheduleAreScoped() {
        var state = GuardianState(); var rule = schedule(); rule.appID = "fixture.app"; state.schedules = [rule]
        let now = date("2026-11-20T18:00:00Z")
        XCTAssertFalse(RuleEngine.evaluate(tvID: tvID, appID: "fixture.app", state: state, at: now).allowed)
        XCTAssertTrue(RuleEngine.evaluate(tvID: tvID, appID: "other.app", state: state, at: now).allowed)
        state.schedules[0].appID = nil
        XCTAssertFalse(RuleEngine.evaluate(tvID: tvID, appID: "other.app", state: state, at: now).allowed)
    }
}
