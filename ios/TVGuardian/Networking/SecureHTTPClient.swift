import Foundation

/// Standard OS certificate validation; redirects cannot forward credentials.
final class SecureHTTPClient: NSObject, URLSessionTaskDelegate {
    private let configuration: URLSessionConfiguration
    init(configuration: URLSessionConfiguration = .ephemeral) { self.configuration = configuration; super.init() }
    private lazy var session: URLSession = {
        let c = configuration
        c.timeoutIntervalForRequest = 15; c.timeoutIntervalForResource = 25
        c.urlCache = nil; c.httpCookieStorage = nil
        c.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()
    func request(base: URL, path: String, method: String = "GET", headers: [String: String] = [:], body: [String: Any]? = nil,
                 query: [URLQueryItem] = []) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard base.scheme == "https", base.host != nil else { throw GuardianError.invalid("An HTTPS connection is required.") }
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        parts.path = path; parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url else { throw GuardianError.invalid("Invalid service URL.") }
        var request = URLRequest(url: url); request.httpMethod = method
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GuardianError.protocolError("Missing HTTP response.") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw GuardianError.denied("Service authorization failed (\(http.statusCode)). Check token expiry, permissions or application password.") }
            throw GuardianError.protocolError("Service returned HTTP \(http.statusCode). No successful change is assumed.")
        }
        guard data.count <= 4_000_000 else { throw GuardianError.protocolError("Service response exceeded the size limit.") }
        if data.isEmpty { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GuardianError.protocolError("Service returned an unexpected JSON format.") }
        if json["error"] != nil || (json["errors"] as? [Any])?.isEmpty == false {
            throw GuardianError.protocolError("The provider reported an API error. No successful change is recorded.")
        }
        return json
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func invalidate() { session.invalidateAndCancel() }
}
