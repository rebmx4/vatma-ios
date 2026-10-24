import Foundation
import WebKit

/// Bounded, non-persistent fetches for user-created shortcut artwork.
/// No profile cookies, credentials, disk cache or executable page content cross into the UI.
enum BrowserSiteResource {
    static func load(_ address: String, kind: String) async throws -> [String: Any] {
        let url = try AddressResolver.validated(address)
        let limits = ["document": 524_288, "manifest": 131_072, "image": 1_048_576]
        guard let limit = limits[kind] else { throw BrowserFailure.invalid("Unknown site resource kind.") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        let session = URLSession(configuration: configuration, delegate: SiteResourceTrust(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue(kind == "image" ? "image/*" : kind == "manifest" ? "application/manifest+json,application/json" : "text/html", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let finalURL = response.url, (try? AddressResolver.validated(finalURL.absoluteString)) != nil,
              response.expectedContentLength <= Int64(limit) else { throw BrowserFailure.invalid("Site resource is unavailable or too large.") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw BrowserFailure.invalid("Site resource is too large.") }
            data.append(byte)
        }
        guard !data.isEmpty else { throw BrowserFailure.invalid("Site resource is empty.") }
        if kind == "image" {
            let mime = response.mimeType?.lowercased() ?? "image/png"
            guard mime.hasPrefix("image/") || mime == "application/octet-stream" else { throw BrowserFailure.invalid("Site did not return an image.") }
            return ["url": finalURL.absoluteString, "dataUrl": "data:\(mime == "application/octet-stream" ? "image/x-icon" : mime);base64,\(data.base64EncodedString())"]
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) else { throw BrowserFailure.invalid("Site metadata encoding is unsupported.") }
        return ["url": finalURL.absoluteString, "text": text]
    }
}


extension BrowserSiteResource {
    @MainActor
    static func metadata(in page: WKWebView, completion: @escaping ([String: Any]) -> Void) {
        guard let resource = Bundle.main.url(forResource: "site-icons", withExtension: "js", subdirectory: "BrowserUI/assets"),
              let module = try? String(contentsOf: resource, encoding: .utf8) else { completion([:]); return }
        // This import-free module is also the single metadata parser used by the UI.
        let script = module.replacingOccurrences(of: "export ", with: "") + "\nreturn readSiteMetadata(document,location.href);"
        page.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
            if case .success(let value) = result, let metadata = value as? [String: Any] { completion(metadata) }
            else { completion([:]) }
        }
    }
}


private final class SiteResourceTrust: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        guard SiteTrust.evaluate(trust) else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
