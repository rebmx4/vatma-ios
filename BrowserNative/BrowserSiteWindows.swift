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
        tab.privateBrowsing = opener.isPrivate
        tab.webApp = opener.webApp
        tab.appControlsCollapsed = opener.appControlsCollapsed
        model.tabs.append(tab)
        windowOpeners[tab.id] = opener.id
        let selectedBefore = model.activeTabId
        let window = renderer(for: tab, configuration: configuration)
        window.isHidden = true
        captureCurrentPreview { [weak self, weak window] in
            guard let self, let window, self.renderers[tab.id] === window,
                  self.model.activeTabId == selectedBefore,
                  self.model.tabs.contains(where: { $0.id == tab.id }) else { return }
            self.model.activeTabId = tab.id
            self.mode = "browse"; self.panel = nil; self.nativeError = nil
            self.changed()
        }
        // WebKit loads the original request itself, preserving POST bodies and window.opener.
        // Calling load() here would issue a second request and break that relationship.
        return window
    }
}
