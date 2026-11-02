import Foundation
import WebKit
import UIKit

@MainActor
enum BrowserPageScripts {
    static let backgroundKey = "atma.media.background"
    static var backgroundEnabled: Bool { UserDefaults.standard.object(forKey: backgroundKey) as? Bool ?? true }
    private static let resources = ["site-media", "youtube-protection", "site-ad-protection", "site-video-controls", "device-identity"].compactMap { name -> (String, String)? in
        guard let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "BrowserUI/assets"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return (name, source)
    }
    private static var signatures: [ObjectIdentifier: String] = [:]
    private static var privateIdentities: [ObjectIdentifier: [String: Any]] = [:]

    static func setPrivateIdentity(_ profile: [String: Any], for view: WKWebView) {
        privateIdentities[ObjectIdentifier(view)] = profile
    }

    static func configure(_ view: WKWebView, blocking: Bool = true) {
        let key = ObjectIdentifier(view)
        let identity = privateIdentities[key]
        let signature = "\(blocking):\(backgroundEnabled):\(identity?["id"] as? String ?? "actual")"
        guard signatures[key] != signature else { return }
        signatures[key] = signature
        let controller = view.configuration.userContentController
        // This standalone renderer owns only the site adapters, never the UI RPC.
        controller.removeAllUserScripts()
        for (name, source) in resources {
            if name == "device-identity" {
                guard let identity, let data = try? JSONSerialization.data(withJSONObject: identity),
                      let json = String(data: data, encoding: .utf8) else { continue }
                controller.addUserScript(WKUserScript(source: "(\(source))(\(json));", injectionTime: .atDocumentStart,
                                                  forMainFrameOnly: false, in: .page))
                continue
            }
            let options = name == "site-media" ? "{background:\(backgroundEnabled),screenLocked:\(!UIApplication.shared.isProtectedDataAvailable)}" : ["youtube-protection", "site-ad-protection"].contains(name) ? "{enabled:\(blocking)}" : "{}"
            let allFrames = ["youtube-protection", "site-ad-protection"].contains(name)
            controller.addUserScript(WKUserScript(source: "(\(source))(\(options));", injectionTime: .atDocumentStart, forMainFrameOnly: !allFrames, in: .page))
        }
        view.callAsyncJavaScript("window.__atmaYouTubeProtection?.setEnabled(blocking); window.__atmaMediaPage?.setBackground(background);",
                                 arguments: ["blocking": blocking, "background": backgroundEnabled], in: nil, in: .page, completionHandler: nil)
    }

    static func forget(_ view: WKWebView) {
        let key = ObjectIdentifier(view)
        signatures.removeValue(forKey: key)
        privateIdentities.removeValue(forKey: key)
    }
}
