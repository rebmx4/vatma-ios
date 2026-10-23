import Foundation
import Security
import CryptoKit
import WebKit

enum SiteTrust {
    static func evaluate(_ trust: SecTrust) -> Bool {
        if SecTrustEvaluateWithError(trust, nil) { return true }
        let anchors = pinnedRoots()
        guard !anchors.isEmpty,
              SecTrustSetAnchorCertificates(trust, anchors as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, false) == errSecSuccess else { return false }
        // The challenge's original SSL/hostname policy remains attached to this trust.
        return SecTrustEvaluateWithError(trust, nil)
    }

    private static func pinnedRoots() -> [SecCertificate] {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("certificates", isDirectory: true),
              let manifest = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let document = try? JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              let rows = document["certificates"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard row["type"] as? String == "root", let file = row["file"] as? String,
                  file == (file as NSString).lastPathComponent, !file.contains("\\"),
                  let expected = row["sha256"] as? String,
                  let fingerprint = row["fingerprint256"] as? String,
                  let pem = try? Data(contentsOf: folder.appendingPathComponent(file)),
                  digest(pem) == expected.lowercased(), let text = String(data: pem, encoding: .utf8) else { return nil }
            let body = text.replacingOccurrences(of: "-----BEGIN CERTIFICATE-----", with: "")
                .replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
                .filter { !$0.isWhitespace }
            guard let der = Data(base64Encoded: body), digest(der) == fingerprint.replacingOccurrences(of: ":", with: "").lowercased(),
                  let cert = SecCertificateCreateWithData(nil, der as CFData),
                  let key = SecCertificateCopyKey(cert),
                  let attributes = SecKeyCopyAttributes(key) as? [String: Any],
                  attributes[kSecAttrKeyType as String] as? String == kSecAttrKeyTypeRSA as String else { return nil }
            return cert
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class SiteBlocker {
    private var ruleList: WKContentRuleList?
    private var views: [ObjectIdentifier: WeakView] = [:]
    private(set) var error: String?
    var didChange: (() -> Void)?
    private let key = "atma.blocker.disabled-hosts"
    private var disabledHosts: Set<String>

    init() {
        disabledHosts = Set((UserDefaults.standard.stringArray(forKey: key) ?? []).map { $0.lowercased() })
        guard let url = Bundle.main.url(forResource: "content-blocker", withExtension: "json", subdirectory: "BrowserUI"),
              let rules = try? String(contentsOf: url, encoding: .utf8) else {
            error = "Bundled content-blocker rules are missing."; return
        }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "atma.independent.v1", encodedContentRuleList: rules) { [weak self] list, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.ruleList = list; self.error = error?.localizedDescription
                self.views.values.forEach { if let view = $0.view { self.apply(to: view, host: view.url?.host) } }
                self.didChange?()
            }
        }
    }

    var available: Bool { ruleList != nil }
    func enabled(host: String?) -> Bool { HostBlockerPolicy.enabled(host: host, disabledHosts: disabledHosts) }
    func setEnabled(_ enabled: Bool, host: String) {
        if enabled { disabledHosts.remove(host.lowercased()) } else { disabledHosts.insert(host.lowercased()) }
        UserDefaults.standard.set(Array(disabledHosts).sorted(), forKey: key)
        views.values.forEach { if let view = $0.view { apply(to: view, host: view.url?.host) } }
    }

    func apply(to webView: WKWebView, host: String?) {
        views = views.filter { $0.value.view != nil }
        views[ObjectIdentifier(webView)] = WeakView(webView)
        let controller = webView.configuration.userContentController
        if let ruleList { controller.remove(ruleList) }
        if enabled(host: host), let ruleList { controller.add(ruleList) }
        BrowserPageScripts.configure(webView, blocking: enabled(host: host))
    }

    private final class WeakView {
        weak var view: WKWebView?
        init(_ view: WKWebView) { self.view = view }
    }
}
