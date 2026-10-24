import UIKit
import WebKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = BrowserController()
        self.window = window
        window.makeKeyAndVisible()
        return true
    }
}

@MainActor
final class BrowserController: UIViewController {
    let model: BrowserModel
    let server = LocalUIServer()
    let blocker = SiteBlocker()
    let downloads = DownloadService()
    lazy var media: BrowserMediaController = {
        let controller = BrowserMediaController()
        controller.isActive = { [weak self] in self?.currentRenderer === $0 }
        controller.blockingEnabled = { [weak self] in self?.blocker.enabled(host: $0.url?.host) ?? true }
        controller.didChange = { [weak self] in self?.publish() }
        return controller
    }()
    private let browserViewport = UIView()
    private var keyboardBottomConstraint: NSLayoutConstraint!
    private var windowBottomConstraint: NSLayoutConstraint!
    var ui: WKWebView!
    var renderers: [String: WKWebView] = [:]
    var windowOpeners: [String: String] = [:]
    var mode = "home"
    var panel: String?
    var nativeError: String?
    var tabPreviews: [String: TabPreview] = [:]
    var previewCaptures: [String: TabPreviewCapture] = [:]
    var deviceRowCollapsed = false
    private var lastLayoutDiagnostic = ""
    var nativeTheme = "auto"
    var currentNavigations: [ObjectIdentifier: WKNavigation] = [:]
    var downloadTransitions: [ObjectIdentifier: DownloadNavigationTransition] = [:]
    static let footerHeight: CGFloat = 166
    var webApp: Bool { mode == "browse" && model.active.webApp == true }
    var controlsCollapsed: Bool { mode == "browse" && !webApp && deviceRowCollapsed }
    var currentFooterHeight: CGFloat {
        if webApp { return 52 + view.safeAreaInsets.bottom }
        return Self.footerHeight - (controlsCollapsed ? 38 : 0)
    }

