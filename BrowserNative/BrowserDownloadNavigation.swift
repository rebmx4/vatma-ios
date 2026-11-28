import UIKit
import WebKit

extension BrowserController {
    func downloadCurrentAddress() throws {
        guard mode == "browse", let page = currentRenderer, let url = page.url,
              ["http", "https"].contains(url.scheme ?? "") else {
            throw BrowserFailure.invalid("Open a web address before downloading.")
        }
        let tabID = model.activeTabId
        page.startDownload(using: URLRequest(url: url)) { [weak self] download in
            guard let self else { download.cancel { _ in }; return }
            self.downloads.attach(download, tabID: tabID)
        }
    }

    func exportDownload(_ id: String) throws {
        guard panel == "files", presentedViewController == nil else {
            throw BrowserFailure.invalid("Open the Downloads panel before exporting a file.")
        }
        let file = try downloads.fileURL(id: id)
        present(UIDocumentPickerViewController(forExporting: [file], asCopy: true), animated: true)
    }

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
