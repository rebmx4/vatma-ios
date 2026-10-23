import Foundation
import WebKit

@MainActor
enum BrowserPageScripts {
    static let backgroundKey = "atma.media.background"
    static var backgroundEnabled: Bool { UserDefaults.standard.object(forKey: backgroundKey) as? Bool ?? true }
    private static let resources = ["site-media", "youtube-protection", "site-video-controls"].compactMap { name -> (String, String)? in
        guard let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "BrowserUI/assets"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return (name, source)
    }
    private static var signatures: [ObjectIdentifier: String] = [:]

    static func configure(_ view: WKWebView, blocking: Bool) {
        let key = ObjectIdentifier(view), signature = "\(blocking):\(backgroundEnabled)"
        guard signatures[key] != signature else { return }
        signatures[key] = signature
        let controller = view.configuration.userContentController
        // This standalone renderer owns only the site adapters, never the UI RPC.
        controller.removeAllUserScripts()
        for (name, source) in resources {
            let options = name == "site-media" ? "{background:\(backgroundEnabled)}" : name == "youtube-protection" ? "{enabled:\(blocking)}" : "{}"
            controller.addUserScript(WKUserScript(source: "(\(source))(\(options));", injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        }
        view.callAsyncJavaScript("window.__atmaYouTubeProtection?.setEnabled(enabled); window.__atmaMediaPage?.setBackground(background);",
                                 arguments: ["enabled": blocking, "background": backgroundEnabled], in: nil, in: .page, completionHandler: nil)
    }

    static func forget(_ view: WKWebView) { signatures.removeValue(forKey: ObjectIdentifier(view)) }
}
