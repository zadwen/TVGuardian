import Foundation
import Security
import CryptoKit

/// The sole self-signed trust exception is one reviewed leaf certificate for one
/// private TV address on port 8002. Cloud/bridge/DNS use ordinary system trust.
final class PinnedTVSession: NSObject, URLSessionTaskDelegate {
    let host: String
    let expectedFingerprint: String?
    private let mutex = NSLock()
    private var observedFingerprint: String?
    private var mismatched = false
    private(set) lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()
    init(host: String, expectedFingerprint: String?) throws {
        guard Validation.privateIPv4(host) else { throw GuardianError.invalid("Use a private IPv4 TV address or Tailscale subnet address.") }
        self.host = host; self.expectedFingerprint = expectedFingerprint
        super.init()
    }
    func url(path: String) -> URL {
        var parts = URLComponents(); parts.scheme = "https"; parts.host = host; parts.port = 8002; parts.path = path
        return parts.url!
    }
    func translated(_ error: Error) -> Error {
        mutex.lock(); defer { mutex.unlock() }
        if mismatched { return GuardianError.certificateChanged }
        if expectedFingerprint == nil, let fingerprint = observedFingerprint { return GuardianError.trustRequired(host: host, fingerprint: fingerprint) }
        return error
    }
    func request(_ path: String, method: String = "GET") async throws -> [String: Any] {
        try Task.checkCancellation()
        var request = URLRequest(url: url(path: path)); request.httpMethod = method; request.timeoutInterval = 10
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 2_000_000 else {
                throw GuardianError.protocolError("TV request failed or returned an oversized response. The operation remains unverified.")
            }
            // A close acknowledgement need not contain a JSON status document.
            // The caller must still observe running -> stopped before success.
            if method == "DELETE", (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] == nil { return [:] }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GuardianError.protocolError("TV response is not a JSON object.") }
            if let error = json["error"] { throw GuardianError.protocolError("The TV rejected the request (\(String(describing: error).prefix(120))).") }
            return json
        } catch { throw translated(error) }
    }
    func image(at value: String) async throws -> Data? {
        guard let url = URL(string: value), url.scheme == "https", url.host == host, url.port == 8002,
              url.user == nil, url.password == nil, url.fragment == nil else { return nil }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.mimeType?.hasPrefix("image/") == true, data.count <= 1_000_000 else { return nil }
        return data
    }
    func invalidate() { session.invalidateAndCancel() }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        guard challenge.protectionSpace.host == host, challenge.protectionSpace.port == 8002,
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = SecTrustGetCertificateAtIndex(trust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let fingerprint = SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
        mutex.lock()
        observedFingerprint = fingerprint
        let approved = expectedFingerprint == fingerprint
        mismatched = expectedFingerprint != nil && !approved
        mutex.unlock()
        completionHandler(approved ? .useCredential : .cancelAuthenticationChallenge,
                          approved ? URLCredential(trust: trust) : nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
