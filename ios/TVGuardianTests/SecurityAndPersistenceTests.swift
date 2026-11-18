import XCTest
@testable import TVGuardian

final class SecurityAndPersistenceTests: XCTestCase {
    func testPrivateTVAddressesOnly() {
        for host in ["192.168.1.50", "10.0.0.2", "172.16.0.2", "172.31.255.254", "100.64.1.1"] { XCTAssertTrue(Validation.privateIPv4(host), host) }
        for host in ["8.8.8.8", "127.0.0.1", "172.32.0.2", "192.168.1.999", "192.168.01.1", "1.2.3", "::1", "https://192.168.1.2", "192.168.1.2/path"] { XCTAssertFalse(Validation.privateIPv4(host), host) }
    }
    func testDomainsCannotInjectFilterRulesOrURLPaths() throws {
        XCTAssertEqual(try Validation.domain(" EXAMPLE.COM "), "example.com")
        for input in ["https://example.com", "a.com\n@@||good.com^", "a.com$client=1.2.3.4", "*.example.com", "192.168.1.2", "a..com", "-a.com", "a.com/"] { XCTAssertThrowsError(try Validation.domain(input), input) }
    }
    func testHTTPSOriginValidation() throws {
        XCTAssertEqual(try Validation.httpsBase("https://guardian.example:8443").host, "guardian.example")
        for url in ["http://guardian.example", "https://user:secret@guardian.example", "https://guardian.example/path", "https://guardian.example?token=secret"] { XCTAssertThrowsError(try Validation.httpsBase(url)) }
    }
    func testAppIdentifierCannotEscapeRESTPath() {
        for id in ["../x", "a/b", "app?query=x", "app#fragment", "a\nb"] { XCTAssertThrowsError(try Validation.identifier(id)) }
    }
    func testCredentialsAreBoundToOriginAndAccount() throws {
        let a = try KeychainStore.scopedAccount("fixture", origin: Validation.httpsBase("https://one.example"), identity: "parent")
        let normalized = try KeychainStore.scopedAccount("fixture", origin: Validation.httpsBase("https://one.example:443/"), identity: "parent")
        let otherHost = try KeychainStore.scopedAccount("fixture", origin: Validation.httpsBase("https://two.example"), identity: "parent")
        let otherAccount = try KeychainStore.scopedAccount("fixture", origin: Validation.httpsBase("https://one.example"), identity: "other")
        XCTAssertEqual(a, normalized); XCTAssertNotEqual(a, otherHost); XCTAssertNotEqual(a, otherAccount)
    }
    func testPINVerifierMatchesIndependentPBKDF2Vector() throws {
        let hash = try PINHasher.derive("792468", salt: Data("0123456789abcdef0123456789abcdef".utf8), rounds: 600_000)
        XCTAssertEqual(hash.map { String(format: "%02x", $0) }.joined(), "0b0569e05099c4eff19257ef657ffeaec76a20ac3b677144394be801c04c86a2")
        XCTAssertTrue(PINHasher.equal(hash, hash)); XCTAssertFalse(PINHasher.equal(hash, Data(repeating: 0, count: 32)))
        XCTAssertThrowsError(try PINHasher.derive("792468", salt: Data(), rounds: 1))
    }
    func testRulesSurviveSavedStateRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try StateStore(directory: directory)
        let tv = TVRecord(name: "Fixture TV", host: "192.168.1.50")
        var state = GuardianState(); state.tvs = [tv]; state.selectedTVID = tv.id
        state.rules = [AppRule(tvID: tv.id, appID: "fixture.app", blocked: true)]
        try store.save(state)
        let restored = try store.load()
        XCTAssertEqual(restored.rules, state.rules)
        XCTAssertFalse(RuleEngine.evaluate(tvID: tv.id, appID: "fixture.app", state: restored).allowed)
    }
    func testCorruptionIsNotSilentlyReset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try StateStore(directory: directory)
        let url = directory.appendingPathComponent("state-v1.json")
        try Data("not valid JSON".utf8).write(to: url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "not valid JSON")
    }
    func testPrivilegeBoundariesStartUnsupported() {
        for feature in [Feature.uninstall, .nativeLock, .preventReinstall, .usage, .nativeSchedules, .networkSettings] { XCTAssertEqual(CapabilityEvidence.baseline(feature).status, .unsupported) }
        XCTAssertEqual(CapabilityEvidence.baseline(.launch).status, .unverified)
    }
    func testSyntacticallyValidButInvalidPolicyFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try StateStore(directory: directory)
        let tv = TVRecord(name: "Fixture TV", host: "192.168.1.50")
        var state = GuardianState(); state.tvs = [tv]
        state.schedules = [RestrictionSchedule(tvID: tv.id, name: "Invalid day", weekdays: [99], startMinute: 0, endMinute: 0, timeZoneID: "Asia/Muscat")]
        try JSONEncoder().encode(state).write(to: directory.appendingPathComponent("state-v1.json"))
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(state))
    }
}
