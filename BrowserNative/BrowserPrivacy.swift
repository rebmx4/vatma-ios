import UIKit
import WebKit

extension BrowserController {
    var isPrivateStart: Bool { model.active.isPrivate && mode == "home" && model.active.url.isEmpty }

    func isPrivateRenderer(_ page: WKWebView) -> Bool {
        model.tabs.contains { $0.isPrivate && renderers[$0.id] === page }
    }

    func returnHome() {
        view.endEditing(true)
        if model.active.isPrivate {
            if let ordinary = model.tabs.first(where: { !$0.isPrivate }) { model.activeTabId = ordinary.id }
            else { newTab() }
        }
        mode = "home"; panel = nil; changed()
    }

    func closePrivateTabs() {
        let ids = Set(model.tabs.filter { $0.isPrivate }.map(\.id))
        ids.forEach { removeRenderer(for: $0) }
        model.tabs.removeAll { ids.contains($0.id) }
        windowOpeners = windowOpeners.filter { !ids.contains($0.key) && !ids.contains($0.value) }
        if model.tabs.isEmpty { newTab() }
        else if ids.contains(model.activeTabId) { model.activeTabId = model.tabs[0].id }
        model.discardUnusedPrivateSession()
        mode = "home"; panel = nil; nativeError = nil; changed()
    }

    func observeHistory(_ page: WKWebView, tabID: String) {
        let changed: (WKWebView) -> Void = { [weak self] page in
            DispatchQueue.main.async { [weak self, weak page] in
                guard let self, let page, self.renderers[tabID] === page else { return }
                self.update(page)
            }
        }
        historyObservations[tabID] = [
            page.observe(\.canGoBack, options: [.new]) { page, _ in changed(page) },
            page.observe(\.canGoForward, options: [.new]) { page, _ in changed(page) },
            page.observe(\.url, options: [.new]) { page, _ in changed(page) },
            page.observe(\.title, options: [.new]) { page, _ in changed(page) }
        ]
    }
}
