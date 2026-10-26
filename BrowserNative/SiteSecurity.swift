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
    private var installed: Set<ObjectIdentifier> = []
    private var pendingLoads: [ObjectIdentifier: URLRequest] = [:]
    private(set) var error: String?
    var didChange: (() -> Void)?

    init() {
        guard let url = Bundle.main.url(forResource: "content-blocker", withExtension: "json", subdirectory: "BrowserUI"),
              let rules = try? String(contentsOf: url, encoding: .utf8) else {
            error = "Bundled content rules are missing."
            return
        }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "atma.website-filter.v2", encodedContentRuleList: rules) { [weak self] list, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.ruleList = list
                self.error = error?.localizedDescription ?? (list == nil ? "Content rules did not compile." : nil)
                for entry in Array(self.views.values) { if let view = entry.view { self.apply(to: view) } }
                let pending = self.pendingLoads
                self.pendingLoads.removeAll()
                for (id, request) in pending {
                    if let view = self.views[id]?.view { view.load(request) }
                }
                self.didChange?()
            }
        }
    }

    var available: Bool { ruleList != nil }

    func apply(to view: WKWebView) {
        views = views.filter { $0.value.view != nil }
        installed.formIntersection(Set(views.keys))
        let id = ObjectIdentifier(view)
        views[id] = WeakView(view)
        if let ruleList, !installed.contains(id) {
            view.configuration.userContentController.add(ruleList)
            installed.insert(id)
        }
        BrowserPageScripts.configure(view, blocking: true)
    }

    func load(_ request: URLRequest, in view: WKWebView) {
        apply(to: view)
        if ruleList != nil || error != nil { view.load(request) }
        else { pendingLoads[ObjectIdentifier(view)] = request }
    }

    func forget(_ view: WKWebView) {
        let id = ObjectIdentifier(view)
        pendingLoads.removeValue(forKey: id)
        views.removeValue(forKey: id)
        installed.remove(id)
    }

    private final class WeakView {
        weak var view: WKWebView?
        init(_ view: WKWebView) { self.view = view }
    }
}
