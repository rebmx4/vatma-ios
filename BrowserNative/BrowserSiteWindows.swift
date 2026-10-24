import UIKit
import WebKit

extension BrowserController {
    func createSiteWindow(from source: WKWebView, configuration: WKWebViewConfiguration,
                          url: URL?) throws -> WKWebView {
        guard source !== ui, let opener = model.tabs.first(where: { renderers[$0.id] === source }) else {
            throw BrowserFailure.invalid("Only an open website may create a site window.")
        }
        let address: String
        if let url, url.absoluteString != "about:blank" {
            address = try AddressResolver.validated(url.absoluteString).absoluteString
        } else { address = "about:blank" }
        var tab = BrowserTab(profileId: opener.profileId, url: address)
        tab.webApp = opener.webApp
        tab.appControlsCollapsed = opener.appControlsCollapsed
        model.tabs.append(tab)
        model.activeTabId = tab.id
        windowOpeners[tab.id] = opener.id
        mode = "browse"; panel = nil; nativeError = nil
        let window = renderer(for: tab, configuration: configuration)
        // WebKit loads the original request itself, preserving POST bodies and window.opener.
        // Calling load() here would issue a second request and break that relationship.
        changed()
        return window
    }
}
