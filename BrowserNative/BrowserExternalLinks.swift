import UIKit
import WebKit

enum ExternalLinkPolicy {
    // Web documents and executable/local URLs stay within the browser's own policy.
    private static let internalSchemes: Set<String> = [
        "http", "https", "about", "blob", "data", "file", "javascript", "vbscript", "atma-ui", "itms-services"
    ]

    static func requiresConfirmation(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), !scheme.isEmpty else { return false }
        return !internalSchemes.contains(scheme)
    }
}

extension BrowserController {
    func offerExternalLink(_ url: URL, from page: WKWebView) {
        // A hidden/background page cannot bring another application forward.
        guard page === currentRenderer, !page.isHidden, panel == nil,
              UIApplication.shared.applicationState == .active,
              presentedViewController == nil else { return }
        let russian = Locale.preferredLanguages.first?.hasPrefix("ru") == true
        let scheme = url.scheme ?? ""
        let origin = page.url?.host ?? (russian ? "Сайт" : "This website")
        let title = russian ? "Открыть другое приложение?" : "Open another app?"
        let message = russian ? "\(origin) предлагает открыть ссылку «\(scheme)»." : "\(origin) wants to open a \(scheme) link."
        let dialog = UIAlertController(title: title, message: message, preferredStyle: .alert)
        dialog.addAction(UIAlertAction(title: russian ? "Отмена" : "Cancel", style: .cancel))
        dialog.addAction(UIAlertAction(title: russian ? "Открыть" : "Open", style: .default) { [weak self] _ in
            UIApplication.shared.open(url, options: [:]) { success in
                guard !success else { return }
                DispatchQueue.main.async {
                    self?.nativeError = russian ? "На устройстве нет приложения для этой ссылки." : "No app is available for this link."
                    self?.publish()
                }
            }
        })
        present(dialog, animated: true)
    }
}
