import WebKit

extension BrowserController {
    func expectDownload(_ webView: WKWebView, url: URL, knownNavigation: Bool) {
        guard let tabID = renderers.first(where: { $0.value === webView })?.key else { return }
        let key = ObjectIdentifier(webView)
        let navigationID = knownNavigation ? currentNavigations[key].map { String(describing: ObjectIdentifier($0)) } : nil
        downloadTransitions[key] = DownloadNavigationTransition(tabID: tabID, url: url.absoluteString, navigationID: navigationID)
    }

    func beginDownload(_ download: WKDownload, from webView: WKWebView, mainFrame: Bool, url: URL?) {
        guard let tabID = renderers.first(where: { $0.value === webView })?.key else {
            download.cancel { _ in }; return
        }
        if mainFrame {
            let key = ObjectIdentifier(webView)
            // A newer navigation may already have replaced this download's provisional load.
            if var transition = downloadTransitions[key], transition.url == url?.absoluteString {
                transition.transferred = true
                downloadTransitions[key] = transition
                finishDownloadNavigation(tabID)
            }
        }
        downloads.attach(download, tabID: tabID)
    }

    func finishDownloadNavigation(_ tabID: String) {
        guard let index = model.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        model.tabs[index].finishNavigationForDownload()
        model.save(); publish()
    }

    func cleanupNavigation(for webView: WKWebView) {
        let key = ObjectIdentifier(webView)
        currentNavigations.removeValue(forKey: key)
        downloadTransitions.removeValue(forKey: key)
    }
}