    init(model: BrowserModel? = nil) {
        self.model = model ?? BrowserModel()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        model = BrowserModel()
        super.init(coder: coder)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { nativeStatusBarStyle }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        browserViewport.translatesAutoresizingMaskIntoConstraints = false
        browserViewport.clipsToBounds = true
        view.addSubview(browserViewport)
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        let safe = view.safeAreaLayoutGuide
        keyboardBottomConstraint = browserViewport.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        windowBottomConstraint = browserViewport.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            browserViewport.topAnchor.constraint(equalTo: safe.topAnchor),
            browserViewport.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            browserViewport.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            windowBottomConstraint
        ])
        for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardWillHideNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardPresentationChanged(_:)), name: name, object: nil)
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        if LocalUIServer.diagnosticsEnabled {
            let source = """
            window.__atmaStartupErrors = [];
            const recordStartupError = value => {
                if (window.__atmaStartupErrors.length < 20) window.__atmaStartupErrors.push(String(value).slice(0, 300));
            };
            addEventListener('error', event => recordStartupError(event.message || ('resource: ' + (event.target.src || event.target.href || event.target.tagName))), true);
            addEventListener('unhandledrejection', event => recordStartupError(event.reason));
            """
            configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "atma")
        ui = WKWebView(frame: .zero, configuration: configuration)
        ui.accessibilityIdentifier = "atma.ui"
        ui.navigationDelegate = self
        ui.isOpaque = false
        ui.backgroundColor = .systemBackground
        ui.scrollView.isScrollEnabled = false
        ui.scrollView.contentInsetAdjustmentBehavior = .never
        browserViewport.addSubview(ui)
        downloads.didChange = { [weak self] tabID, error in
            guard let self else { return }
            if let error {
                if let index = self.model.tabs.firstIndex(where: { $0.id == tabID }) {
                    self.model.tabs[index].error = error
                    self.model.save()
                } else { self.nativeError = error }
            }
            self.publish()
        }
        blocker.didChange = { [weak self] in self?.publish() }
        server.start { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url): self.ui.load(URLRequest(url: url))
            case .failure(let error): self.showStartupFailure(error)
            }
        }
        if LocalUIServer.diagnosticsEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.reportPageDiagnostics("15 seconds") }
        }
    }

    @objc private func keyboardPresentationChanged(_ notification: Notification) {
        guard view.window != nil, notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool != false else { return }
        let visible = notification.name == UIResponder.keyboardWillShowNotification
        if LocalUIServer.diagnosticsEnabled { LocalUIServer.diagnostic("Keyboard presentation: visible=\(visible)") }
        guard keyboardBottomConstraint.isActive != visible else { return }
        view.layoutIfNeeded()
        // The keyboard guide can retain an accessory-height inset after dismissal.
        // Track the guide only while the system keyboard is presented.
        if visible {
            windowBottomConstraint.isActive = false
            keyboardBottomConstraint.isActive = true
        } else {
            keyboardBottomConstraint.isActive = false
            windowBottomConstraint.isActive = true
        }
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 0
        UIView.animate(withDuration: duration, delay: 0, options: [UIView.AnimationOptions(rawValue: curve << 16), .beginFromCurrentState, .allowUserInteraction]) {
            self.view.layoutIfNeeded()
        }
    }

    func reportPageDiagnostics(_ stage: String, webView: WKWebView? = nil) {
        guard LocalUIServer.diagnosticsEnabled, let page = webView ?? ui else { return }
        LocalUIServer.diagnostic("\(stage): loading=\(page.isLoading), host=\(page.url?.host ?? "nil"), port=\(page.url?.port ?? 0)")
        page.evaluateJavaScript("JSON.stringify({ready:document.readyState,title:document.title,bodyChildren:document.body?.children.length||0,home:!!document.getElementById('go-home'),mode:document.body?.dataset.mode,heading:document.querySelector('h1')?.textContent?.slice(0,100),errors:window.__atmaStartupErrors||[]})") { result, error in
            if let error {
                let failure = error as NSError
                LocalUIServer.diagnostic("DOM evaluation: \(failure.domain) \(failure.code)")
            } else { LocalUIServer.diagnostic("DOM: \(result as? String ?? "nil")") }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let frame = browserViewport.bounds
        let browsing = mode == "browse" && panel == nil
        ui.frame = browsing ? CGRect(x: frame.minX, y: max(frame.minY, frame.maxY - currentFooterHeight),
                                     width: frame.width, height: min(currentFooterHeight, frame.height)) : frame
        for (id, renderer) in renderers {
            renderer.isHidden = !browsing || id != model.activeTabId
            media.setPageVisible(renderer, visible: !renderer.isHidden || (panel == "media" && id == model.activeTabId))
            renderer.frame = CGRect(x: frame.minX, y: frame.minY, width: frame.width,
                                    height: max(0, frame.height - currentFooterHeight))
        }
        browserViewport.bringSubviewToFront(ui)
        if LocalUIServer.diagnosticsEnabled {
            let geometry = "mode=\(mode), root=\(view.bounds), viewport=\(browserViewport.frame), ui=\(ui.frame), keyboard=\(view.keyboardLayoutGuide.layoutFrame), safe=\(view.safeAreaInsets), footer=\(currentFooterHeight)"
            if geometry != lastLayoutDiagnostic { lastLayoutDiagnostic = geometry; LocalUIServer.diagnostic("Layout: " + geometry) }
        }
        publish()
    }

    var currentRenderer: WKWebView? { renderers[model.activeTabId] }

    func renderer(for tab: BrowserTab, configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        if let renderer = renderers[tab.id] { return renderer }
        // Keep WebKit's supplied window configuration, including its opener relationship.
        let config = configuration ?? WKWebViewConfiguration()
        config.websiteDataStore = model.store(for: tab.profileId)
        // A popup must not share script handlers or mutable script lists with its opener.
        config.userContentController = WKUserContentController()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        // The page adapter gates intent without preventing WebKit metadata preload.
        config.mediaTypesRequiringUserActionForPlayback = []
        let profile = model.profile(tab.profileId)
        if tab.profileId != BrowserModel.actualProfile, let mobile = profile?["mobile"] as? Bool {
            config.defaultWebpagePreferences.preferredContentMode = mobile ? .mobile : .desktop
        } else {
            config.defaultWebpagePreferences.preferredContentMode = .recommended
        }
        // Website content receives only a bounded media-state handler, never UI RPC.
        let renderer = WKWebView(frame: .zero, configuration: config)
        renderer.accessibilityIdentifier = "atma.site." + tab.id
        renderer.navigationDelegate = self
        renderer.uiDelegate = self
        renderer.allowsBackForwardNavigationGestures = true
        renderer.scrollView.contentInsetAdjustmentBehavior = .never
        media.register(renderer, tabID: tab.id)
        if tab.profileId != BrowserModel.actualProfile {
            renderer.customUserAgent = profile?["userAgent"] as? String
        }
        blocker.apply(to: renderer, host: URL(string: tab.url)?.host)
        renderers[tab.id] = renderer
        browserViewport.insertSubview(renderer, belowSubview: ui)
        return renderer
    }

    func open(_ input: String, profileID: String? = nil, webApp: Bool? = nil) throws {
        let url = try AddressResolver.resolve(input, engine: model.preferences.searchEngine)
        try open(URLRequest(url: url), profileID: profileID, webApp: webApp)
    }

    func open(_ request: URLRequest, profileID: String? = nil, webApp: Bool? = nil) throws {
        guard let url = request.url else { throw BrowserFailure.invalid("Missing navigation URL.") }
        _ = try AddressResolver.validated(url.absoluteString)
        if let profileID {
            guard model.profile(profileID) != nil else { throw BrowserFailure.invalid("Unknown shortcut profile.") }
            if model.active.profileId != profileID {
                removeRenderer(for: model.activeTabId)
                model.tabs[model.activeIndex].profileId = profileID
            }
        }
        if let webApp {
            model.tabs[model.activeIndex].webApp = webApp
            model.tabs[model.activeIndex].appControlsCollapsed = false
        }
        // End the native WebKit input session before shrinking its view into chrome.
        view.endEditing(true)
        model.tabs[model.activeIndex].url = url.absoluteString
        model.tabs[model.activeIndex].error = nil
        mode = "browse"; panel = nil; nativeError = nil
        let renderer = renderer(for: model.active)
        blocker.apply(to: renderer, host: url.host)
        renderer.load(request)
        changed()
    }

    func selectTab(_ id: String) throws {
        guard model.tabs.contains(where: { $0.id == id }) else { throw BrowserFailure.invalid("Unknown tab.") }
        model.activeTabId = id; panel = nil
        let tab = model.active
        mode = tab.url.isEmpty ? "home" : "browse"
        if !tab.url.isEmpty, renderers[id] == nil {
            // about:blank is an internal site-window document, not an address-bar input.
            let url: URL?
            if tab.url == "about:blank" { url = URL(string: tab.url) }
            else { url = try? AddressResolver.validated(tab.url) }
            if let url { renderer(for: tab).load(URLRequest(url: url)) }
        }
        changed()
    }

    func newTab(profile: String? = nil) {
        let tab = BrowserTab(profileId: profile ?? model.active.profileId)
        model.tabs.append(tab); model.activeTabId = tab.id; mode = "home"; panel = nil
        changed()
    }

    func closeTab(_ id: String) throws {
        guard let index = model.tabs.firstIndex(where: { $0.id == id }) else { throw BrowserFailure.invalid("Unknown tab.") }
        let opener = windowOpeners.removeValue(forKey: id)
        windowOpeners = windowOpeners.filter { $0.value != id }
        removeRenderer(for: id)
        model.tabs.remove(at: index)
        if model.tabs.isEmpty { newTab(profile: BrowserModel.actualProfile) }
        else if model.activeTabId == id {
            let destination = opener.flatMap { candidate in model.tabs.first { $0.id == candidate }?.id }
                ?? model.tabs[min(index, model.tabs.count - 1)].id
            try selectTab(destination)
        }
        changed()
    }

    func changeProfile(_ id: String) throws {
        guard model.profile(id) != nil else { throw BrowserFailure.invalid("Unknown profile.") }
        guard id != model.active.profileId else { return }
        removeRenderer(for: model.activeTabId)
        model.tabs[model.activeIndex].profileId = id
        if mode == "browse", !model.active.url.isEmpty { try selectTab(model.activeTabId) }
        changed()
    }

    private func removeRenderer(for id: String) {
        invalidatePreview(for: id)
        if let renderer = renderers.removeValue(forKey: id) {
            media.unregister(renderer)
            renderer.stopLoading()
            cleanupNavigation(for: renderer)
            renderer.removeFromSuperview()
        }
    }

    func changed() {
        model.save()
        view.setNeedsLayout()
        publish()
    }

    func state() -> [String: Any] {
        let tab = model.active
        let host = URL(string: tab.url)?.host
        let frame = browserViewport.bounds
        return ["id": "ios", "deviceName": UIDevice.current.model, "profileId": tab.profileId,
                "mode": mode, "panel": panel as Any? ?? NSNull(), "url": tab.url, "title": tab.title,
                "siteName": tab.siteName, "iconUrl": tab.iconUrl,
                "width": frame.width, "height": frame.height, "footerHeight": currentFooterHeight,
                "webApp": webApp, "controlsCollapsed": controlsCollapsed,
                "loading": tab.loading, "error": nativeError as Any? ?? tab.error as Any? ?? NSNull(),
                "capabilities": ["cookies": true, "downloads": true, "tabs": true,
                                 "persistentProfiles": true, "contentBlocking": blocker.available, "media": true,
                                 "fullFingerprintEmulation": false, "localeEmulation": false,
                                 "timezoneEmulation": false, "sync": false, "push": false,
                                 "translation": false, "googleAccount": false, "probe": false],
                "searchEngine": model.preferences.searchEngine, "locale": model.preferences.locale,
                "timezone": model.preferences.timezone, "profiles": model.profiles,
                "tabs": model.tabs.map(\.json), "activeTabId": model.activeTabId, "media": media.state,
                "blocker": ["available": blocker.available, "enabled": blocker.enabled(host: host),
                            "host": host as Any? ?? NSNull(), "error": blocker.error as Any? ?? NSNull()]]
    }

    func publish() {
        guard ui != nil, ui.url?.host == "127.0.0.1", ui.url?.port == Int(server.port) else { return }
        ui.callAsyncJavaScript("window.dispatchEvent(new CustomEvent('atma-native-state', {detail: state}));",
                              arguments: ["state": state()], in: nil, in: .page, completionHandler: nil)
    }

    func update(_ webView: WKWebView, error: String? = nil, loading: Bool? = nil) {
        guard let entry = renderers.first(where: { $0.value === webView }),
              let index = model.tabs.firstIndex(where: { $0.id == entry.key }) else { return }
        if let url = webView.url, ["http", "https"].contains(url.scheme ?? "") || url.absoluteString == "about:blank" {
            if model.tabs[index].url != url.absoluteString { model.tabs[index].iconUrl = "" }
            model.tabs[index].url = url.absoluteString
            model.tabs[index].siteName = url.host ?? ""
        }
        model.tabs[index].title = webView.title ?? ""
        model.tabs[index].loading = loading ?? webView.isLoading
        model.tabs[index].error = error
        model.save(); publish()
    }

    private func showStartupFailure(_ error: Error) {
        nativeError = error.localizedDescription
        let label = UILabel(frame: view.safeAreaLayoutGuide.layoutFrame)
        label.numberOfLines = 0; label.textAlignment = .center
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.text = "ATMA UI could not start.\n" + error.localizedDescription
        ui.isHidden = true; view.addSubview(label)
    }
}
