import UIKit
import WebKit

@MainActor
final class BrowserUIStartup {
    private unowned let browser: BrowserController
    private let cover = UIView()
    private let message = UILabel()
    private let retryButton = UIButton(type: .system)
    private var rootURL: URL?
    private var attemptID: String?
    private var navigation: WKNavigation?
    private var timeout: Task<Void, Never>?
    private var retriesLeft = 0
    var isReady: Bool { rootURL != nil && cover.superview == nil }

    init(browser: BrowserController) {
        self.browser = browser
        cover.backgroundColor = .systemBackground
        cover.accessibilityViewIsModal = true
        message.font = .preferredFont(forTextStyle: .body)
        message.adjustsFontForContentSizeCategory = true
        message.textAlignment = .center
        message.numberOfLines = 0
        message.textColor = .label
        retryButton.setTitle("Повторить", for: .normal)
        retryButton.addAction(UIAction { [weak self] _ in self?.start() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [message, retryButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: cover.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: cover.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: cover.safeAreaLayoutGuide.trailingAnchor, constant: -24)
        ])
    }

    func start() {
        retriesLeft = 1
        if cover.superview == nil {
            cover.frame = browser.view.bounds
            cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            browser.view.addSubview(cover)
        }
        message.text = "Загрузка ATMA…"
        retryButton.isHidden = true
        browser.ui.accessibilityElementsHidden = true
        if let rootURL {
            load(rootURL)
        } else {
            browser.server.start { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let url):
                    self.rootURL = url
                    self.load(url)
                case .failure(let error):
                    self.showFailure("Local UI server: \(error.localizedDescription)")
                }
            }
        }
    }

    func receiveReady(attemptID: String, stylesReady: Bool) {
        guard attemptID == self.attemptID else { return }
        guard stylesReady else { retry("Missing UI stylesheets"); return }
        clearAttempt()
        cover.removeFromSuperview()
        browser.ui.accessibilityElementsHidden = false
    }

    func navigationFailed(_ navigation: WKNavigation?, error: NSError) {
        guard let navigation, navigation === self.navigation else { return }
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        retry("Navigation failed: \(error.domain) \(error.code)")
    }

    func processDidTerminate() {
        if isReady { start() }
        else if attemptID != nil { retry("WebKit UI process terminated") }
    }

    private func load(_ rootURL: URL) {
        clearAttempt()
        browser.ui.stopLoading()
        let id = UUID().uuidString
        let url = rootURL.appending(queryItems: [
            URLQueryItem(name: "startup", value: id),
            URLQueryItem(name: "desktopRegion", value: Locale.autoupdatingCurrent.region?.identifier)
        ])
        attemptID = id
        navigation = browser.ui.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, self.attemptID == id else { return }
            self.retry("UI did not signal readiness")
        }
    }

    private func retry(_ reason: String) {
        guard retriesLeft > 0, let rootURL else { showFailure(reason); return }
        LocalUIServer.diagnostic("Retrying startup: \(reason)")
        retriesLeft -= 1
        load(rootURL)
    }

    private func showFailure(_ reason: String) {
        clearAttempt()
        browser.ui.stopLoading()
        LocalUIServer.diagnostic("Startup failed: \(reason)")
        message.text = "Не удалось загрузить интерфейс ATMA."
        retryButton.isHidden = false
    }

    private func clearAttempt() {
        attemptID = nil
        navigation = nil
        timeout?.cancel()
        timeout = nil
    }
}
