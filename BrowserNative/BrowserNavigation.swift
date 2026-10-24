import UIKit
import WebKit

extension BrowserController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if webView === ui {
            let allowed = url.scheme == "http" && url.host == "127.0.0.1" && url.port == Int(server.port)
            decisionHandler(allowed ? .allow : .cancel)
            return
        }
        if navigationAction.shouldPerformDownload, ["http", "https", "blob"].contains(url.scheme ?? "") {
            if navigationAction.targetFrame?.isMainFrame == true {
                expectDownload(webView, url: url, knownNavigation: false)
            }
            decisionHandler(.download); return
        }
        // Web content may navigate its own subframes; the browser address accepts only HTTP(S).
        if navigationAction.targetFrame?.isMainFrame != false {
            if ExternalLinkPolicy.requiresConfirmation(url) {
                decisionHandler(.cancel)
                offerExternalLink(url, from: webView)
                return
            }
            guard url.absoluteString == "about:blank" || (try? AddressResolver.validated(url.absoluteString)) != nil else {
                nativeError = "This navigation requires an unsupported URL scheme."
                publish(); decisionHandler(.cancel); return
            }
            // A new window's destination must not change its opener's navigation/blocking state.
            if navigationAction.targetFrame?.isMainFrame == true {
                downloadTransitions.removeValue(forKey: ObjectIdentifier(webView))
                blocker.apply(to: webView, host: url.host)
            }
        }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if webView === ui {
            let status = (navigationResponse.response as? HTTPURLResponse)?.statusCode ?? 0
            LocalUIServer.diagnostic("Navigation response: \(status), MIME=\(navigationResponse.response.mimeType ?? "nil"), displayable=\(navigationResponse.canShowMIMEType)")
            decisionHandler(.allow); return
        }
        LocalUIServer.diagnostic("Site response: status=\((navigationResponse.response as? HTTPURLResponse)?.statusCode ?? 0), MIME=\(navigationResponse.response.mimeType ?? "nil")")
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        let shouldDownload = !navigationResponse.canShowMIMEType || disposition.lowercased().hasPrefix("attachment")
        if navigationResponse.isForMainFrame {
            blocker.apply(to: webView, host: navigationResponse.response.url?.host)
            if shouldDownload, let url = navigationResponse.response.url { expectDownload(webView, url: url, knownNavigation: true) }
        }
        decisionHandler(shouldDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        guard webView !== ui else { download.cancel { _ in }; return }
        beginDownload(download, from: webView, mainFrame: navigationAction.targetFrame?.isMainFrame == true,
                      url: navigationAction.request.url)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        guard webView !== ui else { download.cancel { _ in }; return }
        beginDownload(download, from: webView, mainFrame: navigationResponse.isForMainFrame,
                      url: navigationResponse.response.url)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView !== ui else { return }
        let key = ObjectIdentifier(webView)
        if let id = renderers.first(where: { $0.value === webView })?.key { invalidatePreview(for: id) }
        media.invalidate(webView)
        if let navigation { currentNavigations[key] = navigation }
        if var transition = downloadTransitions[key] {
            let startedID = navigation.map { String(describing: ObjectIdentifier($0)) }
            if transition.transferred || (transition.navigationID != nil && transition.navigationID != startedID) {
                downloadTransitions.removeValue(forKey: key)
            }
            else if transition.navigationID == nil {
                transition.navigationID = startedID
                downloadTransitions[key] = transition
            }
        }
        update(webView)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard webView !== ui else { return }
        blocker.apply(to: webView, host: webView.url?.host)
        update(webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard webView !== ui else { return }
        blocker.apply(to: webView, host: webView.url?.host)
        media.setPageVisible(webView, visible: !webView.isHidden || (panel == "media" && webView === currentRenderer), force: true)
        update(webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === ui { reportPageDiagnostics("Navigation finished"); publish() }
        else {
            reportPageDiagnostics("Site navigation finished", webView: webView)
            blocker.apply(to: webView, host: webView.url?.host)
            media.setPageVisible(webView, visible: !webView.isHidden || (panel == "media" && webView === currentRenderer), force: true)
            downloadTransitions.removeValue(forKey: ObjectIdentifier(webView))
            update(webView, loading: false)
            let finishedURL = webView.url
            BrowserSiteResource.metadata(in: webView) { [weak self, weak webView] metadata in
                guard let self, let webView, webView.url == finishedURL,
                      let id = self.renderers.first(where: { $0.value === webView })?.key,
                      let index = self.model.tabs.firstIndex(where: { $0.id == id }) else { return }
                let icons = (metadata["iconCandidates"] as? [String] ?? []) + (metadata["faviconCandidates"] as? [String] ?? [])
                self.model.tabs[index].iconUrl = icons.first ?? ""
                if let name = metadata["siteName"] as? String, !name.isEmpty { self.model.tabs[index].siteName = name }
                self.model.save(); self.publish()
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(webView, navigation: navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(webView, navigation: navigation, error: error)
    }

    private func navigationFailed(_ webView: WKWebView, navigation: WKNavigation?, error: Error) {
        let failure = error as NSError
        if webView === ui {
            LocalUIServer.diagnostic("Navigation failed: \(failure.domain) \(failure.code)")
            reportPageDiagnostics("Navigation failed")
            if failure.domain != NSURLErrorDomain || failure.code != NSURLErrorCancelled { nativeError = error.localizedDescription }
            return
        }
        LocalUIServer.diagnostic("Site navigation failed: \(failure.domain) \(failure.code), host=\(webView.url?.host ?? "nil")")
        let key = ObjectIdentifier(webView)
        let navigationID = navigation.map { String(describing: ObjectIdentifier($0)) }
        let failingURL = (failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString
            ?? failure.userInfo[NSURLErrorFailingURLStringErrorKey] as? String
        if var transition = downloadTransitions[key],
           transition.isExpectedInterruption(failure, navigationID: navigationID, failingURL: failingURL) {
            if transition.navigationID == nil { transition.navigationID = navigationID; downloadTransitions[key] = transition }
            if !transition.transferred { finishDownloadNavigation(transition.tabID) }
            return
        }
        // A superseded navigation must not overwrite the new navigation's loading/error state.
        if let current = currentNavigations[key], let navigation, current !== navigation { return }
        let cancelled = failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled
        update(webView, error: cancelled ? nil : error.localizedDescription, loading: false)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === ui { webView.reload() }
        else { media.invalidate(webView); update(webView, error: "WebKit ended this tab's content process. Reload the tab to continue.") }
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        guard webView !== ui, let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let trusted = SiteTrust.evaluate(trust)
        LocalUIServer.diagnostic("Site TLS trust: host=\(challenge.protectionSpace.host), trusted=\(trusted)")
        guard trusted else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard webView !== ui, navigationAction.targetFrame == nil else { return nil }
        do {
            return try createSiteWindow(from: webView, configuration: configuration, url: navigationAction.request.url)
        } catch { nativeError = error.localizedDescription; publish() }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard webView !== ui, let id = renderers.first(where: { $0.value === webView })?.key else { return }
        try? closeTab(id)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard presentedViewController == nil else { completionHandler(); return }
        let alert = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard presentedViewController == nil else { completionHandler(false); return }
        let alert = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        guard presentedViewController == nil else { completionHandler(nil); return }
        let alert = UIAlertController(title: webView.url?.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        present(alert, animated: true)
    }
}
