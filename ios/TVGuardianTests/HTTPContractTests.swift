import XCTest
@testable import TVGuardian

private final class FixtureURLProtocol: URLProtocol {
    static var status = 200
    static var payload = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class HTTPContractTests: XCTestCase {
    func fixture(_ status: Int, _ json: String) -> SecureHTTPClient {
        FixtureURLProtocol.status = status; FixtureURLProtocol.payload = Data(json.utf8)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureURLProtocol.self]
        return SecureHTTPClient(configuration: config)
    }
    func testHTTP200ProviderErrorIsNotSuccess() async {
        let client = fixture(200, "{\"errors\":[{\"code\":\"invalid\"}]}")
        defer { client.invalidate() }
        do { _ = try await client.request(base: URL(string: "https://fixture.example")!, path: "/"); XCTFail("Provider error must fail") } catch { }
    }
    func testExpiredTokenFailsWithClearAuthorizationError() async {
        let client = fixture(401, "{}")
        defer { client.invalidate() }
        do { _ = try await client.request(base: URL(string: "https://fixture.example")!, path: "/"); XCTFail("401 must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("authorization")) }
    }
    func testHTTPTransportRejectedBeforeCredentialUse() async {
        let client = fixture(200, "{}")
        defer { client.invalidate() }
        do { _ = try await client.request(base: URL(string: "http://fixture.example")!, path: "/", headers: ["Authorization": "fixture"]); XCTFail("HTTP must fail") } catch { }
    }
    func testUnknownJSONShapeDoesNotBecomeEmptySuccess() async {
        let client = fixture(200, "[]")
        defer { client.invalidate() }
        do { _ = try await client.request(base: URL(string: "https://fixture.example")!, path: "/"); XCTFail("Array is not an object") } catch { }
    }
}
